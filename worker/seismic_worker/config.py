"""Configuration, read from environment variables (see systemd/worker.env.example)."""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Config:
    database_url: str
    models_dir: Path
    detector_weights: str   # file name inside models_dir
    crack_weights: str
    threads: int            # torch / OpenCV threads
    poll_seconds: float     # idle polling interval
    pause_seconds: float    # pause between two images
    max_load: float         # do not start an image while loadavg(1m) per core exceeds this
    worker_name: str
    jpeg_max_side: int      # overlay images are downscaled to this side

    @staticmethod
    def from_env() -> "Config":
        url = os.environ.get("SEISMIC_DATABASE_URL") or os.environ.get("DATABASE_URL")
        if not url:
            raise SystemExit("SEISMIC_DATABASE_URL (or DATABASE_URL) is not set")
        return Config(
            database_url=url,
            models_dir=Path(os.environ.get("SEISMIC_MODELS_DIR", "/var/db/openproject/seismic_tool/models")),
            detector_weights=os.environ.get("SEISMIC_DETECTOR_WEIGHTS", "masonry_det.pt"),
            crack_weights=os.environ.get("SEISMIC_CRACK_WEIGHTS", "crack_seg.pt"),
            threads=max(1, int(os.environ.get("SEISMIC_THREADS", "2"))),
            poll_seconds=float(os.environ.get("SEISMIC_POLL_SECONDS", "5")),
            pause_seconds=float(os.environ.get("SEISMIC_PAUSE_SECONDS", "1")),
            max_load=float(os.environ.get("SEISMIC_MAX_LOAD_PER_CORE", "4.0")),
            worker_name=os.environ.get("SEISMIC_WORKER_NAME", os.uname().nodename),
            jpeg_max_side=int(os.environ.get("SEISMIC_JPEG_MAX_SIDE", "2400")),
        )
