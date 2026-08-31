---
name: remote-exec-baidu
description: Connect to and run commands on 百度内网 remote machines (P800/M300 开发机 node41/node53 等、美研 GPU 机 THOR/THANOS/ALCHEMY/ATOM) through relay-cli, plus docker exec into M300 PyTorch containers. Load this before any remote command dispatch — it carries the exact connection forms, the conda/CUDA self-proof rules, and the write-permission boundaries. Also give this file to stateless executors (ducx/codex/subagents) so they do not have to be told the connection syntax step by step.
---

# 百度内网远端执行

所有内网机器都在 relay 审计通道后面,**不能直连**。下面是已验证可用的形式。

## 开发机(P800 / M300)

`node41` 已配 Host 别名,直接用:
```bash
ssh devbox '<远端命令>'
```
`devbox` = `chenlonglong01@10.206.192.139`(wxtky02-p800-8nic-vd-node41),nproc 208。

### ⚠️ 连接复用:先建常驻 master,否则每条命令都弹一次指纹

**根因(2026-08-31 实测定性)**:`ssh devbox '<cmd>'` 顺带建起的 master 是**那条 ssh 的子进程**。
执行者给远端命令套 `timeout`、或任务被 kill 时,**杀进程组会把 master 一起带走** ——
`ControlPersist 8h` 写了也没用,它活不到 8 小时。下一条命令发现没 master,重新认证。
表现就是"又开始一直弹认证"。

**解法:让 master 独立于任何任务进程树。派任务前先跑这一条(会弹一次指纹,仅一次):**
```bash
ssh -MNf -o ControlPersist=8h devbox     # -M 显式 master  -N 不执行命令  -f 后台常驻
ssh -O check devbox                       # 应答 Master running (pid=…)
```
实测证据:建成后连续 `ssh devbox` 每条 **0.8s**、无弹窗;把子 ssh 用 `kill -9 -- -PID`
**整组杀掉,master pid 不变、后续命令继续复用**。这就是它抗 timeout 的原因。

**执行者侧规则**:
```bash
# ✅ 最优:多条命令合并成一次 bash -lc,一次往返
ssh devbox 'bash -lc "cmd1; cmd2; cmd3"'
# ❌ 禁止:master 未建成就并发发多条独立 ssh —— 各自认证、被 relay 断连
```

⚠️ **`timeout` 是 GNU coreutils,macOS 本机没有**(实测 `rc=127 command not found`)。
所以"每条命令带 timeout"只能写在**远端 `bash -lc` 里面**;本机侧要限时用
`ssh -o ConnectTimeout=` 或后台 + 条件轮询。

配置前提:`~/.ssh/config` 里同一台机可能命中的**所有 Host 段,ControlPath 必须逐字相同**。
曾分裂成 `~/.ssh/master-…` 与 `~/.ssh/sessions/master-…` 两套,导致 `ssh devbox` 和
`ssh <ip>` 各建一条通道各认一次;现已统一到 `~/.ssh/master-%r@%h:%p`。

⚠️ **有任务在飞时不要改 `~/.ssh/config`** —— 会打断它的连接。等回收后再动。

📄 本机从零搭建(relay-cli 安装、config 全文、封装脚本清单、换机清单):
[[skills/remote-exec-baidu/setup.md]]

**其他节点没有别名**,用完整形式(`~/.ssh/config` 里的 relay proxy 写法展开):
```bash
ssh -o ConnectTimeout=45 -o StrictHostKeyChecking=no \
    -o ProxyCommand="relay-cli proxy %h %p %r" \
    <user>@<ip> '<远端命令>'
```
已验证节点:node53 = `10.206.192.151`(nproc 192)。其余候选 node115/95/117/90、node33/36。

要新增别名就往 `~/.ssh/config` 加 `Host <名> / HostName <ip> / User <user> / ProxyCommand relay-cli proxy %h %p %r`。

## 美研 GPU 机(qa_work)

THOR(H100,172.19.53.15)有封装好的脚本:
```bash
~/.local/bin/qa-exec '<命令>'
```
原理:`script` 伪 PTY 跑 relay-cli(复用当天指纹)→ 跳板机 → `ssh qa` → 执行。
**前提:当天用户手动跑过一次 relay-cli 解锁指纹。** relay 服务端禁 exec 通道和端口转发,PTY 是唯一通路。
交互式进容器另有 `~/.local/bin/h100`(expect,触发词 relayH100)。
其余:THANOS 172.19.53.5、ALCHEMY 172.19.53.18、ATOM 172.19.53.2 —— 登录链路**未实测**,别假定和 THOR 一样。
用卡前要在群 5794977 锁卡。

## 踩过的坑

- 本机 macOS 的 zsh **没有 `timeout` 命令**,别用它包 ssh。
- 交互式 ssh 我无法操作,只能用**一次性命令模式**(`ssh host '...'`)。
- `docker pull` 26GB 镜像要 **35~45 分钟**(2026-08-29 node53 实测下界 37 分钟),不是十几分钟,
  **绝对不要以为卡死就重试**。而且 ssh stdout 会在两分钟左右断流、`PULL_RC` 再也回不来 ——
  要计时就**把 pull 输出重定向到远端文件**,别靠 ssh stdout 回传;
  判断是否拉完用只读旁证:`docker images` 有 tag + image id/size + 盘用量增长 + 已无 pull 进程。
  (2026-08-29:没写这句,执行者连发 4 次同一条 pull。)
- **node41 上 docker 默认 bridge 网络的出网 HTTPS 会被劫持,必须用 `--network host` 才能出网**
  (2026-08-29 三方对照取证,`VERDICT=machine-wide` 那个初判是错的):
  | 位置 | 结果 |
  |---|---|
  | 宿主机 | **通**,BOS 返正常的 `403 AccessDenied` |
  | bridge 容器(172.17.0.2) | **被劫持** |
  | `--network host` 容器 | **通**,与宿主一致 |
  劫持者是这台机器上的 **IBM Storage Scale(GPFS)管理界面**:bridge 里
  `bj.bcebos.com` 被解析到 **10.6.145.191:443**,握手拿到的是自签证书
  `OU=gpfsgui, CN=wxtky02-p800-8nic-vd-node41`,加 `-k` 后返回的 body 是
  `<title>Log In - IBM Storage Scale</title>` 的 HTML 登录页 —— 不是 BOS 响应。
  两边 proxy 环境变量都为空(`env | grep -i proxy` rc=1),**不是 proxy 配置问题**,
  是 bridge 的 DNS/路由把公网域名指向了本机 gpfsgui 服务。
  → **所以 node41 上凡是需要出网的容器(BOS/restore.sh 初始化、pip、clone)一律加 `--network host`。**
  只跑测试、不出网的容器仍用默认 bridge(最小权限)。
- 症状识别:`x509: certificate is valid for <本机名>, not <目标域名>` 或
  证书 `OU=gpfsgui` = **踩到 bridge 劫持**,不是"机器没网",更不是证书库坏了。
  加 `--no-check-certificate` / `-k` **治不了**,只会把代理的登录页当成正文拿回来
  (rc 仍非 0,或拿到一堆 HTML) —— 遇到这个先换 `--network host` 重试,别去改证书库。
- `Host key verification failed` 只是 known_hosts 缺条目,和凭据无关;
  但它常常是**上游 ssh key 没配好**的下游症状,别只治它。
- **并发任务必须各用自己的子目录。** 同一 campaign 派多个执行者时,
  宿主挂载目录用 `/ssd<N>/$(id -un)/<战役名>/<任务名>/`,不要让两个执行者共享一个目录 ——
  否则 `test_add.py` / `run.log` 这类同名产物会被互相覆盖
  (2026-08-29 真实发生:后到的执行者覆盖了并行 session 的产物,靠它自己主动备份才没丢)。
  docker 会合并并发 pull,所以并行任务测出来的"pull 耗时"也不可信。
- **干净镜像里没有 Triton**(2026-08-29 取证):`torch._inductor.exc.TritonMissing:
  Cannot find a working triton installation`。**凡是走 inductor 生成 kernel 的测试会整片 fail**
  (`test_multi_kernel.py` 19 例 → 0 passed / 17 failed / 2 skipped)。
  这不是环境搭错,是镜像本身不带 —— 要跑 inductor 类测试**必须先解决 Triton**,
  否则夜间铺开只会拿到一片同因失败。派活前先问:这批测试需不需要 Triton。
  昆仑定制版 xtriton wheel(用户 2026-08-29 提供,**公开 bucket 免凭据,但要 `--network host` 才下得动**):
  `https://klx-public.bj.bcebos.com/luodan12/xtriton/0828/triton-3.6.0+gitdf5a9bcd-cp312-cp312-linux_x86_64.whl`
  (`cp312` 配 `python312_torch212`;**用户说后面会升级,用前先问最新 URL**)。
  装完必须双自证:`import triton; print(triton.__version__, triton.__file__)`
  + `from torch._inductor.runtime.triton_compat import HAS_TRITON; print(HAS_TRITON)`。
- **`HAS_TRITON=True` 不等于能跑 inductor 测试**(2026-08-29 血证):xtriton 3.6.0 装好、
  `HAS_TRITON` 为 `True`,`test_multi_kernel.py` 仍是 **0 passed / 17 failed**,
  错误换成 `RuntimeError: 0 compatible backends for target (cuda) ([]). There should only be one.`
  —— 即 Triton 本体在、但**没有注册可用的 cuda 后端**。
  所以 Triton 类环境的验收门禁**必须是"某个 inductor 测试真的 pass"**,
  不能停在 import 自证;两层都过了才算环境就绪。

### M300 跑 `test/inductor`:xcn 后端 + target bridge(2026-08-30 隔离实验取证)

跑通需要**两件事同时成立**,缺一个都是 `0 compatible backends for target (cuda)`:

1. **`TRITON_ENABLE_XCN_BACKEND=true`** —— 注册 xcn 后端的开关。
   不设:`backends` = `['triton_shared','xpu']`;设了:`['triton_shared','xcn']`。
   (我 2026-08-29 第一次诊断就是漏了它,才误判成"wheel 缺 cuda 后端、要换包"。**结论是错的**。)
2. **target bridge**(`sitecustomize.py` monkeypatch `triton.compile`)——
   把 inductor 传来的 `GPUTarget(backend="cuda")` 换成 `GPUTarget(backend="houyi", arch="xpu5", warp_size=32)`。
   **xcn 注册了也不接受 `cuda` target**:设了 env 后
   `make_backend(GPUTarget('cuda',0,32))` 依然 `RuntimeError: 0 compatible backends`。
   `houyi/xpu5` 是目前已知唯一能匹配 xcn 的 target 形式。
   靠 `PYTHONPATH=.` 让 Python 启动时自动 import 当前目录的 `sitecustomize.py`,patch 才生效。
   bridge 出处:用户仓库 `torchcompile-test`(长期容器内
   `/workspace/m300/baidu/personal-code/torchcompile-test`,入口 `test_xpu.sh`)。

实测有效的完整调用。**这条命令的已核实真值是 `13 passed / 4 failed / 2 skipped`**
(2026-08-30 两次逐用例一致;早先记的 `4 passed / 12 failed / 3 skipped` 是**环境不完整**
那次的产物,已作废 —— 见 `overnight-test-campaign/blockers.md`)。
配方必须逐字照抄,**少一项(尤其 `PYTHONPATH=.`)就会拿到虚低的 pass 数,而且报出来的是"测试红"不是"环境错"**:
```bash
cd <源码树外的工作目录>   # 树根下跑会被本地 torch/ 遮蔽
TC_PLATFORM=xpu TRITON_ENABLE_XCN_BACKEND=true TORCHINDUCTOR_COMPILE_THREADS=1 \
LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/local/xcuda/targets/x86_64-linux/lib/" \
PYTHONPATH=. python -m pytest <测试文件相对路径> -q
# 例(2026-08-30 取证时用的): xTorch/test/inductor/test_multi_kernel.py
```
`TORCHINDUCTOR_COMPILE_THREADS=1`:编译子进程会丢掉 monkeypatch,必须单线程。
上层张量/device 全程仍是 **CUDA 口径**(`TEST_DEVICE=cuda:0`),不要改成 `torch.xpu`。

**bridge 必需,已用严格对照实证**(2026-08-30,同一用例 `test_inplace_update`,唯一变量是 `PYTHONPATH=.`):
- 有 bridge:`1 passed, 18 deselected in 62.89s`
- 无 bridge:`rc=124`,**硬超时 900s 仍未出汇总行**(≥14× 慢)
注意失败形态:**去掉 bridge 不是报 `0 compatible backends`,而是"跑不完"** ——
inductor 内部不走裸 `make_backend(GPUTarget('cuda'))`,不报错,改走某条极慢的回退路径。
→ 教训:**这类环境问题不能只看"有没有报错",要看"有没有在合理时间内 pass"**;
派这类验证一律带 `timeout`,否则会一直挂着并被误读成"在正常跑"。
`TC_PLATFORM` / `LD_LIBRARY_PATH` 是否必需仍未逐项拆完(非阻塞,照抄全套即可)。
→ 这修正了上面"M300 一律按 CUDA 写法"那条:**eager 层按 CUDA 写没错,
但 inductor→triton 这一跳需要显式 target 转换,不会自己发生。**
- **`--collect-only` 的计数会随环境变化,不是静态事实**(2026-08-29 取证):装 Triton 前后
  同一批 16 个文件从 **1997 → 2994**(+997)。变化来自 Triton 条件分支/import 层跳过恢复,
  例:`test_compile_subprocess.py` 966→1930、`test_triton_heuristics.py` 0→24、
  `test_coordinate_descent_tuner.py` 0→5、`test_best_config.py` 0→1、`test_custom_op_out_lowering.py` 3→6。
  → **分母必须在"最终跑测试的那个环境"里取**,环境一变就要重取;
  上轮 rc=5 "no tests collected" 往往是缺依赖导致的整体跳过,不是文件真没用例。
- **不要在 PyTorch 源码树根目录下跑 pytest**:源码里的 `torch/` 目录会遮蔽已安装的 torch 包,
  报 `ModuleNotFoundError: torch.version`(2026-08-29 实测)。
  正确做法:`cd` 到源码树**外面**,用测试文件的绝对/相对路径跑
  (如 `cd <工作目录> && python -m pytest xTorch/test/inductor/xxx.py`)。
- **没有 pytest-xdist**(2026-08-29 取证):干净镜像里没装,`pytest -n` 不可用。
  旧容器 `chenlonglong01_m300_py312_torch212` 里的 xdist-3.8.0 是后装的。
  分片要靠**多进程各跑各的文件**,别指望 `-n`。
- 一条命令失败**最多重试一次**,再失败换方法或停下报告。

## docker exec 进 M300 容器

```bash
ssh <节点> "docker exec <容器> bash -lc '<命令>'"
```

**`bash -lc` 每条都是全新 shell,`conda activate` 不跨命令保留。** 每条跑 python 的命令都得自己 activate:
```bash
source /root/miniconda/etc/profile.d/conda.sh && conda activate python312_torch212 && <命令>
```
自证(对不上就停):`/root/miniconda/envs/python312_torch212/bin/python`、`3.12.13`、torch `2.12.0a0+git0382020`。
裸 `python` 是 miniconda base 3.13.13,**没有 torch**。

### 落点自证:用挂载目录的哨兵文件,**不要用 hostname**

必须证明"我真在目标机器的容器里",否则整轮工作作废
(2026-08-25 事故:本机 subagent 被当成容器内 agent;2026-08-29 事故:自证规则本身误判)。

**正确做法 —— 哨兵文件**(对 host / bridge 网络都成立,顺带证明挂载真的通了):
```bash
TOKEN="$(date +%s)-$RANDOM"
ssh <节点> "echo $TOKEN > /ssd<N>/\$(id -un)/<战役名>/.sentinel"      # 宿主写
ssh <节点> "docker exec <容器> bash -lc 'cat /workspace/<战役名>/.sentinel'"  # 容器读
# 读回的串 == TOKEN 才算落点正确
```

**`hostname` 不能当凭据。** 它只在 `--network host` 时才显示宿主名;默认 bridge 网络下返回的是
容器 id,看起来"不像目标机器",会把好环境误判成落错地方。同理 `pwd` 也不可靠 —— 复用已存在的
容器时 `-w` 不生效,pwd 可能是 `/home`。
hostname / id -un / pwd 仍值得**记录进报告**留档,但**不作为门禁**。

## 硬规矩(违反即作废)

- **device 一律 CUDA 口径**:`torch.cuda.is_available()` / `device="cuda"` / `.cuda()`。
  **禁止 `torch.xpu.*`** —— 实测 `is_available()` 为 False,会让用例整片误 skip 变**假绿**(比报红危险)。
  M300 软件栈就是兼容 CUDA 的,上游 CUDA 测试可原样复用。
- **`XPUSIM_*` / `CUDA_AMODEL_*` 镜像已配好,一个都不要改。** 只允许 `export XPUSIM_LAUNCH_LOG_LEVEL=DISABLE` 静音。
  官方镜像默认跑**功能模拟器**,不用真卡不用锁卡,瓶颈是 CPU/内存。
- **写权限边界**:宿主机只允许 mkdir 自己的工作目录 + `docker pull/run/exec` + 只读侦查
  (`hostname`/`df`/`nproc`/`docker ps`/`docker images`);容器内只允许写 `/workspace/<战役名>`。
  `/klxlake`、其他用户目录、别人的容器**一律禁碰**(禁 stop/rm/exec)。**"盘满就顺手清"绝对不许,换机器。**
- 路径里**不要写死用户名**,用 `$(id -un)`。宿主工作目录 `/ssd<N>/$(id -un)/<战役名>`,N 按各机最空盘挑。
  **各机可写的盘不一样**:node53 的 `/ssd2` 是 root 所有、写不进去,`/ssd4` 可写 —— 别拿别的机器的结论套。
- `docker run` **跑测试不需要 `--privileged`,也不需要 `--network host`**
  (2026-08-29 node41 + node53 双机独立取证:默认 bridge + bind mount + `-w` 就能跑通功能模拟器,
  3 passed,device 用例 call 2.4s 真跑)。默认用最小权限起容器:
  ```bash
  docker run -d --name <容器> -v /ssd<N>/$(id -un)/<战役名>:/workspace/<战役名> \
             -w /workspace/<战役名> <镜像> sleep infinity
  ```
  真起不来再逐个加,并在报告里写明"不加会失败"及具体报错。
  **但容器要出网就必须加 `--network host`**(node41 bridge 会被 gpfsgui 劫持,见上文);
  需要初始化/pip/clone 的容器加它,只跑测试的不加。
- 容器内 `/root/.comate/.baidu-cx/*/bin/` 下的 `ducx`/`baidu-codex` **不在 PATH,起不来,不要启动它们**。
  执行主体是你自己(或本机 ducx),容器只是被 `docker exec` 操作的对象。

## 已知非报错

pytest 尾部的 `Kl5Top destructed` / `XpuSystem destructed` 是正常析构日志,忽略。

## 传文件进容器

不要用 here-doc(引号层数容易炸)。用 base64:
```bash
B64=$(base64 -i local.py | tr -d '\n')   # macOS 的 base64 没有 -w0
ssh <节点> "docker exec <容器> bash -lc 'echo $B64 | base64 -d > <远端路径>'"
```
写完用 `wc -l` + `cat -A` 验证行尾是真 `$` 换行而不是字面 `\n`,并双端 `md5sum` 比对。

## 相关

- 夜间批量测试的完整战役流程:`overnight-test-campaign` 技能(阶段门禁、分片、回传格式)
- 镜像权威出处:KU《M300软件产出镜像用户手册》`w_NznaMuJTnLdD`
- 容器网盘/ssh key 初始化(clone 内网仓库前必须先跑):KU `iLP-gei3L_-MnK`
