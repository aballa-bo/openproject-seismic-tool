"""Ported from the masonry_det application (same author).

Segmentazione delle fessure dentro i box "Cracks" del detector MSD-Det.

Strategia (cascata a due stadi):
  1. il detector MSD-Det localizza le fessure con un box;
  2. ogni box (con un piccolo margine) viene ritagliato dall'immagine a piena risoluzione e
     suddiviso in tasselli di circa `tile` px: così le fessure, sottili, non vengono rimpicciolite;
  3. il modello YOLO-seg (addestrato su Crack-Seg) produce la maschera di ogni tassello;
  4. la maschera viene limitata al box rilevato (il margine serve solo come contesto al modello):
     la segmentazione fuori dai box "Cracks" non viene usata,
     così si riducono i falsi positivi su giunti di malta, bordi e ombre.
"""
from __future__ import annotations

import cv2
import numpy as np
from skimage.morphology import skeletonize

OVERLAY_BGR = (0, 0, 255)  # rosso


def _tiles(x0: int, y0: int, x1: int, y1: int, tile: int, overlap: float = 0.2):
    """Genera finestre (xa, ya, xb, yb) che coprono il rettangolo, con sovrapposizione."""
    def starts(a, b):
        n = b - a
        if n <= tile:
            return [a]
        step = int(tile * (1 - overlap))
        s = list(range(a, b - tile, step)) + [b - tile]
        return sorted(set(s))
    for ya in starts(y0, y1):
        for xa in starts(x0, x1):
            yield xa, ya, min(xa + tile, x1), min(ya + tile, y1)


def segment_cracks(seg_model, bgr: np.ndarray, boxes, *, tile: int = 640, pad: float = 0.05,
                   conf: float = 0.25, imgsz: int = 640, device=None):
    """Ritorna (maschera booleana HxW dell'immagine, [maschera booleana di ciascun box])."""
    H, W = bgr.shape[:2]
    full = np.zeros((H, W), bool)
    per_box = []
    for x1, y1, x2, y2 in boxes:
        px, py = (x2 - x1) * pad, (y2 - y1) * pad
        bx0, by0 = max(0, int(x1 - px)), max(0, int(y1 - py))
        bx1, by1 = min(W, int(np.ceil(x2 + px))), min(H, int(np.ceil(y2 + py)))
        box_mask = np.zeros((H, W), bool)
        wins = list(_tiles(bx0, by0, bx1, by1, tile))
        crops = [bgr[ya:yb, xa:xb] for xa, ya, xb, yb in wins]
        for i in range(0, len(crops), 16):  # batch di tasselli
            res = seg_model.predict(crops[i:i + 16], imgsz=imgsz, conf=conf, retina_masks=True,
                                    device=device, verbose=False)
            for (xa, ya, xb, yb), r in zip(wins[i:i + 16], res):
                if r.masks is None:
                    continue
                m = r.masks.data.cpu().numpy().any(0)
                box_mask[ya:yb, xa:xb] |= m[: yb - ya, : xb - xa].astype(bool)
        # ritaglio al box originale: il margine è solo contesto, non area da etichettare
        clip = np.zeros_like(box_mask)
        clip[max(0, int(y1)):min(H, int(np.ceil(y2))), max(0, int(x1)):min(W, int(np.ceil(x2)))] = True
        box_mask &= clip
        per_box.append(box_mask)
        full |= box_mask
    return full, per_box


def classic_crack_mask(gray: np.ndarray, kernel: int = 15, min_area: int = 30, min_len: int = 25,
                       max_fill: float = 0.5) -> np.ndarray:
    """Maschera delle fessure senza rete neurale: linee sottili più scure dell'intorno.

    Black-hat morfologico (evidenzia i dettagli scuri più stretti di `kernel` px), soglia al 97°
    percentile del ritaglio (minimo 12 livelli di grigio), poi si tengono solo le componenti
    allungate: area >= min_area, lato maggiore >= min_len, riempimento del rettangolo < max_fill
    (così si scartano macchie e buchi tondeggianti).
    """
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel, kernel))
    bh = cv2.morphologyEx(cv2.GaussianBlur(gray, (3, 3), 0), cv2.MORPH_BLACKHAT, k)
    t = max(12.0, float(np.percentile(bh, 97)))
    m = (bh > t).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(m, connectivity=8)
    keep = np.zeros(n, bool)
    for i in range(1, n):
        w, h, a = st[i, 2], st[i, 3], st[i, 4]
        keep[i] = a >= min_area and max(w, h) >= min_len and a / (w * h) < max_fill
    return keep[lab]


def segment_cracks_classic(bgr: np.ndarray, boxes, *, kernel: int = 15):
    """Come segment_cracks ma con classic_crack_mask: ritorna (maschera HxW, [maschera di ciascun box])."""
    H, W = bgr.shape[:2]
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    full = np.zeros((H, W), bool)
    per_box = []
    for x1, y1, x2, y2 in boxes:
        bx0, by0 = max(0, int(x1)), max(0, int(y1))
        bx1, by1 = min(W, int(np.ceil(x2))), min(H, int(np.ceil(y2)))
        box_mask = np.zeros((H, W), bool)
        if bx1 - bx0 >= 3 and by1 - by0 >= 3:
            box_mask[by0:by1, bx0:bx1] = classic_crack_mask(gray[by0:by1, bx0:bx1], kernel=kernel)
        per_box.append(box_mask)
        full |= box_mask
    return full, per_box


def segment_whole_image(seg_model, bgr: np.ndarray, *, tile: int = 640, conf: float = 0.25, imgsz: int = 640,
                        device=None, min_area: int = 100, merge: float = 0.01):
    """Modalità "solo fessure": segmenta l'intera immagine a tasselli, senza il detector MSD.

    Le fessure sono le componenti connesse della maschera; i frammenti distanti meno di
    `merge` x lato maggiore dell'immagine vengono uniti nella stessa fessura. Le componenti con
    area inferiore a `min_area` px vengono scartate.
    Ritorna (maschera HxW, [(confidenza, [x1, y1, x2, y2], maschera della fessura)]), dove la
    confidenza è la media, sui pixel della fessura, della confidenza dell'istanza che li copre.
    """
    H, W = bgr.shape[:2]
    cmap = np.zeros((H, W), np.float32)  # confidenza massima per pixel
    wins = list(_tiles(0, 0, W, H, tile))
    for i in range(0, len(wins), 16):
        crops = [bgr[ya:yb, xa:xb] for xa, ya, xb, yb in wins[i:i + 16]]
        res = seg_model.predict(crops, imgsz=imgsz, conf=conf, retina_masks=True, device=device, verbose=False)
        for (xa, ya, xb, yb), r in zip(wins[i:i + 16], res):
            if r.masks is None:
                continue
            ms = r.masks.data.cpu().numpy()[:, : yb - ya, : xb - xa] > 0.5
            cs = r.boxes.conf.cpu().numpy().astype(np.float32)
            tilec = (ms * cs[:, None, None]).max(0)
            np.maximum(cmap[ya:yb, xa:xb], tilec, out=cmap[ya:yb, xa:xb])
    full = cmap > 0

    cracks = []
    if full.any():
        k = max(1, int(round(merge * max(H, W))))
        grown = cv2.dilate(full.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * k + 1,) * 2))
        n, lab = cv2.connectedComponents(grown, connectivity=8)
        lab[~full] = 0
        keep = np.zeros((H, W), bool)
        for c in range(1, n):
            m = lab == c
            area = int(m.sum())
            if area < min_area:
                continue
            ys, xs = np.nonzero(m)
            cracks.append((float(cmap[m].mean()), [float(xs.min()), float(ys.min()), float(xs.max() + 1),
                                                   float(ys.max() + 1)], m))
            keep |= m
        full = keep
        cracks.sort(key=lambda t: -t[0])
    return full, cracks


def draw_boxes(img_bgr: np.ndarray, dets, color=(0, 0, 255), lw: int = 2) -> np.ndarray:
    """Disegna box ed etichette "classe confidenza" (usato in modalità solo fessure)."""
    out = img_bgr.copy()
    fs = lw / 3
    for cls, c, (x1, y1, x2, y2) in dets:
        p1, p2 = (int(x1), int(y1)), (int(x2), int(y2))
        cv2.rectangle(out, p1, p2, color, lw, cv2.LINE_AA)
        txt = f"{cls} {c:.2f}"
        (tw, th), bl = cv2.getTextSize(txt, cv2.FONT_HERSHEY_SIMPLEX, fs, max(1, lw // 2))
        ty = p1[1] - 2 if p1[1] - th - bl - 2 >= 0 else p1[1] + th + bl + 2
        cv2.rectangle(out, (p1[0], ty - th - bl), (p1[0] + tw, ty + bl // 2), color, -1)
        cv2.putText(out, txt, (p1[0], ty - bl // 2), cv2.FONT_HERSHEY_SIMPLEX, fs, (255, 255, 255),
                    max(1, lw // 2), cv2.LINE_AA)
    return out


def crack_stats(mask: np.ndarray) -> dict:
    """Area (px), lunghezza dello scheletro (px) e larghezza media (px) di una maschera."""
    area = int(mask.sum())
    if area == 0:
        return {"crack_area_px": 0, "crack_length_px": 0.0, "crack_mean_width_px": 0.0}
    ys, xs = np.nonzero(mask)
    sub = mask[ys.min(): ys.max() + 1, xs.min(): xs.max() + 1]
    sk = skeletonize(sub)
    # lunghezza: i passi diagonali dello scheletro valgono sqrt(2)
    sk8 = sk.astype(np.uint8)
    straight = (sk8[:, 1:] & sk8[:, :-1]).sum() + (sk8[1:, :] & sk8[:-1, :]).sum()
    diag = (sk8[1:, 1:] & sk8[:-1, :-1]).sum() + (sk8[1:, :-1] & sk8[:-1, 1:]).sum()
    length = float(straight + np.sqrt(2) * diag) or float(sk.sum())
    return {
        "crack_area_px": area,
        "crack_length_px": round(length, 1),
        "crack_mean_width_px": round(area / length, 2) if length else 0.0,
    }


def draw_overlay(img_bgr: np.ndarray, mask: np.ndarray, alpha: float = 0.6, contour: bool = True) -> np.ndarray:
    out = img_bgr.copy()
    if mask.any():
        color = np.array(OVERLAY_BGR, np.float32)
        out[mask] = (out[mask] * (1 - alpha) + color * alpha).astype(np.uint8)
        if contour:
            cs, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            cv2.drawContours(out, cs, -1, (0, 255, 255), max(1, round(max(mask.shape) / 2000)))
    return out
