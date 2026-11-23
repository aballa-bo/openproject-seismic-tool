"""Entry point: python -m seismic_worker"""
from __future__ import annotations

import logging
import os
import signal
import sys
import time
import traceback
from pathlib import Path

from .config import Config
from .queue import Queue

log = logging.getLogger("seismic")
_stop = False


def _lower_priority():
    """Make this process as unobtrusive as possible (in addition to the systemd unit settings)."""
    try:
        os.nice(19)
    except OSError:
        pass
    try:  # SCHED_IDLE: runs only when a CPU would otherwise be idle (no privileges needed)
        os.sched_setscheduler(0, os.SCHED_IDLE, os.sched_param(0))
    except (AttributeError, OSError):
        pass
    try:  # best-effort idle I/O class
        import subprocess
        subprocess.run(["ionice", "-c", "3", "-p", str(os.getpid())], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def _load_per_core() -> float:
    try:
        return os.getloadavg()[0] / (os.cpu_count() or 1)
    except OSError:
        return 0.0


def _busy(cfg: Config) -> bool:
    return _load_per_core() > cfg.max_load


def _sleep(seconds: float):
    end = time.time() + seconds
    while not _stop and time.time() < end:
        time.sleep(min(0.5, end - time.time()))


def main() -> int:
    global _stop
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    cfg = Config.from_env()
    _lower_priority()

    def _handler(*_):
        global _stop
        _stop = True
        log.info("stopping after the current image")
    signal.signal(signal.SIGTERM, _handler)
    signal.signal(signal.SIGINT, _handler)

    q = Queue(cfg.database_url, cfg.worker_name, should_stop=lambda: _stop)
    q.recover_stale()
    from .pipeline import Pipeline
    pipe = Pipeline(cfg)
    log.info("worker %s ready (threads=%d, models in %s)", cfg.worker_name, cfg.threads, cfg.models_dir)

    last_beat = 0.0
    while not _stop:
        if time.time() - last_beat > 30:
            q.heartbeat(None, {"state": "idle"})
            last_beat = time.time()
        if _busy(cfg):
            # tell the web UI why nothing is happening
            if time.time() - last_beat > 15:
                q.heartbeat(None, {"state": "waiting_load", "load_per_core": round(_load_per_core(), 1),
                                   "limit": cfg.max_load})
                last_beat = time.time()
            _sleep(cfg.poll_seconds * 2)
            continue
        task = q.claim()
        if task is None:
            _sleep(cfg.poll_seconds)
            continue
        q.heartbeat(task.job_id, {"image": task.filename})
        last_beat = time.time()
        log.info("job %d: %s", task.job_id, task.filename)
        try:
            if not task.source_path or not os.path.isfile(task.source_path):
                raise FileNotFoundError(f"source image not found: {task.source_path}")
            out = pipe.process(task.source_path, task.params, Path(task.output_dir), f"r{task.result_id}")
            q.finish(task, ok=True, **out)
            log.info("  done in %.1f s: %s", out["duration_ms"] / 1000, out["summary"] or "no damage")
        except Exception as e:  # noqa: BLE001 - one bad image must not stop the queue
            log.error("  failed: %s\n%s", e, traceback.format_exc())
            q.finish(task, ok=False, error=f"{type(e).__name__}: {e}")
        _sleep(cfg.pause_seconds)

    q.heartbeat()
    return 0


if __name__ == "__main__":
    sys.exit(main())
