#!/bin/bash
# Copies the trained weights into the models directory used by the worker.
#   bin/fetch-models.sh <dest_dir> [source_dir]
# Weights are not stored in git (the detector is ~195 MB). Source search order:
#   $2, $SEISMIC_MODELS_SRC, the masonry_det training folder on the Windows share.
DEST="${1:?usage: fetch-models.sh <dest_dir> [source_dir]}"
SRC="${2:-${SEISMIC_MODELS_SRC:-}}"
RUNS="/mnt/windows_share/_prj/Andrea/net/masonry_det/runs"

mkdir -p "$DEST"
copy() { # name  candidate...
  local name="$1"; shift
  [ -f "$DEST/$name" ] && { echo "  $name already present"; return 0; }
  for c in "$@"; do
    if [ -f "$c" ]; then cp "$c" "$DEST/$name" && echo "  $name <- $c"; return 0; fi
  done
  echo "  $name not found"; return 1
}
copy masonry_det.pt "${SRC:+$SRC/masonry_det.pt}" "$RUNS/ft_volta430/weights/best.pt"
copy crack_seg.pt   "${SRC:+$SRC/crack_seg.pt}"   "$RUNS/crackseg_ft_volta/weights/best.pt"
