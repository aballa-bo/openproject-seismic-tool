"""Damage detection on one image: MSD-Det detector + crack segmentation cascade.

Modes (job params["mode"]):
  cascade    detector (7 damage classes) + YOLO-seg crack masks inside the "Cracks" boxes
  detector   detector only
  crack_only whole-image crack segmentation, no detector
"""
from __future__ import annotations

import logging
import time
from pathlib import Path

import cv2
import numpy as np

from .config import Config
from . import crack_overlay as co

log = logging.getLogger("seismic.pipeline")

CLASSES = ["Cracks", "Fabric loss of masonry units", "Surface dissolution", "Efflorescence",
           "Discolouration", "Plant", "Moss"]


class Pipeline:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self._det = None
        self._seg = None
        import torch
        torch.set_num_threads(cfg.threads)
        cv2.setNumThreads(cfg.threads)
        self.torch = torch

    # models are loaded lazily and kept in memory (only the ones a job needs)
    def _load(self, name: str):
        from ultralytics import YOLO
        path = self.cfg.models_dir / name
        if not path.is_file():
            raise FileNotFoundError(f"model weights not found: {path}")
        log.info("loading %s", path)
        return YOLO(str(path))

    @property
    def detector(self):
        if self._det is None:
            self._det = self._load(self.cfg.detector_weights)
        return self._det

    @property
    def segmenter(self):
        if self._seg is None:
            self._seg = self._load(self.cfg.crack_weights)
        return self._seg

    def process(self, source: str, params: dict, out_dir: Path, stem: str) -> dict:
        from .imageio import load_bgr
        t0 = time.time()
        mode = params.get("mode", "cascade")
        conf = float(params.get("conf", 0.25))
        crack_conf = float(params.get("crack_conf", 0.25))
        imgsz = int(params.get("imgsz", 1280))

        bgr = load_bgr(source)
        H, W = bgr.shape[:2]
        dets = []          # (class, confidence, xyxy, mask-or-None)
        full = np.zeros((H, W), bool)

        with self.torch.inference_mode():
            if mode == "crack_only":
                full, cracks = co.segment_whole_image(self.segmenter, bgr, conf=crack_conf, device="cpu")
                dets = [("Cracks", c, xyxy, m) for c, xyxy, m in cracks]
            else:
                r = self.detector.predict(bgr, imgsz=imgsz, conf=conf, iou=0.5, device="cpu", verbose=False)[0]
                names = self.detector.names
                dets = [(names[int(b.cls)], float(b.conf), b.xyxy[0].tolist(), None) for b in r.boxes]
                if mode == "cascade":
                    idx = [i for i, d in enumerate(dets) if d[0] == "Cracks"]
                    if idx:
                        full, per_box = co.segment_cracks(self.segmenter, bgr, [dets[i][2] for i in idx],
                                                          conf=crack_conf, device="cpu")
                        for i, m in zip(idx, per_box):
                            dets[i] = (dets[i][0], dets[i][1], dets[i][2], m)

        records, summary = [], {}
        for cls, c, xyxy, mask in dets:
            rec = {"class": cls, "confidence": round(float(c), 4), "box": [round(float(v), 1) for v in xyxy]}
            if mask is not None and mask.any():
                st = co.crack_stats(mask)
                rec.update(area_px=st["crack_area_px"], length_px=st["crack_length_px"],
                           mean_width_px=st["crack_mean_width_px"])
            records.append(rec)
            summary[cls] = summary.get(cls, 0) + 1

        out_dir.mkdir(parents=True, exist_ok=True)
        overlay_path = out_dir / f"{stem}_overlay.jpg"
        mask_path = None
        lw = max(2, round(max(H, W) / 600))
        over = co.draw_overlay(bgr, full) if full.any() else bgr
        over = co.draw_boxes(over, [(c, p, b) for c, p, b, _ in dets], lw=lw)
        over = self._shrink(over)
        cv2.imwrite(str(overlay_path), over, [cv2.IMWRITE_JPEG_QUALITY, 85])
        if full.any():
            mask_path = out_dir / f"{stem}_mask.png"
            cv2.imwrite(str(mask_path), self._shrink(full.astype(np.uint8) * 255, nearest=True))

        return {"detections": records, "summary": summary, "width": W, "height": H,
                "overlay_path": str(overlay_path), "mask_path": str(mask_path) if mask_path else None,
                "duration_ms": int((time.time() - t0) * 1000)}

    def _shrink(self, img, nearest=False):
        side = self.cfg.jpeg_max_side
        h, w = img.shape[:2]
        if max(h, w) <= side:
            return img
        s = side / max(h, w)
        return cv2.resize(img, (round(w * s), round(h * s)),
                          interpolation=cv2.INTER_NEAREST if nearest else cv2.INTER_AREA)
