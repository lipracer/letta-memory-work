---
name: overnight-test-campaign
description: This skill should be used when the user wants to run a large batch of tests overnight (半夜/夜间跑) on remote GPU/XPU machines by delegating to agents — including environment and disk precheck, pulling images and building containers, sharding test suites that have no unified runner, and collecting an auditable report by morning. First campaign is the M300 PyTorch Autotuning (torch.compile) suite. Load this before scheduling any unattended remote test run.
version: 0.2.0
---

# 夜间远端测试战役

**做什么**:让上游 PyTorch 单元测试在 M300(编译层面兼容 CUDA)上跑起来,
批量、无人值守、早上有一份可复现的报告。产出是**一张持续演进的兼容性缺口清单**
([[reference/m300/cuda_compat_gaps.md]]),不是一次性绿灯。

**核心矛盾**:测试套件没有统一 runner,机器是共享的,而半夜没人在场。
所以一切必须先在有人看着时打通一遍。

---

## 1. 先读这个:当前进展

**不知道该干什么时,看这一节,不要从头读全部文件。**

| 已确立 | 值 |
|---|---|
| 环境配方 | 见 [[skills/remote-exec-baidu/SKILL.md]],**逐字照抄** |
| 单文件基线 | `test_multi_kernel.py` = 13 pass / 4 fail / 2 skip,**两次逐用例一致** |
| 那 4 个 fail | 全是 `cpp_wrapper` 变体 → **真实缺口**,不是噪声 |
| 2 进程并行 | **安全**(独立 cache 目录),零新增 fail |
| 并行收益 | ❌ **未测出**(基准样本撞 timeout,数字作废) |
| autotune 慢的根因 | ✅ 模拟器 event 返 0 → benchmark 迭代不收缩,见 `pitfalls.md` |
| 规避开关收益 | ❌ **未测出**(只验了单用例) |

**下一步该做的**:量 `TORCHINDUCTOR_USE_EXPERIMENTAL_BENCHMARKER=0` 对整文件的实际收益
(给 ≥3000s 预算,对比 2656s 基线)。这个数字决定所有分片预算,没它无法定 P2。

---

## 2. 判读口径(决定"红"意味着什么)

套件是**上游的**,目标是上游 CUDA 测试原样拿来能过。由此:

- **按 CUDA 写法跑**(`device="cuda"` / `TestCommonCUDA`)是**验收口径本身**,不是权宜。
  改测试去适配我们的后端 = 污染验收。
- **skip 比 fail 危险。** fail 暴露缺口(有价值);大面积 skip 是假装通过。
  必须带 `-rs` 摊出 skip 数和原因,**不许只报 pass 数**。
  skip 还必须**分三类**(`skip_upstream` / `skip_ours` / `skip_gating_bug`,定义见
  [[reference/m300/precision_criteria.md]]):**skip 总数下降不一定是好事,稳定也不一定安全**,
  只有按类看才有意义。
- **分母诚实**:覆盖率对的是**上游 torch.compile / inductor 全量**,
  不是"我们挑得出来能跑的那些"。缺失文件、collect 失败、整片 skip 都计入缺口。
  ⚠️ **范围不是整个 PyTorch** —— torch 其他模块是团队的活；别拿团队的分母给自己记分。
  ⚠️ **不要直接用 DENOM=4959**：它的文件范围与收集环境未留证，且 `--collect-only`
  计数随环境变（同批 16 个文件装 Triton 前后 1997→2994）。在**最终跑测试的环境**里重取。
- **新增 fail 排报告最前**,不许被"整体成功"盖过去。

---

## 3. 三条铁律

1. **先跑通一个,再铺开。** 没跑通过一次的测试不许进夜间批量 —— 半夜只会产出一堆
   error,白烧一晚机器。
2. **环境每动一次(装包/改 env/换镜像/换机器),退回冒烟重跑。** 拿到"1 个用例真 pass"才能继续。
3. **跑通之前不许造机制。** 规模是一晚一晚试出来的(2→4→8),不为想象中的第 N 晚提前造调度器。
   判据:为"还没发生的规模"设计 → 砍掉;当前这步实测撑不住 → 才可以加。

---

## 4. 执行模型

**我只统筹,不下场。** 执行主体是 **ducx**(跑在本机,无状态、可并发):

```bash
ducx exec -m gpt-5.6-terra -c model_provider=oneapi -c model_reasoning_effort=high \
  --skip-git-repo-check -s danger-full-access "$(cat PROMPT.md)" > ducx.log 2>&1 &
```
三个参数缺一不可(缺 provider → 死循环重连;缺 reasoning → config 默认 low)。
Letta subagent 只在 ducx 不可用时兜底。**容器里起不了 ducx** —— 容器是被
`ssh <节点>` + `docker exec` 操作的对象,不是执行者。

**探路也是任务**(`df` / `docker ps` / 试写权限一并委托),我自己 ssh 去探等于污染上下文。

**派一个分片用脚本，不手写 prompt**（`bin/` 下三个）：

| 脚本 | 干什么 | 为何是代码而不是文档 |
|---|---|---|
| `bin/dispatch.sh <节点> <容器> <测试文件> [时限]` | 建 run 目录、模板生成 PROMPT、带齐三个 ducx 参数派发 | 手写 4KB prompt 就是“每次 prompt 一大堆” |
| `bin/runner.sh <测试文件> [时限]`（容器内） | conda activate + 12 项 env + 自证 + 跑 + 落 meta.env | 漏 `PYTHONPATH=.` → 假红；漏 benchmarker 开关 → 慢两个量级 |
| `bin/classify.py <meta.env>...` | meta → verdict + 处置 | 同一个 rc=124 三种含义，分错就污染缺口清单 |

`classify.py` 的判定（已用四个场景验过）：
`rc=3` → `env_broken`（不算 fail，原样重排）；
`rc=124` 且用满预算 → `budget_short`（加时限）；
`rc=124` 但远未用满 → `hung`（立案为 blocker）；
`rc=0/1` 且有汇总行 → `ok`（rc=1 有 fail 是有价值产出，不是故障）。

**改得起的地方**：环境契约变了改 `runner.sh`（换镜像才需要）；
新增一个同类任务只给参数。**若发现自己又在手写散文派派任务，就是退步了。**

**不是每个任务一个脚本，是每个环境契约一个脚本。** 三层分工见
[[system/orchestration.md]]：环境契约（容器内 bash）/ 跑什么（参数）/ 派发回收（我这侧）。
所以脚本里**不许出现某一轮才成立的值** —— 战役名用 `CAMPAIGN=` env 传，
测试文件是必需参数，cache 目录按 PID 隔离。写死具体测试文件名和写死用户名是同一个毛病。

**PROMPT 模板只写四样**:①目标 ②这一轮独有、猜不到的事实 ③禁碰清单 ④交付格式。
连接方式、环境配方、写权限边界**不抄进 prompt** —— 给执行者文件路径让它自己读,
这样改一次文件,所有后续执行者自动拿到最新版。步骤不用写,执行者有脑子。

**没有 handback 视为没干活**,哪怕它口头说成功。格式见 `HANDBACK-schema.md`。

---

## 5. 四阶段与文件路由

阶段之间是硬门禁,前一阶段没过不许进下一阶段。

| 阶段 | 门禁 | 读哪个文件 |
|---|---|---|
| **P0** 选机体检 | 有空间、有空闲算力、写权限已验 | `phase-p0-p1.md` |
| **P1** 打通单例(**人在场**) | 真跑出 pass + 拿到单例耗时 | `phase-p0-p1.md` |
| **P2** 定分片 | 分片方案落成文件 | `sharding.md` |
| **P3** 夜间铺开 | 早上有报告可读 | `night-run.md` |

P1 是价值所在:**没有真实耗时就无法定分片**。

其余文件按需读,**不要一次全读进上下文**:

| 文件 | 什么时候读 |
|---|---|
| `blockers.md` | **铺开前必读**,未决卡点;没解决不许铺开 |
| `boundaries.md` | 派执行者前;写权限硬边界(**也直接给执行者读**) |
| `machines.md` | 需要机器/镜像/容器具体参数时 |
| `channels.md` | 要和跑着的任务交互,或怀疑撞连接上限时 |
| `pitfalls.md` | 结果反常时;已取证的坑与根因 |
| `HANDBACK-schema.md` | 定交付格式时 |
| `RUNBOOK-template.md` | 需要给执行者一份完整手册时 |
