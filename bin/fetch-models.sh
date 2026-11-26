#!/bin/bash
# Copies the trained weights into the models directory used by the worker.
#   bin/fetch-models.sh <dest_dir> [source_dir]
# Weights are not stored in git (the detector is ~195 MB). Source search order:
#   $2, $SEISMIC_MODELS_SRC, the masonry_det training folder on the Windows share.
DEST="${1:?usage: fetch-models.sh <dest_dir> [source_dir]}"
SRC="${2:-${SEISMIC_MODELS_SRC:-}}"
RUNS="/mnt/windows_share/_prj/Andrea/net/masonry_det/runs"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEIGHTS="$HERE/weights"   # weights stored in the repository (the detector is split in parts < 100 MB)

mkdir -p "$DEST"
copy() { # name  candidate...
  local name="$1"; shift
  [ -f "$DEST/$name" ] && { echo "  $name already present"; return 0; }
  for c in "$@"; do
    if [ -f "$c" ]; then cp "$c" "$DEST/$name" && echo "  $name <- $c"; return 0; fi
  done
  echo "  $name not found"; return 1
}
# detector stored in the repo as masonry_det.pt.part00, part01, ... : reassemble and verify
if [ ! -f "$DEST/masonry_det.pt" ] && ls "$WEIGHTS"/masonry_det.pt.part* >/dev/null 2>&1; then
  cat "$WEIGHTS"/masonry_det.pt.part* > "$DEST/masonry_det.pt.tmp"
  want=$(awk '$2=="masonry_det.pt"{print $1}' "$WEIGHTS/SHA256SUMS")
  if [ -z "$want" ] || [ "$(sha256sum "$DEST/masonry_det.pt.tmp" | cut -d' ' -f1)" = "$want" ]; then
    mv "$DEST/masonry_det.pt.tmp" "$DEST/masonry_det.pt" && echo "  masonry_det.pt <- $WEIGHTS (parts)"
  else
    rm -f "$DEST/masonry_det.pt.tmp"; echo "  masonry_det.pt: checksum mismatch in the repository parts"
  fi
fi
copy masonry_det.pt "${SRC:+$SRC/masonry_det.pt}" "$RUNS/ft_volta430/weights/best.pt"
copy crack_seg.pt   "${SRC:+$SRC/crack_seg.pt}" "$WEIGHTS/crack_seg.pt"   "$RUNS/crackseg_ft_volta/weights/best.pt"
