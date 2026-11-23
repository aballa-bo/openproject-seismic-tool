#!/bin/bash
# Installs the OpenProject "Seismic tool" plugin and its low-priority worker.
#   sudo bash install.sh
# Optional: SEISMIC_MODELS_SRC=/path/with/masonry_det.pt+crack_seg.pt  sudo -E bash install.sh
set -e

PLUGIN_NAME="openproject-seismic_tool"
MODULE_DIR_NAME="seismic_tool"
PLUGIN_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OP_DIR="${OP_DIR:-/opt/openproject}"
DEST_DIR="$OP_DIR/modules/$MODULE_DIR_NAME"
WORKER_HOME="/opt/openproject-seismic"
MODELS_DIR="${SEISMIC_MODELS_DIR:-/var/db/openproject/seismic_tool/models}"
ENV_FILE="/etc/openproject-seismic/worker.env"

echo "========================================================="
echo " Installing OpenProject Seismic tool                     "
echo "========================================================="

if [ "$EUID" -ne 0 ]; then
  echo "[-] ERROR: run with root privileges: sudo bash install.sh"
  exit 1
fi

echo "[1/8] Copying the plugin to $DEST_DIR..."
rm -rf "$DEST_DIR"
mkdir -p "$OP_DIR/modules"
cp -r "$PLUGIN_SRC" "$DEST_DIR"
rm -rf "$DEST_DIR/.git" "$DEST_DIR/worker" "$DEST_DIR/venv"
chown -R openproject:openproject "$DEST_DIR"

echo "[2/8] Configuring Gemfile.modules..."
sed -i "/openproject-seismic_tool/d" "$OP_DIR/Gemfile.modules" 2>/dev/null || true
sed -i "/group :opf_plugins do/a\\  gem '$PLUGIN_NAME', path: 'modules/$MODULE_DIR_NAME'" "$OP_DIR/Gemfile.modules"

echo "[3/8] bundle install..."
openproject run bundle config set frozen false
openproject run bundle install

echo "[4/8] Database migrations..."
openproject run rake db:migrate

echo "[5/8] Deploying static assets..."
ASSET_DIR="$OP_DIR/public/assets/openproject_seismic_tool"
mkdir -p "$ASSET_DIR"
cp "$PLUGIN_SRC"/app/assets/javascripts/openproject_seismic_tool/*.js "$ASSET_DIR/"
cp "$PLUGIN_SRC"/app/assets/stylesheets/openproject_seismic_tool/*.css "$ASSET_DIR/"
chown -R openproject:openproject "$ASSET_DIR"
openproject run rake tmp:cache:clear

echo "[6/8] Python environment for the worker ($WORKER_HOME)..."
mkdir -p "$WORKER_HOME"
rsync -a --delete --exclude '__pycache__' "$PLUGIN_SRC/worker/" "$WORKER_HOME/worker/"
if [ ! -x "$WORKER_HOME/venv/bin/python" ]; then
  python3 -m venv "$WORKER_HOME/venv"
fi
"$WORKER_HOME/venv/bin/pip" install --quiet --upgrade pip
# CPU-only PyTorch (this server has no GPU); much smaller than the default CUDA build
"$WORKER_HOME/venv/bin/pip" install --quiet torch torchvision --index-url https://download.pytorch.org/whl/cpu
"$WORKER_HOME/venv/bin/pip" install --quiet -r "$WORKER_HOME/worker/requirements.txt"
# ultralytics pulls in the GUI build of OpenCV (needs libGL); keep only the headless one
"$WORKER_HOME/venv/bin/pip" uninstall --quiet -y opencv-python 2>/dev/null || true
"$WORKER_HOME/venv/bin/pip" install --quiet --force-reinstall --no-deps opencv-python-headless
chown -R openproject:openproject "$WORKER_HOME"

echo "[7/8] Model weights in $MODELS_DIR..."
mkdir -p "$MODELS_DIR"
bash "$PLUGIN_SRC/bin/fetch-models.sh" "$MODELS_DIR" || true
chown -R openproject:openproject "$(dirname "$MODELS_DIR")"
DEPTH_DIR="$MODELS_DIR/depth_anything_v2_small"
if [ ! -f "$DEPTH_DIR/config.json" ]; then
  echo "  downloading Depth Anything V2 Small (crack modelling) from Hugging Face..."
  "$WORKER_HOME/venv/bin/python" - "$DEPTH_DIR" <<'PY' || echo "  [!] depth model download failed: the worker will retry at the first 3D job (needs internet)."
import sys
from huggingface_hub import snapshot_download
snapshot_download("depth-anything/Depth-Anything-V2-Small-hf", local_dir=sys.argv[1])
PY
fi
chown -R openproject:openproject "$(dirname "$MODELS_DIR")"
if [ ! -f "$MODELS_DIR/masonry_det.pt" ] || [ ! -f "$MODELS_DIR/crack_seg.pt" ]; then
  echo "[!] Weights missing in $MODELS_DIR (masonry_det.pt, crack_seg.pt): see MODELS.md."
  echo "    The worker starts anyway, but jobs fail until the files are there."
fi

echo "[8/8] Worker service..."
mkdir -p "$(dirname "$ENV_FILE")"
if [ ! -f "$ENV_FILE" ]; then
  DB_URL="$(openproject config:get DATABASE_URL 2>/dev/null || true)"
  if [ -z "$DB_URL" ]; then
    echo "[!] DATABASE_URL not found: edit $ENV_FILE by hand."
  fi
  sed -e "s|^SEISMIC_DATABASE_URL=.*|SEISMIC_DATABASE_URL=$DB_URL|" \
      -e "s|^SEISMIC_MODELS_DIR=.*|SEISMIC_MODELS_DIR=$MODELS_DIR|" \
      "$PLUGIN_SRC/systemd/worker.env.example" > "$ENV_FILE"
fi
chown root:openproject "$ENV_FILE"; chmod 640 "$ENV_FILE"
cp "$PLUGIN_SRC/systemd/openproject-seismic-worker.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable openproject-seismic-worker >/dev/null 2>&1 || true
systemctl restart openproject-seismic-worker || echo "[!] worker did not start: journalctl -u openproject-seismic-worker"

systemctl restart openproject-web-1 openproject-worker-1 2>/dev/null || openproject restart

echo "========================================================="
echo " [OK] Seismic tool installed."
echo " Enable the 'Seismic tool' module in the project settings and give roles the permissions."
echo " Worker logs: journalctl -u openproject-seismic-worker -f"
echo "========================================================="
