#!/usr/bin/env bash
# collect.sh: FILE_LIST [timeout_seconds=300] [output_dir=/workspace/m0-denominator-final]
#             [extra_env]. --mode collect (default) records collection counts;
#             --mode execute runs tests and records pass/fail/skip/error counts.
# Run init-container.sh first: it prepares conda, SciPy and the target bridge.
# This script only runs the caller's files. CONDA_ENV and SOURCE_ROOT override
# the historical defaults; extra_env carries the runtime contract.
set +e
MODE=collect
if [ "${1:-}" = "--mode" ]; then
  MODE=${2:?usage: collect.sh [--mode collect|execute] FILE_LIST [timeout_seconds] [output_dir] [extra_env]}
  shift 2
fi
case "$MODE" in
  collect|execute) ;;
  *) echo "invalid mode: $MODE" >&2; exit 2 ;;
esac
LIST=${1:?usage: collect.sh [--mode collect|execute] FILE_LIST [timeout_seconds] [output_dir] [extra_env]}
TIMEOUT=${2:-300}
OUT=${3:-/workspace/m0-denominator-final}
EXTRA_ENV=${4:-}
CONDA_ENV=${CONDA_ENV:-python312_torch212}
SRC=${SOURCE_ROOT:-/workspace/m300/torch_feature}
mkdir -p "$OUT/$MODE"
source /root/miniconda/etc/profile.d/conda.sh
conda activate "$CONDA_ENV"
cd "$SRC"
if [ "$MODE" = collect ]; then
  SUMMARY="$OUT/collect_summary.tsv"
  printf 'file\tcollect\trc\n' > "$SUMMARY"
else
  SUMMARY="$OUT/execute_summary.tsv"
  printf 'file\tpassed\tfailed\tskipped\terror\txfailed\txpassed\trc\n' > "$SUMMARY"
fi
COMMANDS="$OUT/${MODE}_commands.log"
printf '%s\n' "CMD: source /root/miniconda/etc/profile.d/conda.sh && conda activate $CONDA_ENV" > "$COMMANDS"
while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  file="xTorch/$rel"
  base="$(basename "$file" .py)"
  out="$OUT/$MODE/$base.$MODE.log"
  if [ "$MODE" = collect ]; then
    cmd="env $EXTRA_ENV timeout ${TIMEOUT}s python -m pytest $file --collect-only -q"
    printf 'CMD: %s\n' "$cmd" >> "$COMMANDS"
    env $EXTRA_ENV timeout "$TIMEOUT" python -m pytest "$file" --collect-only -q >"$out" 2>&1
    rc=$?
    collect="$(sed -n -E -e 's/.*Running ([0-9]+) items.*/\1/p' -e 's/.*collected ([0-9]+) items.*/\1/p' "$out" | tail -1)"
    [ -z "$collect" ] && collect=0
    printf '%s\t%s\t%s\n' "$rel" "$collect" "$rc" | tee -a "$SUMMARY"
  else
    cmd="env $EXTRA_ENV timeout ${TIMEOUT}s python -m pytest $file -q -rsx"
    printf 'CMD: %s\n' "$cmd" >> "$COMMANDS"
    env $EXTRA_ENV timeout "$TIMEOUT" python -m pytest "$file" -q -rsx >"$out" 2>&1
    rc=$?
    count() { sed -n -E "s/.*([0-9]+) $1.*/\1/p" "$out" | tail -1; }
    passed=$(count passed); failed=$(count failed); skipped=$(count skipped)
    error=$(sed -n -E 's/.*([0-9]+) errors?.*/\1/p' "$out" | tail -1)
    xfailed=$(count xfailed); xpassed=$(count xpassed)
    passed=${passed:-0}; failed=${failed:-0}; skipped=${skipped:-0}; error=${error:-0}; xfailed=${xfailed:-0}; xpassed=${xpassed:-0}
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$rel" "$passed" "$failed" "$skipped" "$error" "$xfailed" "$xpassed" "$rc" | tee -a "$SUMMARY"
  fi
  printf 'RC: %s\n' "$rc" >> "$COMMANDS"
done < "$LIST"
printf 'DONE\n' >> "$COMMANDS"
