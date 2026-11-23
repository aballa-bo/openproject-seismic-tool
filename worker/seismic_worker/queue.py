"""Database-backed job queue (PostgreSQL, tables created by the Rails migration).

One queue entry = one image (seismic_image_results row). Claiming uses
SELECT ... FOR UPDATE SKIP LOCKED, so several workers could run safely, although
one low-priority worker is the intended setup.
"""
from __future__ import annotations

import json
import logging
import time
from dataclasses import dataclass

import psycopg2
import psycopg2.extras

log = logging.getLogger("seismic.queue")


@dataclass
class Task:
    result_id: int
    job_id: int
    filename: str
    source_path: str
    params: dict
    output_dir: str


class Queue:
    def __init__(self, dsn: str, worker_name: str, should_stop=lambda: False):
        self.dsn = dsn
        self.should_stop = should_stop
        self.worker = worker_name
        self.conn = None
        self._connect()

    # -- connection ---------------------------------------------------------
    def _connect(self):
        while True:
            try:
                self.conn = psycopg2.connect(self.dsn)
                self.conn.autocommit = True
                return
            except psycopg2.Error as e:
                if self.should_stop():
                    raise SystemExit(0)
                log.error("database unavailable (%s); retrying in 10 s", str(e).strip())
                for _ in range(20):
                    if self.should_stop():
                        raise SystemExit(0)
                    time.sleep(0.5)

    def _run(self, sql, args=(), fetch=None):
        for attempt in (1, 2):
            try:
                with self.conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                    cur.execute(sql, args)
                    if fetch == "one":
                        return cur.fetchone()
                    if fetch == "all":
                        return cur.fetchall()
                    return cur.rowcount
            except (psycopg2.OperationalError, psycopg2.InterfaceError):
                if attempt == 2:
                    raise
                log.warning("database connection lost, reconnecting")
                self._connect()

    # -- worker lifecycle -----------------------------------------------------
    def recover_stale(self):
        """At startup nothing can be running: put interrupted images back in the queue."""
        n = self._run("UPDATE seismic_image_results SET status='queued', started_at=NULL, updated_at=now() "
                      "WHERE status='running'")
        if n:
            log.info("re-queued %d interrupted image(s)", n)
        self._run("UPDATE seismic_jobs SET status='queued', updated_at=now() "
                  "WHERE status='running' AND NOT EXISTS (SELECT 1 FROM seismic_image_results r "
                  "WHERE r.seismic_job_id = seismic_jobs.id AND r.status = 'done')")

    def heartbeat(self, job_id=None, info=None):
        self._run(
            "INSERT INTO seismic_worker_status (name, beat_at, current_job_id, info) VALUES (%s, now(), %s, %s) "
            "ON CONFLICT (name) DO UPDATE SET beat_at = now(), current_job_id = EXCLUDED.current_job_id, "
            "info = EXCLUDED.info",
            (self.worker, job_id, json.dumps(info or {})))

    # -- tasks ---------------------------------------------------------------
    def claim(self) -> Task | None:
        row = self._run(
            """
            UPDATE seismic_image_results r SET status='running', started_at=now(), updated_at=now()
            FROM (
              SELECT r2.id FROM seismic_image_results r2
              JOIN seismic_jobs j ON j.id = r2.seismic_job_id
              WHERE r2.status = 'queued' AND j.status IN ('queued', 'running')
              ORDER BY j.priority DESC, j.id ASC, r2.id ASC
              FOR UPDATE OF r2 SKIP LOCKED LIMIT 1
            ) pick
            WHERE r.id = pick.id
            RETURNING r.id, r.seismic_job_id, r.filename, r.source_path
            """, fetch="one")
        if not row:
            return None
        job = self._run("UPDATE seismic_jobs SET status = CASE WHEN status='queued' THEN 'running' ELSE status END, "
                        "started_at = COALESCE(started_at, now()), updated_at = now() WHERE id = %s "
                        "RETURNING params, output_dir", (row["seismic_job_id"],), fetch="one")
        return Task(row["id"], row["seismic_job_id"], row["filename"], row["source_path"],
                    job["params"] or {}, job["output_dir"] or "")

    def finish(self, task: Task, *, ok: bool, detections=None, summary=None, width=None, height=None,
               overlay_path=None, mask_path=None, error=None, duration_ms=None):
        self._run(
            "UPDATE seismic_image_results SET status=%s, detections=%s, summary=%s, width=%s, height=%s, "
            "overlay_path=%s, mask_path=%s, error=%s, duration_ms=%s, finished_at=now(), updated_at=now() "
            "WHERE id=%s AND status='running'",
            ("done" if ok else "failed", json.dumps(detections or []), json.dumps(summary or {}), width, height,
             overlay_path, mask_path, (error or None) and str(error)[:2000], duration_ms, task.result_id))
        self._refresh_job(task.job_id)

    def _refresh_job(self, job_id: int):
        self._run(
            """
            UPDATE seismic_jobs j SET
              done_images = c.done, failed_images = c.failed, updated_at = now(),
              status = CASE
                WHEN j.status = 'cancelled' THEN 'cancelled'
                WHEN c.pending > 0 THEN 'running'
                WHEN c.done = 0 AND c.failed > 0 THEN 'failed'
                ELSE 'done' END,
              finished_at = CASE WHEN j.status <> 'cancelled' AND c.pending = 0 THEN now() ELSE j.finished_at END
            FROM (
              SELECT count(*) FILTER (WHERE status='done') AS done,
                     count(*) FILTER (WHERE status='failed') AS failed,
                     count(*) FILTER (WHERE status IN ('queued','running')) AS pending
              FROM seismic_image_results WHERE seismic_job_id = %s
            ) c
            WHERE j.id = %s
            """, (job_id, job_id))
