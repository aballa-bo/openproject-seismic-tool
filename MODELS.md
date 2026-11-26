# Model weights

The weights are stored in the repository, in `weights/`. The detector (~195 MB) is above GitHub's 100 MB file
limit, so it is split in `masonry_det.pt.part00..02`; `bin/fetch-models.sh` (called by `install.sh`) joins the parts,
checks them against `weights/SHA256SUMS` and puts the files into `/var/db/openproject/seismic_tool/models`.
To use other weights, set `SEISMIC_MODELS_SRC` (folder with `masonry_det.pt` and `crack_seg.pt`; it has priority)
or drop files with the same names into the models directory. To rebuild the split after replacing the detector:
`split -b 90M -d -a 2 masonry_det.pt weights/masonry_det.pt.part` and update `weights/SHA256SUMS`.

| File in models dir | Source run (masonry_det) | Role |
|---|---|---|
| `masonry_det.pt` | `runs/ft_volta430/weights/best.pt` | YOLOv5-x detector, 7 MSD-Det damage classes, 1280 px. Last fine-tuning (MSD-Det + 430 vault images). |
| `crack_seg.pt`   | `runs/crackseg_ft_volta/weights/best.pt` | YOLO11m-seg, crack masks; Crack-Seg fine-tuned on masonry. |

Why these: they are the most recent weights in `masonry_det` and the ones used for the last detection run.
Measured on the held-out sets (from the training logs):

* Detector `ft_volta430`: mAP50 0.161 / mAP50-95 0.068 on the MSD test split, 0.063 / 0.028 on the vault validation set.
  Low in absolute terms (the paper reports 0.93 mAP50 for YOLOv5-x at 640 px on the original dataset; the 1280 px
  models trained here score lower). Treat detections as **hints for the inspector**, not as measurements.
* Crack segmentation: `crackseg_ft_volta` mask mAP50 0.585 (recall 0.62) vs `crackseg_yolo11m-seg` 0.583 (recall 0.56) on the
  Crack-Seg test split; the fine-tuned one is kept for its better recall on masonry.

Other weights can be dropped in with the same names, or selected with `SEISMIC_DETECTOR_WEIGHTS` /
`SEISMIC_CRACK_WEIGHTS` in `/etc/openproject-seismic/worker.env`.
