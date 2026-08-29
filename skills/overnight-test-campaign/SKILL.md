---
name: overnight-test-campaign
description: This skill should be used when the user wants to run a large batch of tests overnight (半夜/夜间跑) on remote GPU/XPU machines by delegating to agents — including environment and disk precheck, pulling images and building containers, sharding test suites that have no unified runner, and collecting an auditable report by morning. First campaign is the M300 PyTorch Autotuning (torch.compile) suite. Load this before scheduling any unattended remote test run.
version: 0.1.0
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
| **P1 打通单例** | 建容器 → **跑环境初始化(配网盘+ssh key)** → 冒烟 → **手动跑通一个最小用例** | 拿到真实 pass/fail + 单例耗时 |
| **P2 定分片** | 用 P1 的耗时反推分片粒度和总时长 | 分片方案落成文件 |
| **P3 夜间铺开** | `letta cron` 触发,agent 按 runbook 执行 | 早上有报告可读 |

P1 是整套东西的价值所在:**没有真实耗时就无法定分片**,没跑过一次就不知道环境缺什么。
P1 一定要人在场。

## P0:选机与体检

**先确认这批测试跑在真实硬件还是模拟器上 —— 这决定了选机标准。**
M300 官方镜像默认开功能模拟器(`XPU_SIMULATOR_MODE=1`),不需要卡也不需要锁卡,
瓶颈是 CPU/内存,选机看**核数和盘**;真实硬件才需要看卡、挂 `/dev/xpu*`、提前锁卡。
详见 `machines.md`。

先体检再拉镜像 —— 镜像动辄几十 G,盘不够会在半夜失败得很难看。

用 `~/.local/bin/wxtky-probe`(只读白名单,详见 `RUNBOOK-template.md`):

```bash
wxtky-probe check <ip>     # hostname + df -h + du -x -h -d 1 /
```

体检清单:
- **根分区剩余** —— 拉镜像建容器主要吃这里。`< 30G` 视为不可用,先换机器或先清理。
- **数据盘** —— 测试产物、autotune cache 放这里,挑 `/ssdN` 有余量的。
- **CPU 核数 / 负载** —— 模拟器模式下这是主要瓶颈(`nproc`、`uptime`)。
- **别人的任务** —— `docker ps` 看有没有正在跑的训练。共享机抢资源会毁掉别人的活。
- **锁卡** —— 仅真实硬件需要;美研 GPU 机必须先在群 5794977 锁卡。

已知机器状态见 `machines.md`。两个必须记住的坑:
- **node41(10.206.192.139)是用户自己的开发机,根分区常年吃紧**(2026-08-28 实测仅剩 8.6G,
  `/root` 占 57G)。**不要默认在这台上搭夜间环境。**
- 空闲量大的:node53(10.206.192.151,ssd 三块 1%)、node115、node95、node117、node90。


## P1:打通单例(人在场)

### 1. 确认镜像
镜像 tag **绝不能猜**。M300 的权威出处是 KU《M300软件产出镜像用户手册》`w_NznaMuJTnLdD`,
当前版本和容器模板见 `machines.md`。拉之前先确认 registry 可达。

```bash
docker pull <registry>/<image>:<tag>          # 先拉,失败得早比失败得晚好
```

### 2. 建容器
用 `machines.md` 里的模板。模拟器模式下官方模板很简单
(`--ipc=host --pid=host --net=host`,不需要 `--device`/`--privileged`),
建议只额外加 `--shm-size=64g` 和一个 `-v <产物目录>:/output`。

### 3. 跑环境初始化(必做,顺序不能错)
容器起来是"裸"的 —— 没有网盘、没有用户的 ssh key,**clone 内网 git 仓库会直接失败**。
先跑 KU《常用命令》`iLP-gei3L_-MnK` 开头的「环境初始化」脚本
(装 `bcecmd` → 从 BOS 拉 `boot/` → `bash restore.sh`,配好网盘和 ssh key)。
完整骨架和注意事项见 `machines.md`。

**位置:建容器之后、冒烟自检之前。** 放错顺序会在 clone 阶段卡住,而且是半夜卡住。

凭据在那份 KU 文档正文里明文写着 —— **现场读取,不落盘、不进 prompt、不进日志**。

### 4. 冒烟自检
先用镜像文档给的官方单例确认容器本身没问题(见 `machines.md`),
**再**去跑目标测试。这一步能把"环境坏了"和"测试本身失败"区分开,省掉大量误判。

模拟器模式记得先 `export XPUSIM_LAUNCH_LOG_LEVEL=DISABLE`,否则日志被模拟器输出淹掉。

### 5. 挑最小用例
挑选原则:**用例数最少、依赖最少、不需要特殊硬件档位的那个子特性**。
autotune 场景推荐 `test_multi_kernel.py`(14 个用例,H2 即可,不需要 CUTLASS SM90+/Blackwell)。

不要一开始就挑 `test_max_autotune.py`(125 个用例、10 个测试类、还带 `SKIP_TESTS` 列表)。

### 6. 真的跑一次

```bash
cd <repo>/test/inductor    # xTorch 在容器内 /workspace/m300/torch_feature/xTorch
python -m pytest test_multi_kernel.py -v --durations=0 2>&1 | tee /tmp/p1.log
```

**P1 必须产出这四个数,拿不到就不许进 P2:**

| 产出 | 用途 |
|---|---|
| pass / fail / skip 计数 | 夜间跑的对比基线 |
| **单个用例平均耗时** | 反推分片粒度的唯一依据 |
| 缺失依赖清单 | 写进环境搭建步骤 |
| 环境变量 / config patch | 有些测试类要 `setUpClass` 打 config |

耗时**必须在实际要用的模式下测**(模拟器 vs 真卡差一个量级以上),不能外推。

把这四项写进 `campaigns/<名字>/P1-baseline.md`。


## P2:定分片

分片依据按优先级:

1. **按硬件档位分** —— 这是硬约束,不是优化。H2(普通 GPU)、H3(CUTLASS SM90+ /
   Blackwell / CK / XPU)必须落到能跑的机器上,否则全是 skip 或 error。
2. **按子特性/测试文件分** —— 天然边界,失败时好定位。
3. **按 P1 耗时配平** —— 让每片时长接近,避免一片跑到早上还没完。

用 P1 的单例耗时估总时长:`用例数 × 平均耗时 × 安全系数 2`。
**超过夜间窗口就要砍范围**,不要指望它跑得比估算快。

分片方案写成文件(一行一项,像 `wxtky-survey/shard_*` 那样),让 subagent 读文件而不是读我的 prompt。

## P3:夜间铺开

### 触发
用 `letta cron` 建定时任务(加载 `scheduling-tasks` 技能拿准确 flag,别背)。
一次战役用**一次性 cron**,不要建成 recurring——跑砸了会每晚重复烧机器。

### 委托
给每片起一个 subagent,**登录方式和执行纪律全部写进 runbook 文件**,不写进 prompt
(见 `RUNBOOK-template.md`)。prompt 里只说:cd 到哪、读哪个 runbook、负责哪个分片文件、交付什么格式。

这样做的理由:登录链路知识不该占我的上下文,而且下次换人换机器只改 runbook。

### 并发上限
**最多 2 路。** 2026-08-28 实测 4 路并行时本机堆了约 80 个 relay 长连接,
5 台出现 `Connection timed out during banner exchange`。relay 网关是共享瓶颈,
不同节点也会互相影响。

### 长连接
`ControlMaster auto` + `ControlPersist 8h`,socket 在 `~/.ssh/sessions/`。
**relay 指纹认证是 per-host 的,N 台就是 N 次首连认证,省不掉**;
长连接省的是同一台机器上后续命令的重连(实测 12s+ → ~0.9s)。
夜间任务要注意 8h 窗口:凌晨建的连接白天可能已过期。

### 审计
所有 subagent 必须 `cd` 到同一个战役目录,日志汇到一个文件。
用户要 review 每一条实际下发的远端命令 —— 这是硬要求,不是可选项。

### 早上的交付
`campaigns/<名字>/REPORT-<日期>.md`,必须包含:
- 与 P1 基线的 pass/fail 对比(**新增的 fail 是唯一真正重要的信息**)
- 每片实际耗时 vs 估算
- 环境搭建过程中的意外(缺包、拉镜像失败、盘满)
- 明确的下一步建议

## 常见坑

- **新容器没跑初始化就 clone** —— 没有 ssh key,`ssh://git@icode.baidu.com:8235/...` 直接失败。
  先跑 P1 第 3 步。
- **凭据不落盘** —— 初始化用的 BOS AK/SK 在 KU 文档明文里,现场读、用完不写进任何文件、
  不进日志、不进 subagent 的 prompt。
- **容器内 ducx 必须 `-s danger-full-access`** —— 默认 `read-only` 在容器里起不来(缺 bubblewrap)。
- **容器内命令名是 `ducx` / `baidu-codex`,不是 `codex`**,在
  `/root/.comate/.baidu-cx/baidu-cx-linux-amd64-*/bin/`,`which codex` 找不到。
- **确认 agent 真的跑在容器里** —— 2026-08-25 有过本地 subagent 被误当成容器 agent、结果作废的先例。
- **不要内联长脚本** —— here-doc / 引号转义反复炸(`zsh: parse error`)。
  写到容器内临时文件再执行。
- **`du` 在满盘机器上很慢** —— 限制 `-x -h -d 1`,超 30s 就跳过只留 `df`。
- **交叉复核** —— 重要结果让第二个只读 agent 独立重算一遍,不给它看第一份结果,
  只报告一致性和分歧点。

## 参考文件

- `machines.md` —— 机器清单、登录链路、镜像与容器模板
- `RUNBOOK-template.md` —— 交给 subagent 的自包含手册模板
- `campaigns/` —— 每次战役的分片、基线、报告

