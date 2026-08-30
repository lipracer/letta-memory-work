---
name: overnight-test-campaign
description: This skill should be used when the user wants to run a large batch of tests overnight (半夜/夜间跑) on remote GPU/XPU machines by delegating to agents — including environment and disk precheck, pulling images and building containers, sharding test suites that have no unified runner, and collecting an auditable report by morning. First campaign is the M300 PyTorch Autotuning (torch.compile) suite. Load this before scheduling any unattended remote test run.
version: 0.1.1
---

# 夜间远端测试战役(overnight test campaign)

无人值守的远端批量测试。核心矛盾:测试没有统一 runner,机器状态不一,而我半夜不在场
—— 所以**一切必须先在有人看着的时候打通一遍**,再交给夜里的 agent 重复执行。

## 铁律:先打通一个,再铺开

**永远不要把没跑通过一次的测试放进夜间批量。** 未验证的批量在半夜只会产出一堆
error,第二天没有任何可用信息,白烧一晚机器。

分四阶段,阶段之间是硬门禁(gate),前一阶段没过不许进下一阶段:

| 阶段 | 做什么 | 门禁 |
|---|---|---|
| **P0 选机 & 体检** | 登录、看盘、看卡、确认镜像可拉 | 目标机有足够空间和空闲卡 |
| **P0.5 通链路试点** | 拿**已有容器**派 2 个 subagent 跑一个最简用例(如 torch add) | 委托链路本身跑通 + 双份 handback |
| **P1 打通单例** | 建容器 → **跑环境初始化(配网盘+ssh key)** → 冒烟 → **手动跑通一个最小用例** | 拿到真实 pass/fail + 单例耗时 |
| **P2 定分片** | 用 P1 的耗时反推分片粒度和总时长 | 分片方案落成文件 |
| **P3 夜间铺开** | `letta cron` 触发,agent 按 runbook 执行 | 早上有报告可读 |

⚠️ 这四道门禁是**线性的,但 P1 的冒烟门禁会反复触发**:环境每变一次(装包/改 env/换镜像/
换机器)就退回冒烟,重新拿到"1 个用例真 pass"才能继续。详见下一节。

P1 是整套东西的价值所在:**没有真实耗时就无法定分片**,没跑过一次就不知道环境缺什么。
P1 一定要人在场。

### 环境每动一次,就要重新冒烟一次(2026-08-29 用户强反馈)

原话:「在开始大规模测试前,一定要冒烟测试,任何环境改了都要先冒烟测试试试,
比如这次任务跑 triton,比如重新装包等,省的浪费这么多 agent」。

**门禁不是一次性的,是每次环境变更后都要重过。** 装包、换镜像、改 env、加挂载、
换机器、换源码树 —— 任何一项动过,先跑那个最小用例,**看到真的 pass 再往下**。
一次冒烟几十秒;跳过它,代价是一个 agent 十分钟起步,而且拿回来的信息量为零。

**冒烟的通过标准是"至少 1 个用例真的 pass",不是"import 成功、没报错、装完了"。**
2026-08-29 血证:xtriton 装好、`HAS_TRITON=True`、pip 报 `Successfully installed`,
三个自证全绿,但 `test_multi_kernel.py` 依然 0 passed / 17 failed
(`0 compatible backends for target (cuda)`)。**import 层自证会给出假绿。**

反面教材(同一晚烧掉的 agent 派次):
1. clone 失败(网络被 bridge 劫持)→ 2. clone 失败(缺凭据)→ 3. 跑测试全红(镜像无 Triton)
→ 4. 装完 Triton 跑测试**还是**全红(后端为空)。
第 3、4 次都是"改完环境直接铺大任务",各自烧一个 agent 才发现环境根本不通。
若每次改完先冒烟一个用例,第 3、4 次能在几十秒内暴露,不必带着 16 文件 collect 和
19 用例全量跑一起陪葬。

推论:**把重环境验证和重数据采集拆成两个动作。** 先派一个廉价的冒烟(1 个用例,`-x -q`),
过了再派采集基线和分母的大活。不要把"验证环境"和"取数据"塞进同一个 prompt ——
环境不通时,后面那堆采集全是废动作。

**P0.5 不许跳。** 它验的不是测试,而是**委托链路本身**:subagent 能不能起来、
命令能不能落进容器、handback 格式能不能被填对。用已有容器 + 最简用例做,成本极低,
2026-08-29 试点就是靠它抓出 `conda activate` 缺失(否则夜间 200+ 用例会整片
`ModuleNotFoundError`)。派两个 agent 到隔离子目录、互不参照,顺带拿到交叉复核。

## 执行模型:本机 subagent 下发,不依赖容器内 agent

**容器里起不了 ducx/baidu-codex(2026-08-29 用户确认)。** 别再指望"把任务丢给容器内 agent
自己干" —— 唯一可靠的执行主体是**本机的 Letta subagent**,它通过
`ssh <节点>` + `docker exec <容器>` 把命令下发进去。容器只是被操作的对象,不是执行者。

每个环节都委托给 subagent,不要我自己在主上下文里逐条 ssh:

| 环节 | 委托内容 |
|---|---|
| 连接 / 体检 | 建长连接、`df -h`、`nproc`、`docker ps`,回报选机结论 |
| 建目录 | 定 `/ssd<N>`、`mkdir -p` 工作目录 |
| 拉镜像 / 起容器 | `docker pull` + `docker run`(参数见 `machines.md`) |
| 环境初始化 | 跑 BOS `restore.sh` 配网盘和 ssh key |
| 冒烟测试 | 官方单例 + 目标最小用例,回报 pass/fail 和耗时 |
| 夜间分片 | 每片一个 subagent,按 runbook 执行 |

委托纪律:prompt 里只写"cd 到哪、读哪个 runbook、负责什么、交付什么格式";
登录链路、容器名、路径约定全部写在 runbook 文件里(见 `RUNBOOK-template.md`)。
这样我的上下文不被登录细节占满,换机器只改 runbook。

**每个 subagent 跑完必须回传一份结构化 handback**(格式见 `HANDBACK-schema.md`):
机器 ip / hostname / 盘与负载状态、选中的工作目录、容器名与 image tag、
**进容器后逐条执行的命令原文 + rc**、测试结果计数、远端日志的路径+行数+md5。
完整测试日志留在远端不回传,但元信息和摘要必须回来 —— **用户要逐条 review,这是硬要求。**
没有 handback 的 agent 视为没干活,哪怕它口头说成功。

## P0→P3 四阶段(详见各参考文件)

| 阶段 | 目标 | 文件 |
|---|---|---|
| **P0 选机体检** | 找到能用的机器、确认磁盘与写权限 | `phase-p0-p1.md` |
| **P1 打通单例**(人在场) | 建容器、装环境、**真跑出一个 pass**、取五个数 | `phase-p0-p1.md` |
| **P2 定分片** | 用 P1 耗时定分片粒度,写成分片队列文件 | `scheduling.md` |
| **P3 夜间铺开** | 多机小批 + 按回收速度续投,早上有报告 | `scheduling.md` |

## ⚠️ 先看阻塞清单

**安排任何无人值守铺开之前,先读 `blockers.md`。** 里面是实证踩出来的未决卡点
(relay 指纹跨零点失效、relay 并发上限 vs 多机铺开、pass 数不稳定)。
**没解决就不许铺开** —— 会整片断在连接上,或拿到不可信的数据。

## 参考文件

按需读,不要一次全读进上下文:

| 文件 | 什么时候读 |
|---|---|
| `blockers.md` | **铺开前必读**;未决卡点清单 |
| `boundaries.md` | 派任何执行者之前;写权限硬边界(**也直接给执行者读**) |
| `phase-p0-p1.md` | 做 P0/P1 时;建容器、环境初始化、冒烟、取分母 |
| `scheduling.md` | 做 P2/P3 时;分片、调度、窗口与收工、并发、审计 |
| `pitfalls.md` | 踩坑时;常见坑与规避 |
| `machines.md` | 需要机器/镜像/容器参数时(**也直接给执行者读**) |
| `RUNBOOK-template.md` | 给执行者的自包含手册模板 |
| `HANDBACK-schema.md` | 定义执行者必须回传的结构化格式 |
| `campaigns/` | 每次战役:`runs/<时间戳>-<机器>-<任务>/` 一次派发一个新目录(不复用),外加 INDEX.md |

远端连接方式、conda 自证、CUDA 口径 → 另一个技能 `remote-exec-baidu/SKILL.md`
(**那份也是给无状态执行者的简报,派活时把路径给它,不要抄进 prompt**)。
