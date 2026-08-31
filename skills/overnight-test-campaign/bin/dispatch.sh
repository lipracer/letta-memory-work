#!/usr/bin/env bash
# dispatch.sh — 派一个测试分片给 ducx。取代"我每次手写 4KB PROMPT.md"。
#
# 存在理由:用户原话「不要每次 prompt 一大堆」。手写 prompt 的是我,毛病一样。
# 一次任务的输入应该只有几个变量,不是一篇散文。
#
# 用法(在本机):
#   dispatch.sh <节点> <容器> <测试文件> [时限秒=3600] [模型=gpt-5.6-terra]
# 例:
#   dispatch.sh devbox chenlonglong01_m300_py312_torch212 \
#       xTorch/test/inductor/test_multi_kernel.py 3600
#
# 产物:$RUNS_ROOT/<tag>/{PROMPT.md,ducx.log,handback.md}
# 派完立刻返回;用 Monitor 盯 handback.md 出现,不要轮询。
set -uo pipefail

NODE="${1:?usage: dispatch.sh <node> <container> <testfile> [budget_s] [model]}"
CONTAINER="${2:?need container}"
TESTFILE="${3:?need testfile}"
BUDGET="${4:-3600}"
MODEL="${5:-gpt-5.6-terra}"

RUNS_ROOT="${RUNS_ROOT:-$HOME/workspace/zhixing-work/campaigns/multinode-20260829/runs}"
SKILL_DIR="${SKILL_DIR:-$MEMORY_DIR/skills}"

TAG="$(date +%Y%m%d-%H%M)-$NODE-$(basename "$TESTFILE" .py)"
RUNDIR="$RUNS_ROOT/$TAG"
mkdir -p "$RUNDIR"

# --- PROMPT 由模板 + 参数生成。只写四样:目标 / 本轮独有事实 / 禁碰 / 交付 ---
cat >"$RUNDIR/PROMPT.md" <<EOF
# 目标
在远端容器里跑一个上游 PyTorch 测试文件,拿到可信的 pass/fail/skip 计数与耗时。

# 先读这些(不要我复述,自己读)
- $SKILL_DIR/remote-exec-baidu/SKILL.md   # 连接方式、环境配方、conda/CUDA 自证口径
- $SKILL_DIR/overnight-test-campaign/boundaries.md  # 写权限硬边界
- $SKILL_DIR/overnight-test-campaign/pitfalls.md    # 已取证的坑,先看再跑

# 本轮参数
| 项 | 值 |
|---|---|
| 节点 | $NODE |
| 容器 | $CONTAINER |
| 测试文件 | $TESTFILE |
| 时限 | ${BUDGET}s |
| 本机 run 目录 | $RUNDIR |

# 怎么跑
用 runner 脚本,**不要自己拼环境变量**(漏一项会得到假红):
1. 把 $SKILL_DIR/overnight-test-campaign/bin/runner.sh 送进容器 /workspace/bin/
2. 在容器内执行:runner.sh $TESTFILE $BUDGET
3. runner 会输出 meta.env(含 RC/ELAPSED_S/SUMMARY/LOG_MD5)和 RUNDIR

怎么拆步骤你自己决定。

# 禁碰
- 宿主机:除 docker exec 和自己的工作目录外,不写任何东西
- 容器内:只写 /workspace
- 不装卸任何 pip/conda 包(会污染被测环境)
- 不改测试文件本身(改测试适配后端 = 污染验收)

# 交付
把远端的 meta.env 内容原样抄回本机 $RUNDIR/handback.md,并附:
- 进容器后逐条命令原文 + rc
- 远端日志绝对路径 + 行数 + md5
- 异常时:日志尾部 30 行
完整日志留远端。**没有 handback.md 视为没干活。**
EOF

ducx exec -m "$MODEL" -c model_provider=oneapi -c model_reasoning_effort=high \
  --skip-git-repo-check -s danger-full-access "$(cat "$RUNDIR/PROMPT.md")" \
  >"$RUNDIR/ducx.log" 2>&1 &

echo "DISPATCHED pid=$! model=$MODEL"
echo "RUNDIR=$RUNDIR"
echo "watch: until [ -f $RUNDIR/handback.md ]; do sleep 20; done"
