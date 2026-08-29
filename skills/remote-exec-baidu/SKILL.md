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
- **并发任务必须各用自己的子目录。** 同一 campaign 派多个执行者时,
  宿主挂载目录用 `/ssd<N>/$(id -un)/<战役名>/<任务名>/`,不要让两个执行者共享一个目录 ——
  否则 `test_add.py` / `run.log` 这类同名产物会被互相覆盖
  (2026-08-29 真实发生:后到的执行者覆盖了并行 session 的产物,靠它自己主动备份才没丢)。
  docker 会合并并发 pull,所以并行任务测出来的"pull 耗时"也不可信。
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
- `docker run` **不需要 `--privileged`,也不需要 `--network host`**
  (2026-08-29 node41 + node53 双机独立取证:默认 bridge + bind mount + `-w` 就能跑通功能模拟器,
  3 passed,device 用例 call 2.4s 真跑)。默认用最小权限起容器:
  ```bash
  docker run -d --name <容器> -v /ssd<N>/$(id -un)/<战役名>:/workspace/<战役名> \
             -w /workspace/<战役名> <镜像> sleep infinity
  ```
  真起不来再逐个加,并在报告里写明"不加会失败"及具体报错。
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
