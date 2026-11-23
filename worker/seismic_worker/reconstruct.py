"""Single image -> 3D relief (coloured point cloud + triangle mesh).

Approach (same idea as common monocular-depth demos, implemented from scratch):
  1. relative depth from a pretrained monocular network (Depth Anything V2, via transformers);
  2. optional crack segmentation (the same YOLO-seg model used by the damage detection):
     crack pixels are tinted red and optionally engraved into the surface;
  3. pinhole back-projection of every pixel (estimated intrinsics, fx = fy = 1.2 * width);
  4. the depth grid is triangulated (two triangles per 2x2 block), skipping triangles that
     span a large depth jump, so foreground and background are not "welded" together.

The result is a 2.5D relief with relative (non-metric) scale: the back of the object is unknown.
Files are written y-up / z towards the viewer, so they open upright in Blender or MeshLab.
"""
from __future__ import annotations

import logging
import time
from pathlib import Path

import cv2
import numpy as np

from .config import Config

log = logging.getLogger("seismic.reconstruct")

HF_ID = "depth-anything/Depth-Anything-V2-Small-hf"


class Reconstructor:
    def __init__(self, cfg: Config, pipeline):
        self.cfg = cfg
        self.pipe = pipeline          # shared with the damage pipeline (torch, crack segmenter)
        self._proc = None
        self._net = None

    # -- depth network -----------------------------------------------------------
    def _load_depth(self):
        if self._net is not None:
            return
        from transformers import AutoImageProcessor, AutoModelForDepthEstimation
        local = self.cfg.models_dir / self.cfg.depth_model
        src = str(local) if local.is_dir() else HF_ID
        log.info("loading depth model from %s", src)
        self._proc = AutoImageProcessor.from_pretrained(src)
        self._net = AutoModelForDepthEstimation.from_pretrained(src).eval()

    def _disparity(self, rgb: np.ndarray) -> np.ndarray:
        """Relative inverse depth, larger = closer, resized to the image, normalised to 0..1."""
        from PIL import Image
        torch = self.pipe.torch
        self._load_depth()
        h, w = rgb.shape[:2]
        inputs = self._proc(images=Image.fromarray(rgb), return_tensors="pt")
        with torch.inference_mode():
            pred = self._net(**inputs).predicted_depth
            pred = torch.nn.functional.interpolate(pred.unsqueeze(1), size=(h, w), mode="bicubic",
                                                   align_corners=False).squeeze().cpu().numpy()
        lo, hi = np.percentile(pred, [1, 99])
        return np.clip((pred - lo) / max(hi - lo, 1e-6), 0, 1).astype(np.float32)

    # -- main entry --------------------------------------------------------------
    def process(self, source: str, params: dict, out_dir: Path) -> dict:
        from .imageio import load_bgr
        t0 = time.time()
        max_side = int(params.get("max_side", 1024))
        mesh_side = int(params.get("mesh_side", 320))
        max_points = int(params.get("max_points", 250000))
        highlight = bool(params.get("highlight_cracks", True))
        groove = float(params.get("groove", 0.04))
        crack_conf = float(params.get("crack_conf", 0.25))

        bgr = load_bgr(source)
        H0, W0 = bgr.shape[:2]
        s = min(1.0, max_side / max(H0, W0))
        if s < 1.0:
            bgr = cv2.resize(bgr, (round(W0 * s), round(H0 * s)), interpolation=cv2.INTER_AREA)
        H, W = bgr.shape[:2]
        rgb = np.ascontiguousarray(bgr[:, :, ::-1])

        disp = self._disparity(rgb)
        z = 1.0 / (0.3 + disp)                       # relative depth, ~0.8 (near) .. 3.3 (far)

        crack = np.zeros((H, W), np.float32)
        crack_px = 0
        if highlight and (self.cfg.models_dir / self.cfg.crack_weights).is_file():
            from . import crack_overlay as co
            with self.pipe.torch.inference_mode():
                full, _ = co.segment_whole_image(self.pipe.segmenter, bgr, conf=crack_conf, device="cpu")
            crack = full.astype(np.float32)
            crack_px = int(full.sum())
        if crack_px and groove > 0:
            z = z * (1.0 + groove * cv2.GaussianBlur(crack, (0, 0), 1.0))

        out_dir.mkdir(parents=True, exist_ok=True)
        colors = rgb.copy()
        colors[crack > 0.5] = (230, 30, 30)

        pts, cols = self._pointcloud(z, colors, max_points)
        self._write_ply(out_dir / "pointcloud.ply", pts, cols)

        verts, faces, vcols = self._mesh(z, colors, mesh_side)
        self._write_ply(out_dir / "mesh.ply", verts, vcols, faces)
        self._write_obj(out_dir / "mesh.obj", verts, vcols, faces)

        d8 = (255 * (1 - (z - z.min()) / max(float(np.ptp(z)), 1e-6))).astype(np.uint8)  # bright = near
        cv2.imwrite(str(out_dir / "depth.png"), cv2.applyColorMap(d8, cv2.COLORMAP_VIRIDIS))
        cv2.imwrite(str(out_dir / "input.jpg"), bgr, [cv2.IMWRITE_JPEG_QUALITY, 88])

        return {"width": W, "height": H, "crack_pixels": crack_px, "points": int(len(pts)),
                "vertices": int(len(verts)), "faces": int(len(faces)),
                "files": ["pointcloud.ply", "mesh.ply", "mesh.obj", "depth.png", "input.jpg"],
                "duration_ms": int((time.time() - t0) * 1000)}

    # -- geometry ----------------------------------------------------------------
    @staticmethod
    def _xyz(z: np.ndarray, W0: int, H0: int) -> np.ndarray:
        h, w = z.shape
        f = 1.2 * w
        u, v = np.meshgrid(np.arange(w, dtype=np.float32), np.arange(h, dtype=np.float32))
        x = (u - w / 2) * z / f
        y = -(v - h / 2) * z / f
        return np.stack([x, y, -z], axis=-1)

    def _pointcloud(self, z, colors, max_points):
        xyz = self._xyz(z, 0, 0).reshape(-1, 3)
        cols = colors.reshape(-1, 3)
        if len(xyz) > max_points:
            idx = np.random.default_rng(0).choice(len(xyz), max_points, replace=False)
            xyz, cols = xyz[idx], cols[idx]
        return xyz.astype(np.float32), cols.astype(np.uint8)

    def _mesh(self, z, colors, side, edge_ratio=0.08):
        h, w = z.shape
        s = min(1.0, side / max(h, w))
        if s < 1.0:
            size = (max(2, round(w * s)), max(2, round(h * s)))
            z = cv2.resize(z, size, interpolation=cv2.INTER_AREA)
            colors = cv2.resize(colors, size, interpolation=cv2.INTER_AREA)
        h, w = z.shape
        verts = self._xyz(z, 0, 0).reshape(-1, 3).astype(np.float32)
        vcols = colors.reshape(-1, 3).astype(np.uint8)
        idx = np.arange(h * w, dtype=np.int32).reshape(h, w)
        a, b, c, d = idx[:-1, :-1], idx[:-1, 1:], idx[1:, :-1], idx[1:, 1:]
        zq = np.stack([z[:-1, :-1], z[:-1, 1:], z[1:, :-1], z[1:, 1:]])
        ok = (zq.max(0) - zq.min(0)) <= edge_ratio * zq.mean(0)
        t1 = np.stack([a[ok], c[ok], b[ok]], axis=1)
        t2 = np.stack([b[ok], c[ok], d[ok]], axis=1)
        return verts, np.concatenate([t1, t2]).astype(np.int32), vcols

    # -- file writers ------------------------------------------------------------
    @staticmethod
    def _write_ply(path: Path, verts, cols, faces=None):
        vt = np.dtype([("x", "<f4"), ("y", "<f4"), ("z", "<f4"), ("r", "u1"), ("g", "u1"), ("b", "u1")])
        v = np.empty(len(verts), vt)
        v["x"], v["y"], v["z"] = verts[:, 0], verts[:, 1], verts[:, 2]
        v["r"], v["g"], v["b"] = cols[:, 0], cols[:, 1], cols[:, 2]
        head = ["ply", "format binary_little_endian 1.0", f"element vertex {len(v)}",
                "property float x", "property float y", "property float z",
                "property uchar red", "property uchar green", "property uchar blue"]
        if faces is not None:
            head += [f"element face {len(faces)}", "property list uchar int vertex_indices"]
        head.append("end_header")
        with open(path, "wb") as fh:
            fh.write(("\n".join(head) + "\n").encode("ascii"))
            fh.write(v.tobytes())
            if faces is not None:
                ft = np.dtype([("n", "u1"), ("i", "<i4", (3,))])
                f = np.empty(len(faces), ft)
                f["n"] = 3
                f["i"] = faces
                fh.write(f.tobytes())

    @staticmethod
    def _write_obj(path: Path, verts, cols, faces):
        c = cols.astype(np.float32) / 255.0
        with open(path, "w") as fh:
            fh.write("# vertex colours as 'v x y z r g b' (common extension)\n")
            np.savetxt(fh, np.hstack([verts, c]), fmt="v %.5f %.5f %.5f %.3f %.3f %.3f")
            np.savetxt(fh, faces + 1, fmt="f %d %d %d")
