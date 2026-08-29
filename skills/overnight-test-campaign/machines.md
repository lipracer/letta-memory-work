---
description: 夜间测试战役用到的机器清单、登录链路、镜像与容器参数模板(overnight-test-campaign 技能的参考文件)
---

# 机器、登录链路与镜像

> 状态标注了实测日期的才是可信的;标"未验证"的不要当成已知。

## wxtky P800 集群(XPU,内网 relay)

登录:本机 → `relay-cli proxy`(百度审计网关)→ 目标节点,账号 `chenlonglong01` 免密。
`~/.ssh/config` 中 `10.206.19*.*` 通配覆盖 192/193/194 三网段(2026-08-28 实测跨段可达)。

工具:`~/.local/bin/wxtky-probe {open|run|check|close|log}`,内置**只读白名单硬拦截**
(非 `hostname|df|du|ls|cat /proc/|free|uptime|docker ps` 等前缀直接拒绝 rc=99,
实测 `rm -rf` 被拦下)。只读探测一律用它,不要自己拼 ssh。

### 关键机器(2026-08-28 全集群 52 台实测)

| 机器 | ip | 状态 |
|---|---|---|
| **node41** | 10.206.192.139 | **用户自己的开发机。根分区仅剩 8.6G(91%),`/root` 占 57G。不要默认在此搭夜间环境。** 额外挂 `/ibm/remote-gpfs-fs01` |
| node53 | 10.206.192.151 | **空闲量最大**,ssd2/3/4 均 1%,/ssd1 剩 2.9T。夜间战役首选 |
| node115 | 10.206.192.224 | /ssd1 剩 2.5T,ssd3/4 近乎空 |
| node95 | 10.206.194.152 | /ssd3 剩 2.3T |
| node117 / node90 | .226 / 10.206.193.220 | 全盘空闲,根分区 9% |
| node42 | 10.206.192.140 | `/ssd1` 仅剩 2.2G,`/root` 26G。可用但紧 |

**避开**(盘已满或根分区告急):node2(`/var` 100% 已 0 可用)、node8(`/ssd1` 剩 35M)、
node18(根 86%)、node20/22/39/50/51/66/67(有盘 Avail=0)。

集群共性:瓶颈几乎全在 `/ssd1~/ssd4`(各 3.5T),`/ssd1` `/ssd3` 是重灾区,`/ssd2` 最宽松。
根分区 `/dev/sda2` 90G 普遍只用 9~21%。`/klxlake`(JuiceFS 4.0P)全集群一致 51%,是共享存储。
node33/node36 是**细分区机型**(根仅 19G,`/var` `/tmp` 独立),不能与 90G 单根机型按剩余量混排。

### 容器内 agent(m300)

```bash
~/.local/bin/dev-agent "任务"
# = ssh devbox → docker exec chenlonglong01_m300_py312_torch212
#   → ducx exec "$TASK" --skip-git-repo-check -s danger-full-access   (cwd /workspace)
```

agent 路径 `/root/.comate/.baidu-cx/baidu-cx-linux-amd64-10.147.0.3/bin/`,
命令名 `ducx` / `baidu-codex`(**不是 `codex`**)。

## 美研 GPU 机器

**使用前必须在群 5794977 锁卡**,且"避免从国内往这些机器拷大量数据"。用户均为 `qa_work`。

| 机器 | ip | 卡 | 密码 |
|---|---|---|---|
| THOR | 172.19.53.15 | 1×H100 | `isa1234` |
| THANOS | 172.19.53.5 | 8×A100 SXM | `isa@1234`(注意有 @) |
| ALCHEMY | 172.19.53.18 | 2×A100 NVLink + A10 + A30 + 3090 | `isa1234` |
| ATOM | 172.19.53.2 | 2×A100 + A10 + A30 | `isa1234` |

- **只有 THOR 的链路验证过**:`~/.local/bin/qa-exec "命令"`(`script` 伪 PTY → relay-cli →
  ssh qa_work → `docker exec chenlonglong01_dev`)。前提:**当天用户手动跑过一次 relay-cli 解锁指纹**。
- ALCHEMY/THANOS/ATOM **是否同样走 relay 未验证**,不要假定登录方式相同。
- 登录报 `no kex algorithm` 时:先登 THANOS 再跳转。
- 交互式进 H100 容器:`~/.local/bin/h100`(expect,触发词 `relayH100`)。

## 镜像(M300,2026-08-28 从 KU 权威文档确认)

来源:KU《M300软件产出镜像用户手册》`w_NznaMuJTnLdD`
(space `HFVrC7hq1Q` / repo `xdoVLSEXE_`,作者 狄鹏 dipeng01)。
**这是镜像的权威出处,拉之前对一下有没有更新的版本。**

### v2 (20260714) —— 当前推荐

```bash
docker pull iregistry.baidu-int.com/xpu/m300_pytorch212_ubuntu2204_x86_64_cuda12:20260714_27
```

预装 xse + xcuda + torch2.12。基础环境:

| OS | Python | PyTorch | CUDA |
|---|---|---|---|
| Ubuntu 22.04.5 LTS | 3.12.13 | 2.12.0a0+git0382020 | cuda_12.8.r12.8 |

已知问题(文档原文):
1. **GCC 版本适配** —— Ubuntu 22.04 的 GCC 是 11.4,xBLAS 和 xFA 需要编译流程适配。
2. **JITC 编译适配** —— xBLAS 编译脚本需增加识别 Ubuntu 22.04 的逻辑,转用 u20 jitc 产出。

### v1 (20260625)
`iregistry.baidu-int.com/xpu/m300_pytorch29_ubuntu2004_x86_64_cuda12:20260625_01`(torch 2.9)

### ⚠️ 这个镜像默认跑在**功能模拟器**上

容器创建后默认已设 `XPU_SIMULATOR_MODE=1`、`XPUSIM_DEVICE_MODEL=KUNLUN5`、
`XPUSIM_SIMULATOR_MODE=FUNCTION`、`CUDA_AMODEL_DLL=.../libxpusim.so`、`CUDA_AMODEL_GPU=KL005`。

**这件事彻底改变战役设计,不要忽略:**
- **不需要真实 XPU 卡,也不需要锁卡** —— 所以不必挂 `/dev/xpu*`,普通机器就能跑。
- **但模拟器远慢于真实硬件** —— P1 单例耗时必须在模拟器上实测,不能拿 GPU 经验外推。
  瓶颈从"卡"变成"CPU 和内存",选机器要看核数而不是看卡。
- 要跑真实硬件必须显式关掉模拟器,并确认目标机有卡、且已锁卡。

其他默认环境变量:`XCUDA_HOME=/usr/local/xcuda/`、`TRITON_ENABLE_XCN_BACKEND=true`,
torch / triton 均已预装 whl。

模拟器相关开关:
```bash
export XPUSIM_LAUNCH_LOG_LEVEL=DISABLE     # 关掉模拟器刷屏输出(夜间跑务必设,否则日志爆炸)
# 性能模拟器(比功能模拟器更慢,按需):
export XPUSIM_SIMULATOR_MODE=CYCLE
export XPUSIM_CA_CFG=/usr/local/xse-ubuntu_2004_x86_64/config/config.json
```

其他镜像(非 M300 主线):
- `iregistry.baidu-int.com/xmlir/xmlir_ubuntu_2004_x86_64:v0.32`
- GPU/sglang 场景:`lmsysorg/sglang:dev`

harbor 登录走 `https://sso.kunlunxin.com/`。

## 容器参数模板

### 工作目录约定(重要,先看这个再看模板)

| 层 | 路径 | 统一性 |
|---|---|---|
| 宿主机 | `/ssd<N>/chenlonglong01`,**N 按每台机器实测最空的盘选** | 不统一(集群各盘余量差异大) |
| 容器内 | `/workspace`,同时设 `-w /workspace` | **永远统一,脚本只认这个** |

**绝不把工作目录放 home 或根分区** —— 根分区普遍只有 90G(细分区机型如 node33/node36 仅 19G),
镜像+编译产物+autotune cache 会撑爆,还会连带影响同机其他人。

实测参考(`chenlonglong01_m300_py312_torch212`,2026-08-29 `docker inspect`):
```
/ssd4/chenlonglong01 -> /workspace       WORKDIR=/workspace
/ssd1 -> /ssd1   /ssd2 -> /ssd2   /ssd3 -> /ssd3   /ssd4 -> /ssd4   /klxlake -> /klxlake
```
四块 ssd 全平挂(临时放大产物方便换盘),其中一块作为 `/workspace`。
选盘参考本文件上面的集群状态:`/ssd2` 通常最宽松,`/ssd1` `/ssd3` 是满盘重灾区。

### M300 镜像模板(模拟器模式,推荐)

在官方最简模板基础上加工作目录和 shm:

```bash
SSD=/ssd2      # ← 按 P0 体检结果改,选该机最空的盘
docker_name=<战役名>_<日期>
docker_image=iregistry.baidu-int.com/xpu/m300_pytorch212_ubuntu2204_x86_64_cuda12:20260714_27

mkdir -p ${SSD}/chenlonglong01
docker run -ti -d --name ${docker_name} \
       --ipc=host --pid=host --net=host \
       --shm-size=64g \
       -v ${SSD}/chenlonglong01:/workspace \
       -v /ssd1:/ssd1 -v /ssd2:/ssd2 -v /ssd3:/ssd3 -v /ssd4:/ssd4 \
       -v /klxlake:/klxlake \
       -w /workspace \
       ${docker_image} /bin/bash
```

官方原版模板只有 `--ipc=host --pid=host --net=host`(不需要 `--device`/`--privileged`,
因为跑模拟器不用卡)。`--shm-size=64g` 别省,PyTorch 测试少了会诡异挂。

### 真实硬件模板(仅确认要上真卡时用,需先锁卡)

```bash
docker run -itd --name <name> \
  --device=/dev/xpu0 ... --device=/dev/xpu7 --device=/dev/xpuctrl \
  --privileged --net=host --shm-size=64g \
  --ulimit memlock=-1 --ulimit nofile=120000 --ulimit stack=67108864 \
  -v /ssd<N>/chenlonglong01:/workspace \
  -v /ssd1:/ssd1 -v /ssd2:/ssd2 -v /ssd3:/ssd3 -v /ssd4:/ssd4 \
  -v /klxlake:/klxlake -w /workspace --cpuset-cpus=0-120 \
  <image>
```

GPU 场景:把 `--device=/dev/xpu*` 换成 `--gpus all`。

容器内网络(拉包用):

```bash
export http_proxy=http://agent.baidu.com:8891 https_proxy=http://agent.baidu.com:8891
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
```

## 容器建好之后:跑环境初始化(必做)

来源:KU《常用命令》`iLP-gei3L_-MnK`(用户个人库 `XKvIcmPUF0`,space `HFVrC7hq1Q`)
开头的「环境初始化」代码块 —— **以文档现场内容为准,不要凭记忆复述脚本**。

它做的事:装 BOS 客户端 `bcecmd` → 写 BOS 凭据 → 从用户的 BOS 网盘拉 `boot/` →
跑 `restore.sh`。`restore.sh` 会**配好网盘挂载和用户本人的 ssh key**,
所以这一步跑完容器才能 clone 内网 git 仓库(`ssh://git@icode.baidu.com:8235/...`)。

流程位置:**建容器之后、冒烟自检之前**。顺序错了会在 clone 阶段卡住。

```bash
# 骨架(凭据与具体路径现场从 KU 文档取,勿写入记忆/脚本/仓库)
cd /tmp && wget <bcecmd zip> && unzip -o ... && cp .../bcecmd /usr/sbin/ && chmod +x /usr/sbin/bcecmd
mkdir -p ~/.go-bcecli && cat > ~/.go-bcecli/credentials <<'EOF'
[Defaults]
Ak = <从 KU 文档取>
Sk = <从 KU 文档取>
Sts =
EOF
bcecmd bos cp -r bos:/klx-pytorch-work-bd/chenlonglong01/boot/ /tmp/boot -y
cd /tmp/boot && bash /tmp/boot/restore.sh
```

BOS 网盘根目录:`bos:/klx-pytorch-work-bd/chenlonglong01/`(`bcecmd bos ls -a` 可列)。

> ⚠️ **这份 KU 文档正文里有明文长期凭据**(BOS AK/SK、GitHub token、若干机器密码)。
> 我不把这些值写进记忆或任何文件;需要时现场读文档。
> 委托 subagent 执行初始化时,让它自己去读该文档取值,不要把凭据放进 prompt 或日志。
> 也提醒用户:这些 key 已在文档里长期明文存放,建议轮换并改为环境变量注入。

该文档还是用户的常用命令总集(GPU/XPU/aot 各种 `docker run` 模板、pip 换源、
NCCL 网卡配置、sglang 启动、清共享内存、各机房机器清单),需要时按 docGuid 现场查。

## 官方冒烟验证(照抄,P1 用得上)


文档给的环境自检步骤,**这是最快确认容器可用的方式**:

```bash
# PyTorch 单例冒烟
git clone ssh://git@icode.baidu.com:8235/baidu/xpu/torch -b v2.9.0
pushd torch
    pytest test/test_ops.py::TestCommonCUDA::test_dtypes___getitem___cuda
popd
```

xBLAS / xFA 编译验证(注意上面「已知问题」里 GCC 11.4 的坑):

```bash
git clone --single-branch -j$(nproc) -b master ssh://git@icode.baidu.com:8235/baidu/xpu/xBLAS2 xBLAS2
pushd xBLAS2
    KL45_XTDK_COMPILER=ON COMPILE_FOR_DEVICES=45 KL45_XRE_DEPENDENCY=ON \
    KL45_XCCL_DEPENDENCY=ON WITH_PLUGIN=ON WITH_LIB=ON FORMAT_CHECK=OFF \
    bash script/cmake_build.sh -y
popd

git clone --single-branch -j$(nproc) -b master ssh://git@icode.baidu.com:8235/baidu/xpu/flash-attention2 flash-attention2
pushd flash-attention2
    KL45_XTDK_COMPILER=ON XPU_ARCH=5 bash -xe xsrc/script/cmake_build.sh -y
popd
```

## 常见测试问题(文档原文)

- 不想要模拟器输出 → `export XPUSIM_LAUNCH_LOG_LEVEL=DISABLE`
- 使能性能模拟器 → `export XPUSIM_SIMULATOR_MODE=CYCLE` +
  `export XPUSIM_CA_CFG=/usr/local/xse-ubuntu_2004_x86_64/config/config.json`


## 代码库

- xTorch 在**容器内** `/workspace/m300/torch_feature/xTorch`(`version.txt` = `2.12.0a0`),
  有 `test/`,无顶层 `inductor/`。宿主机看不到。
- 远端仓库 `ssh://git@dev.kunlunxin.com:30004/klx/XTrainer/xTorch.git`
- `cuda-rt-hook` 在**宿主机** `/home/users/chenlonglong01/cuda-rt-hook`(容器 `/workspace` 里看不到)
