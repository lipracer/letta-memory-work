#!/usr/bin/env bash
# runner.sh — 在 M300 容器内跑一个上游 PyTorch 测试文件,环境契约钉死在这里。
#
# 存在理由:那 12 项环境变量"必须每次一样"。漏 PYTHONPATH=. 会得到假红,
# 漏 TORCHINDUCTOR_USE_EXPERIMENTAL_BENCHMARKER=0 会慢两个数量级。
# 散文管不住不变量,所以它是脚本。
#
# 用法(在容器内):
#   runner.sh <测试文件相对路径> [时限秒=3600] [产物目录=./_runs]
# 额外 env 透传:调用方直接 export 即可,本脚本不清环境。
#
# 换镜像/换容器环境契约变了,才需要改这个文件;换测试文件只是换参数。
set -uo pipefail

TESTFILE="${1:?usage: runner.sh <testfile> [timeout_s] [outdir]}"
BUDGET="${2:-3600}"
OUTDIR="${3:-./_runs}"

TAG="$(basename "$TESTFILE" .py)-$(date +%Y%m%d-%H%M%S)-$$"
RUNDIR="$OUTDIR/$TAG"
mkdir -p "$RUNDIR" || { echo "FATAL: cannot mkdir $RUNDIR" >&2; exit 2; }
LOG="$RUNDIR/pytest.log"
META="$RUNDIR/meta.env"

# --- 环境契约(改这里 = 改所有任务) ---
source /root/miniconda/etc/profile.d/conda.sh 2>/dev/null || {
  echo "FATAL: conda profile not found" >&2; exit 2; }
conda activate python312_torch212 || { echo "FATAL: conda activate failed" >&2; exit 2; }

export TC_PLATFORM=xpu
export TRITON_ENABLE_XCN_BACKEND=true
export TORCHINDUCTOR_COMPILE_THREADS=1
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:/usr/local/xcuda/targets/x86_64-linux/lib/"
export PYTHONPATH="${PYTHONPATH:-.}"
export XPUSIM_LAUNCH_LOG_LEVEL="${XPUSIM_LAUNCH_LOG_LEVEL:-DISABLE}"
# 模拟器 CUDA event 返 0 → experimental benchmarker 不收缩迭代数 → 慢约两个数量级。
# 上游默认 True 即默认踩坑;0 切到 TritonBenchmarker(do_bench 有 1e-3 下钳)。
export TORCHINDUCTOR_USE_EXPERIMENTAL_BENCHMARKER="${TORCHINDUCTOR_USE_EXPERIMENTAL_BENCHMARKER:-0}"
# 并行隔离:每进程独立 cache,否则并行时互相覆盖。
export TORCHINDUCTOR_CACHE_DIR="${TORCHINDUCTOR_CACHE_DIR:-$PWD/$RUNDIR/.inductor_cache}"
export TRITON_CACHE_DIR="${TRITON_CACHE_DIR:-$PWD/$RUNDIR/.triton_cache}"

# --- 环境自证:失败要报"环境错",绝不能伪装成测试红 ---
python - >"$RUNDIR/selfproof.txt" 2>&1 <<'PY'
import sys, torch
print("python", sys.version.split()[0])
print("torch", torch.__version__)
print("cuda_available", torch.cuda.is_available())
try:
    from torch.utils._triton import has_triton
    print("has_triton", has_triton())
except Exception as e:
    print("has_triton ERROR", e)
PY
SELFPROOF_RC=$?
if [ $SELFPROOF_RC -ne 0 ] || ! grep -q "^cuda_available True" "$RUNDIR/selfproof.txt"; then
  echo "VERDICT: env_broken" | tee "$RUNDIR/verdict.txt"
  echo "selfproof failed — see $RUNDIR/selfproof.txt" >&2
  exit 3
fi

# --- 跑 ---
START=$(date +%s)
timeout --signal=TERM --kill-after=60 "$BUDGET" \
  python -m pytest "$TESTFILE" -q -rs --durations=0 >"$LOG" 2>&1
RC=$?
ELAPSED=$(( $(date +%s) - START ))

# --- 落元信息(供分类器消费,不靠人读日志) ---
SUMMARY="$(grep -oE '[0-9]+ (passed|failed|skipped|error)[a-z]*' "$LOG" | tr '\n' ' ')"
{
  echo "TESTFILE=$TESTFILE"
  echo "RC=$RC"
  echo "ELAPSED_S=$ELAPSED"
  echo "BUDGET_S=$BUDGET"
  echo "SUMMARY=$SUMMARY"
  echo "HAS_SUMMARY_LINE=$([ -n "$SUMMARY" ] && echo yes || echo no)"
  echo "LOG=$(cd "$RUNDIR" && pwd)/pytest.log"
  echo "LOG_LINES=$(wc -l <"$LOG" | tr -d ' ')"
  echo "LOG_MD5=$(md5sum "$LOG" | cut -d' ' -f1)"
  echo "BENCHMARKER=$TORCHINDUCTOR_USE_EXPERIMENTAL_BENCHMARKER"
} | tee "$META"

echo "RUNDIR=$(cd "$RUNDIR" && pwd)"
exit $RC
