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

## 写权限边界(硬约束,违反即中止)

这些机器是**共享的**,`/klxlake` 是全集群共享存储。一次越界写可能毁掉别人几天的训练。
下面是白名单式约束 —— **没列进允许清单的写操作,一律不许做**。

### 宿主机(登录节点后):除下列之外禁止任何写操作

允许:
- `docker pull <image>`
- `docker run` / `docker start` / `docker exec`(操作**本战役自己创建的**容器)
- `mkdir -p /ssd<N>/$(id -un)/<战役目录>` —— 仅为挂载准备工作目录

禁止(不完全列举):
- 装包、改配置:`apt`/`yum`/`pip install`、动 `/etc/**`、动 `~/.ssh/**`、动 `~/.bashrc`
- 删改任何既有文件、清理别人的盘("盘满就清"绝对不许 —— 换机器,不清盘)
- `docker rm` / `docker stop` / `docker restart` **别人的容器**,或 `docker system prune`
- `kill` 任何不是自己起的进程
- 写宿主机 home、`/tmp` 之外的临时文件

盘不够就换机器,不要在共享机上做"顺手清理"。

### 容器内:只许写 `/workspace`

| 路径 | 权限 |
|---|---|
| `/workspace`(= 宿主机 `/ssd<N>/$(id -un)`) | ✅ 唯一可写区,代码、产物、日志全放这 |
| `/ssd1` `/ssd2` `/ssd3` `/ssd4` 的**其他用户目录** | ❌ 禁写(这些盘平挂进来是为了看,不是为了写) |
| `/klxlake` | ❌ **禁写** —— 全集群共享 JuiceFS,写进去影响所有人 |
| 其他用户的 home、`/home/users/<别人>` | ❌ 禁写 |

例外:环境初始化脚本(`bcecmd` / `restore.sh`)会写 `/usr/sbin/bcecmd`、
`~/.go-bcecli/`、`~/.ssh/` —— **这是容器内的 root,容器本身即隔离沙箱,允许**;
但同样的写操作在**宿主机上绝对禁止**。

### subagent 的义务

- runbook 里必须复述这份边界,派发 prompt 里也要点明"只写 `/workspace`"。
- 任何需要越界写的情况 —— **停下来报告,不许自行变通**。
  "为了跑通顺手改了个全局配置"是本战役最严重的违规。
- handback 的"异常与偏离"里必须记录任何触碰边界的尝试。

## 用户名不要写死

技能要能给别人用,也要扛住账号变化。**路径里的用户名一律现场取,不写字面量。**

```bash
# 远端节点上的用户名(在 subagent 的远端会话里取)
RUSER=$(id -un)                    # 或 ssh <节点> 'id -un'
WORKROOT=/ssd${SSD_N}/${RUSER}     # SSD_N 由 P0 体检选出
```

同理:BOS 网盘路径 `bos:/klx-pytorch-work-bd/${RUSER}/`、容器命名
`${RUSER}_<战役名>_<日期>` 都用变量拼。文档里出现的 `chenlonglong01`
只是**当前用户的实测样例**,照抄前先确认 `id -un` 是不是同一个人。

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

### 2. 建容器 —— ⚠️ 工作目录必须落在 /ssdN,不能在 home

**这是最容易在半夜炸掉整场战役的一步。** 根分区/home 只有几十 G,
镜像 + 编译产物 + autotune cache + 测试日志很快吃满,而且撑爆根分区会连带影响机器上别人的活。

**约定(照 m300 pytorch 容器的实测配置):**

| 层 | 路径 | 是否统一 |
|---|---|---|
| 宿主机 | `/ssd<N>/$(id -un)` —— **N 按每台机器实测最空的那块选** | ❌ 不统一,也不需要统一 |
| 容器内 | `/workspace`(同时是 `WORKDIR`) | ✅ **永远统一** |

所以**统一脚本只认容器内的 `/workspace`**,宿主机是 ssd1 还是 ssd4 对脚本毫无影响。
不要为了"路径统一"去强用同一块盘 —— 集群里 `/ssd1` `/ssd3` 是满盘重灾区,
`/ssd2` 最宽松,硬统一必然撞上某台机器那块盘已满。

参考实测(当前用户 `chenlonglong01` 的 `m300_py312_torch212` 容器,2026-08-29 `docker inspect`):
```
/ssd4/<user> -> /workspace              WORKDIR=/workspace
/ssd1 -> /ssd1   /ssd2 -> /ssd2   /ssd3 -> /ssd3   /ssd4 -> /ssd4   /klxlake -> /klxlake
```
四块 ssd 都平挂进去(方便临时换盘放大产物),只有一块作为 `/workspace`。

**建容器前必须先定 N**,靠 P0 的 `df -h` 输出选,并把选中的盘记进战役报告
(排查问题时"当时用的哪块盘"是关键信息)。

模板与完整 flag 见 `machines.md`;模拟器模式下官方模板很简单
(`--ipc=host --pid=host --net=host`),额外加 `--shm-size=64g`、
`-v /ssd<N>/$(id -un):/workspace -w /workspace`,以及四块 ssd 的平挂。

### 3. 跑环境初始化(配网盘 + ssh key)
容器起来是"裸"的 —— 没有网盘、没有用户的 ssh key,**clone 内网 git 仓库会直接失败**。
跑 KU《常用命令》`iLP-gei3L_-MnK` 开头的「环境初始化」脚本
(装 `bcecmd` → 从 BOS 拉 `boot/` → `bash restore.sh`,配好网盘和 ssh key)。
完整骨架和注意事项见 `machines.md`。

**只要在任何 clone 之前跑掉就行**(所以在冒烟自检之前)。漏跑的症状是 clone 阶段卡住,
半夜卡住等于整场白跑。

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
source /root/miniconda/etc/profile.d/conda.sh && conda activate python312_torch212
export XPUSIM_LAUNCH_LOG_LEVEL=DISABLE
python -m pytest test_multi_kernel.py -v --durations=0 2>&1 | tee run.log
```

**进容器必须先 activate `python312_torch212`** —— 裸 `python` 是 miniconda base(3.13,无 torch)。
`docker exec bash -lc` 每条都是新 shell,activate 不跨命令保留,
所以每条命令都要带上(或 `source` 工作目录里的 `env.sh`)。详见 `machines.md`。
日志落**工作目录**,别落 `/tmp`。

**P1 必须产出这四个数,拿不到就不许进 P2:**

| 产出 | 用途 |
|---|---|
| pass / fail / skip 计数 | 夜间跑的对比基线 |
| **单个用例平均耗时** | 反推分片粒度的唯一依据 |
| 缺失依赖清单 | 写进环境搭建步骤 |
| 环境变量 / config patch | 有些测试类要 `setUpClass` 打 config |

耗时**必须在实际要用的模式下测**(模拟器 vs 真卡差一个量级以上),不能外推。
算平均耗时时**扣掉每进程约 2-4s 的设备初始化固定开销**(2026-08-29 实测:
最简 add 用例里 device 首次初始化占 2.33~3.78s,CPU 用例仅 0.01s),
否则会把固定开销摊进每个用例、把分片估得过粗。

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
所有 subagent 必须 `cd` 到同一个战役目录,并按 `HANDBACK-schema.md` **一任务一目录**
交付:`campaigns/<战役名>/logs/<机器>-<任务>/{handback.md, run.log, 脚本, fetch.err}`。
主 agent 收齐后汇总 `campaigns/<战役名>/INDEX.md`,
**缺哪份要点出来**,不能用"整体成功"盖过去。
摘要级 run.log 要**拉回本机**并双端 md5 比对,让用户不必登机器就能翻。
用户要 review 每一条实际下发的远端命令 —— 这是硬要求,不是可选项。

### 早上的交付
`campaigns/<名字>/REPORT-<日期>.md`,必须包含:
- 与 P1 基线的 pass/fail 对比(**新增的 fail 是唯一真正重要的信息**)
- 每片实际耗时 vs 估算
- 环境搭建过程中的意外(缺包、拉镜像失败、盘满)
- 明确的下一步建议

## 常见坑

- **工作目录建在 home/根分区** —— 最常见的自毁方式。必须落 `/ssd<N>/$(id -un)`,
  容器内统一映射成 `/workspace`。选盘要看 P0 的 `df -h`,别抄别的机器的盘号。
- **越界写** —— 宿主机除 `docker pull/run/exec` 和建自己的工作目录外禁止写;
  容器内只许写 `/workspace`,`/klxlake` 和别人的目录**禁写**。详见上文写权限边界。
- **"盘满就顺手清一下"** —— 绝对不许。共享机上删的可能是别人的训练产物。换机器。
- **用户名写死** —— 路径里用 `$(id -un)`,别硬编码某个账号名。
- **新容器没跑初始化就 clone** —— 没有 ssh key,`ssh://git@icode.baidu.com:8235/...` 直接失败。
  先跑 P1 第 3 步。
- **凭据不落盘** —— 初始化用的 BOS AK/SK 在 KU 文档明文里,现场读、用完不写进任何文件、
  不进日志、不进 subagent 的 prompt。
- **没 activate 就跑 python** —— 容器 PATH 上是 miniconda base(3.13,无 torch)。
  进容器**第一件事** `source /root/miniconda/etc/profile.d/conda.sh && conda activate python312_torch212`。
  且 `docker exec bash -lc` **每条都是新 shell,activate 不跨命令保留** —— 每条都要带,
  或 `source` 工作目录里的 `env.sh`。这条不做,整夜任务会在第一跳全片 `ModuleNotFoundError`。
  2026-08-29 双 agent 独立踩到同一处。
- **用 `torch.xpu.*` 接口** —— **M300 软件栈兼容 CUDA,一律按 CUDA 写法用**:
  `torch.cuda.is_available()` / `device="cuda"` / `.cuda()` / `TestCommonCUDA`。
  实测 `torch.xpu.is_available()` = False 而 `torch.cuda.is_available()` = True,
  拿前者当 device 门禁会让用例**全部误 skip**,早上看到一片假绿。好处是上游 CUDA 测试可原样复用。
- **自己调模拟器环境变量** —— 镜像已把那一堆 `XPUSIM_*` / `CUDA_AMODEL_*` 配成自洽默认值,
  **开箱就能跑通,一个都别改**(它们互相耦合,动一个就可能整套失配)。
  唯一该主动设的是 `XPUSIM_LAUNCH_LOG_LEVEL=DISABLE`。要换档位按 `machines.md` 的成对配方改。
- **把模拟器析构日志当报错** —— pytest 结束后 stderr 打印 `Kl5Top destructed` /
  `XpuSystem destructed`,设了 `XPUSIM_LAUNCH_LOG_LEVEL=DISABLE` 也照打,退出码不受影响。
- **here-doc 写脚本** —— 引号转义反复出错。可靠做法:本机生成 → `base64 -i`(macOS **不支持
  `-w0`**)→ 容器内 `base64 -d` 落盘 → 双端 `md5sum` 比对。2026-08-29 实测一次成功。
- **别指望容器内 agent** —— 容器里起不了 ducx/baidu-codex。二进制**确实存在**于
  `/root/.comate/.baidu-cx/*/bin/` 但不在 PATH(2026-08-29 实测 `which` rc=1),
  **不要因为文件在那儿就去启动它**。执行主体是本机 subagent,经 `ssh` + `docker exec` 下发。
- **确认命令真的落在容器里** —— 2026-08-25 有过本地 subagent 被误当成容器 agent、结果作废的先例。
  用 `docker exec <容器> hostname` 之类的自证命令确认落点。
- **不要内联长脚本** —— here-doc / 引号转义反复炸(`zsh: parse error`)。
  写到容器内临时文件再执行。
- **`du` 在满盘机器上很慢** —— 限制 `-x -h -d 1`,超 30s 就跳过只留 `df`。
- **交叉复核** —— 重要结果让第二个只读 agent 独立重算一遍,不给它看第一份结果,
  只报告一致性和分歧点。

## 参考文件

- `machines.md` —— 机器清单、登录链路、镜像与容器模板
- `RUNBOOK-template.md` —— 交给 subagent 的自包含手册模板
- `HANDBACK-schema.md` —— **每个 subagent 必须回传的结构化日志格式(用户 review 用)**
- `campaigns/` —— 每次战役的分片、基线、handback、报告

