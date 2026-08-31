---
description: 夜间测试战役 P0 选机体检与 P1 打通单例的完整步骤:确认镜像、建容器、环境初始化、冒烟自检、挑最小用例、P1 必须产出的五个数与分母取证(overnight-test-campaign 参考文件)
---

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
判据(按此挑,不要照抄文件名):
- 用例数**十几到二十**,不是上百 —— 单文件应能在几分钟内跑完;
- **不需要特殊硬件档位**(避开要 CUTLASS SM90+ / Blackwell 之类的);
- 不带自己的 `SKIP_TESTS` 列表(那会掩盖真实结果);
- 测试类少,依赖少。

反例特征:上百用例 + 多个测试类 + 自带 skip 列表 → 不适合当第一个。
2026-08-30 在 autotune 场景据此选中 `test_multi_kernel.py`(19 例约 200s),
落选 `test_max_autotune.py`(125 例、10 类、带 `SKIP_TESTS`)。

### 6. 真的跑一次

```bash
cd <repo>/test/inductor    # xTorch 在容器内 /workspace/m300/torch_feature/xTorch
source /root/miniconda/etc/profile.d/conda.sh && conda activate python312_torch212
export XPUSIM_LAUNCH_LOG_LEVEL=DISABLE
python -m pytest <选中的测试文件> -v --durations=0 2>&1 | tee run.log
```

**进容器必须先 activate `python312_torch212`** —— 裸 `python` 是 miniconda base(3.13,无 torch)。
`docker exec bash -lc` 每条都是新 shell,activate 不跨命令保留,
所以每条命令都要带上(或 `source` 工作目录里的 `env.sh`)。详见 `machines.md`。
日志落**工作目录**,别落 `/tmp`。

**P1 必须产出这五个数,拿不到就不许进 P2:**

| 产出 | 用途 |
|---|---|
| pass / fail / skip 计数 | 夜间跑的对比基线 |
| **单个用例平均耗时** | 反推分片粒度的唯一依据 |
| **去重后的用例总数(分母)** | 夜间验收凭据,见下方警告 |
| 缺失依赖清单 | 写进环境搭建步骤 |
| 环境变量 / config patch | 有些测试类要 `setUpClass` 打 config |

### 用例总数(分母)必须自己取证,不许抄文档

**唯一可信来源是容器内 `python -m pytest <文件> --collect-only -q`**,按文件拿真实计数,
再**按文件求并集去重**。理由(2026-08-29 查证):
- feature 文档声称"唯一权威计数器是 `count_tests.py`",但**该脚本在仓库里不存在**,
  文档里所有用例数都无法复现。
- **子特性的用例数不能逐行相加**。文档自己的去重规则就是"按文件求并集,同一文件只计一次",
  而子特性之间共享文件(例:`test_max_autotune.py` 整文件 125 个用例,被拆着计入多个分类),
  相加必然重复计数。autotune P0 六个子特性逐行相加 = 227,这个数**没有意义**,
  我曾错记成 228 并当成基线 —— 两个数都不该用。
- 分母错了有两种死法:高估则机器空转,低估则夜里跑不完;早上看到"跑了 N 个"
  也无法判断漏没漏。

`--collect-only` 与 AST 静态计数对不上时,差异本身就是信号(collect error 或条件 skip),
必须查清再进 P2,不许取个数字了事。

⚠️ **AST 数与 collect 数是两个口径,差的是数量级,不是误差。** AST 只数源码里写了多少
`test_*` 方法,`instantiate_device_type_tests` / `@parametrize` / `copy_tests` /
`make_test_cls_with_patches` 的**展开倍数不计入**;collect 一展开就乘设备数 × dtype 数。
**两栏都要留**(AST 数 / collect 数),差值本身就是"展开倍数"这个信息。
分片预算只能用 collect 数。详见 [[reference/m300/task_docs.md]]。

耗时**必须在实际要用的模式下测**(模拟器 vs 真卡差一个量级以上),不能外推。
算平均耗时时**扣掉每进程约 2-4s 的设备初始化固定开销**(2026-08-29 实测:
最简 add 用例里 device 首次初始化占 2.33~3.78s,CPU 用例仅 0.01s),
否则会把固定开销摊进每个用例、把分片估得过粗。

把这五项写进 `campaigns/<名字>/P1-baseline.md`。


