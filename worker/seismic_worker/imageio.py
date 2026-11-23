"""Image loading (EXIF orientation applied, HEIC supported) -- same convention as masonry_det."""
from __future__ import annotations

import numpy as np
from PIL import Image, ImageOps

try:
    import pillow_heif

    pillow_heif.register_heif_opener()
except ImportError:  # pragma: no cover
    pass

Image.MAX_IMAGE_PIXELS = None  # photogrammetric frames can be large


def load_bgr(path: str) -> np.ndarray:
    im = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    return np.ascontiguousarray(np.asarray(im)[:, :, ::-1])
