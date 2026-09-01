#!/usr/bin/env bash
# init-container.sh - initialize the M300 environment from image tag:
# iregistry.baidu-int.com/xpu/m300_pytorch212_ubuntu2204_x86_64_cuda12:20260713_24
# Usage (inside target container): init-container.sh [--container NAME] [--env ENV]
#   [--source-env ENV] [--workdir DIR]. The container name is audit metadata.
# This script prepares the environment only; it never runs tests.
set -Eeuo pipefail
CONTAINER="chenlonglong01_m300_py312_torch212"; ENV_NAME="python312_torch212"
SOURCE_ENV="python312_torch212"; WORKDIR="/workspace/m0-denominator-final"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --container) CONTAINER="${2:?missing value}"; shift 2;;
    --env) ENV_NAME="${2:?missing value}"; shift 2;;
    --source-env) SOURCE_ENV="${2:?missing value}"; shift 2;;
    --workdir) WORKDIR="${2:?missing value}"; shift 2;;
    -h|--help) sed -n '1,10p' "$0"; exit 0;;
    *) echo "usage: $0 [--container NAME] [--env ENV] [--source-env ENV] [--workdir DIR]" >&2; exit 2;;
  esac
done
mkdir -p "$WORKDIR"; LOG="$WORKDIR/init-container.log"; touch "$LOG"
exec > >(tee -a "$LOG") 2>&1
step=0
run_step() { step=$((step+1)); local name="$1"; shift; echo "[step $step] $name"; "$@"; local rc=$?; echo "[step $step] $name rc=$rc"; return "$rc"; }
echo "container=$CONTAINER env=$ENV_NAME source_env=$SOURCE_ENV workdir=$WORKDIR"
run_step conda-profile test -f /root/miniconda/etc/profile.d/conda.sh
source /root/miniconda/etc/profile.d/conda.sh
if conda env list | awk '{print $1}' | grep -Fxq "$ENV_NAME"; then echo "[skip] conda env $ENV_NAME already exists"; else run_step "clone conda env $SOURCE_ENV -> $ENV_NAME" conda create -y -n "$ENV_NAME" --clone "$SOURCE_ENV"; fi
ENV_PREFIX="/root/miniconda/envs/$ENV_NAME"; PYTHON="$ENV_PREFIX/bin/python"
run_step python-present test -x "$PYTHON"
scipy_version="$($PYTHON -c 'import scipy; print(scipy.__version__)' 2>/dev/null || true)"
if [[ "$scipy_version" == "1.13.1" ]]; then echo "[skip] scipy 1.13.1 already installed"; else
  wheel="$(find "$WORKDIR" -maxdepth 1 -type f -name 'scipy-1.13.1-*.whl' -print -quit)"
  [[ -n "$wheel" ]] || { echo "FATAL: scipy-1.13.1 wheel not found in $WORKDIR" >&2; exit 1; }
  run_step "install scipy 1.13.1 from $wheel" "$PYTHON" -m pip install --no-deps --force-reinstall "$wheel"
fi
BRIDGE_DIR="$WORKDIR/triage-triton"; BRIDGE="$BRIDGE_DIR/sitecustomize.py"
if [[ -f "$BRIDGE" ]]; then echo "[skip] bridge already present: $BRIDGE"; else
  mkdir -p "$BRIDGE_DIR"; source_bridge="/workspace/multinode-20260829/p1-triton/sitecustomize.py"
  [[ -f "$source_bridge" ]] || { echo "FATAL: canonical bridge missing: $source_bridge" >&2; exit 1; }
  run_step "install target bridge $BRIDGE" cp "$source_bridge" "$BRIDGE"
fi
ENV_FILE="$WORKDIR/init-env.sh"
if [[ -f "$ENV_FILE" ]] && grep -q '^export TRITON_ENABLE_XCN_BACKEND=true$' "$ENV_FILE" && grep -q '^export PYTHONPATH=' "$ENV_FILE"; then echo "[skip] runtime environment file already present: $ENV_FILE"; else
  run_step "write runtime environment contract" bash -c "cat > '$ENV_FILE' <<'EOF'
export TC_PLATFORM=xpu
export TRITON_ENABLE_XCN_BACKEND=true
export TORCHINDUCTOR_COMPILE_THREADS=1
export LD_LIBRARY_PATH=\"\${LD_LIBRARY_PATH:-}:/usr/local/xcuda/targets/x86_64-linux/lib/\"
export PYTHONPATH=\"$BRIDGE_DIR\"
export XPUSIM_LAUNCH_LOG_LEVEL=\"\${XPUSIM_LAUNCH_LOG_LEVEL:-DISABLE}\"
export TORCHINDUCTOR_USE_EXPERIMENTAL_BENCHMARKER=\"\${TORCHINDUCTOR_USE_EXPERIMENTAL_BENCHMARKER:-0}\"
EOF"
fi
source "$ENV_FILE"
echo "[self-proof]"; set +e
proof="$($PYTHON - "$BRIDGE_DIR" <<'PY'
import os, sys
import torch, numpy, scipy, triton
from triton.runtime import driver
keys=sorted(getattr(triton.backends, "backends", {}).keys())
print("python", sys.executable); print("torch", torch.__version__); print("numpy", numpy.__version__)
print("scipy", scipy.__version__); print("triton", triton.__version__)
print("torch.cuda.is_available()", torch.cuda.is_available()); print("triton backend keys", keys)
print("active target", driver.active.get_current_target())
print("bridge", sys.argv[1], os.path.isfile(os.path.join(sys.argv[1], "sitecustomize.py")))
PY
)"; proof_rc=$?; set -e; printf '%s\n' "$proof"
[[ $proof_rc -eq 0 ]] || { echo "FATAL: self-proof python failed" >&2; exit 1; }
grep -q '^python /root/miniconda/envs/' <<<"$proof" || { echo "FATAL: unexpected python path" >&2; exit 1; }
grep -q '^torch 2\.12\.0a0+git0382020$' <<<"$proof" || { echo "FATAL: torch version mismatch" >&2; exit 1; }
grep -q '^numpy 1\.26\.4$' <<<"$proof" || { echo "FATAL: numpy version mismatch" >&2; exit 1; }
grep -q '^scipy 1\.13\.1$' <<<"$proof" || { echo "FATAL: scipy version mismatch" >&2; exit 1; }
grep -q '^triton 3\.6\.0$' <<<"$proof" || { echo "FATAL: triton version mismatch" >&2; exit 1; }
grep -q '^torch.cuda.is_available() True$' <<<"$proof" || { echo "FATAL: CUDA compatibility unavailable" >&2; exit 1; }
grep -q "^triton backend keys \['triton_shared', 'xcn'\]$" <<<"$proof" || { echo "FATAL: triton backend registry mismatch" >&2; exit 1; }
grep -q "^active target GPUTarget(backend='houyi', arch='xpu5', warp_size=32)$" <<<"$proof" || { echo "FATAL: active target mismatch" >&2; exit 1; }
grep -q '^bridge .* True$' <<<"$proof" || { echo "FATAL: target bridge missing" >&2; exit 1; }
echo "INIT_OK"
