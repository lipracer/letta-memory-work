---
description: 从零把一台 macOS 本机配成能操作百度内网远端机器的工作站 —— relay-cli 安装、~/.ssh/config 全文、本地封装脚本清单与源码、ControlMaster 长连接的正确配法与验证。给新人或换机时照着做一遍即可复用。
---

# 本机环境搭建（可复用给他人 / 换机重建）

目标：让本机能 `ssh devbox '<cmd>'` 一句话操作内网开发机，并让**多条命令复用一次指纹认证**。

前置：内网办公网环境（或已连 VPN）、有 relay 权限、macOS。

## 1. relay-cli

所有内网机器都在 relay 审计通道后面，**不能直连**。relay-cli 是唯一入口。

| 项 | 值 |
|---|---|
| 当前版本 | `v1.0.5`（`relay-cli -v` 自查） |
| 安装位置 | `~/.local/bin/relay-cli`（27MB 单文件二进制） |
| 旧版位置 | `/usr/local/bin/relay-cli` —— **仍在 PATH 里，是隐患** |
| 升级 | `relay-cli -update` 自更新 |

⚠️ **`which -a relay-cli` 必须确认新版在前**。旧版有 `operation not supported by device` panic，
v1.0.5 已修。当前本机两个都在 PATH，靠 `~/.local/bin` 排在 `/usr/local/bin` 之前生效 ——
换机时别忘了这个顺序，或直接删掉旧的。（旧版备份在 `~/relay-cli.old.bak`。）

v1.0.5 提供的能力，本工作流只用第一条：

```bash
relay-cli proxy <host> <port> <user>   # ← SSH ProxyCommand 透传，本工作流的基础
relay-cli ssh [user@]host[:port]       # 一次命令登录
relay-cli proxy setup                  # 一键写 ssh config
relay-cli                              # 交互登录（指纹认证在这里发生）
```

**认证方式**：`-t fp`（指纹）| `qc`（扫码）| `totp`，默认自动检测。指纹认证需要**真 TTY**，
所以 agent 无法代替用户完成首次解锁 —— 每天首次由用户在 iTerm2 里手动跑一次 `relay-cli`。

**AI 模式**（Ctrl+A）本工作流不用，配置在 `~/.relay-cli/config.yaml`，
可 `disable_ai: true` 关掉。装了 ducc 的话它会自动从 `~/.baidu-cc/user.json` 读 key。

## 2. `~/.ssh/config`

下面是**可直接抄用的全文**（用户名/IP 按需替换）。

```sshconfig
# ── relay 跳板机本身 ──
Host relay relay.baidu-int.com
    HostName relay.baidu-int.com
    ControlMaster auto
    ControlPath ~/.ssh/master-%r@%h:%p
    ControlPersist yes
    ServerAliveInterval 60
    PubkeyAcceptedAlgorithms +ssh-rsa
    HostkeyAlgorithms +ssh-rsa

# ── M300/P800 开发机 node41，别名 devbox ──
Host devbox
    HostName 10.206.192.139
    User chenlonglong01
    ProxyCommand relay-cli proxy %h %p %r
    ControlMaster auto
    ControlPath ~/.ssh/master-%r@%h:%p
    ControlPersist 8h

# ── wxtky P800 集群其余节点（按 IP/主机名通配） ──
# ControlPath 必须与 devbox 段完全一致，见下文「ControlPath 分裂」
Host 10.206.19*.* wxtky02-*
    User chenlonglong01
    ProxyCommand relay-cli proxy %h %p %r
    ControlMaster auto
    ControlPath ~/.ssh/master-%r@%h:%p
    ControlPersist 8h
    StrictHostKeyChecking no
    ServerAliveInterval 30

Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    HostkeyAlgorithms +ssh-rsa
    PubkeyAcceptedAlgorithms +ssh-rsa
```

没配别名的节点用展开形式：

```bash
ssh -o ConnectTimeout=45 -o StrictHostKeyChecking=no \
    -o ProxyCommand="relay-cli proxy %h %p %r" \
    <user>@<ip> '<远端命令>'
```

### ⚠️ 坑一：ControlPath 分裂（2026-08-31 实测并修复）

`devbox`（HostName `10.206.192.139`）**同时命中 `Host devbox` 和 `Host 10.206.19*.*` 两条规则**。
两段的 `ControlPath` 若不一致：

```
Host devbox        → ~/.ssh/master-%r@%h:%p            ← 一条 socket
Host 10.206.19*.*  → ~/.ssh/sessions/master-%r@%h:%p   ← 另一条
```

后果：`ssh devbox` 和 `ssh 10.206.192.139` **各建各的 master 通道，各认一次指纹**。
现场证据是 `~/.ssh/sessions/` 空目录躺了两天，socket 全在 `~/.ssh/` 下。

→ **同一台机可能命中的所有段，`ControlPath` 必须逐字相同。** 已统一到 `~/.ssh/master-%r@%h:%p`。

### ⚠️ 坑二：首条必须串行，之后才能并发（2026-08-31 实测）

ControlMaster 复用的前提是**第一条连接先把 master 建成**。若一上来就并发发多条 ssh，
每条都发现没有 master、于是各自建连各自认证 —— 既慢又**直接撞 relay 并发上限**
（实测并发探测时后两条被 relay 断开）。

正确姿势，二选一：

```bash
# A) 先单独建 master，之后的命令才并发
ssh devbox true                 # 建 master（可能触发指纹）
ssh -O check devbox             # 应答 "Master running (pid=...)"
# …此后所有 ssh devbox 复用它

# B) 更省：多条命令合并成一次 bash -lc 送过去（推荐）
ssh devbox 'bash -lc "cmd1; cmd2; cmd3"'
```

**B 优于 A**：一次建连、一次往返，还天然避开并发上限。派任务给执行者时优先要求 B。

### 验证长连接是否真的生效

```bash
ssh -v devbox true 2>&1 | grep -iE "mux|master|control"   # 应见 "Trying existing master"
ls -la ~/.ssh/master-*                                     # socket 应落盘
time ssh devbox true; time ssh devbox true                 # 第二条应显著更快
ssh -O check devbox                                        # Master running (pid=…)
ssh -O exit  devbox                                        # 需要时显式关闭
```

⚠️ **有任务在飞时不要改 `~/.ssh/config`** —— 会打断它的连接。等回收后再动。
（改动只对新建的连接生效，已建成的 master 不受影响也不会自动采纳新配置。）

## 3. 本机封装脚本（`~/.local/bin/`）

| 脚本 | 用途 | 状态 |
|---|---|---|
| `relay-cli` | v1.0.5 二进制本体 | ✅ 在用 |
| `wxtky-probe` | 只读探测 P800 集群节点（登录性/磁盘/大目录），自带长连接 + 命令白名单 + 全审计日志 | ✅ 在用 |
| `h100` | expect 脚本，一路进到 THOR 的容器并把控制权交还用户 | ✅ 在用（需真 TTY） |
| `qa-exec` | 在 THOR 容器内非交互执行命令（`script` 伪 PTY 方案） | ✅ 在用 |
| `dev-agent` | 曾用于驱动**容器内** ducx | ❌ **已作废**，见下 |

### `wxtky-probe`：探测类脚本的正确形态

值得复用的三个设计点（新写同类脚本照抄）：

1. **长连接**：`open` 子命令先建 ControlMaster，`run` 复用，`close` 收尾 —— 一次认证。
2. **只读白名单**：正则前缀匹配 `hostname|df|du|ls|nproc|free|docker ps|…`，
   非白名单命令**直接拒绝并记日志**。探路脚本不该有写能力。
3. **全审计**：每条真正下发到远端的命令写入 `PROBE_LOG`，事后可复核。

用法：
```bash
wxtky-probe open  <ip>            # 建长连接（可能触发一次指纹）
wxtky-probe run   <ip> "<cmd>"    # 在长连接上执行只读命令
wxtky-probe check <ip>            # 标准三件套 login/df/du
wxtky-probe close <ip>
```

注意它内部 `SOCK_DIR="$HOME/.ssh/sessions"` —— 与坑一的统一路径**不一致**，
它会自己建自己的 socket。要么改成 `$HOME/.ssh`，要么接受它独立一条通道。

### `qa-exec`：relay 禁 exec 通道时的唯一通路

THOR（美研 QA 机）那条链路上，relay 服务端**禁 exec 通道也禁端口转发**，
所以不能用 ProxyCommand。绕法是 `script` 造伪 PTY 跑 relay-cli，靠 `sleep` + `echo`
按时序喂命令：

```
script 伪 PTY → relay-cli(复用当天指纹) → 跳板机 → ssh qa_work@172.19.53.15 → docker exec → 执行
```

前提：**当天用户已手动跑过一次 `relay-cli` 解锁指纹。**
用法 `qa-exec "命令"`（容器内）/ `qa-exec --host "命令"`（THOR 宿主机）。

⚠️ 脚本里硬编码了 QA 机密码。复用到别处时改成从环境变量或钥匙串取，不要照抄明文。

### `dev-agent` 为什么作废

它做的是 `ssh devbox` → `docker exec` → **在容器内跑 `ducx exec`**。
但容器内**起不了** ducx/baidu-codex：二进制确实在 `/root/.comate/.baidu-cx/*/bin/`，
**但不在 PATH**（`which ducx baidu-codex codex` rc=1）。**不要因为文件在那儿就去启动它。**

→ 现行唯一通路：**执行者跑在本机或宿主机，容器只是被 `docker exec` 操作的对象。**

## 4. 换机重建清单

```
□ 装 relay-cli 到 ~/.local/bin，确认 which -a 里它在最前
□ 抄上面的 ~/.ssh/config（改 User/IP），检查所有段 ControlPath 逐字一致
□ 用户手动跑一次 relay-cli 完成指纹解锁（需真 TTY，agent 代不了）
□ ssh devbox true 建 master，ssh -O check devbox 验证
□ time ssh devbox true 两次，确认第二次明显更快
□ 按需拷 wxtky-probe / h100 / qa-exec，改掉里面的用户名与明文密码
□ 不要拷 dev-agent
```

## 相关
- 连接形式、conda 自证、CUDA 口径、写权限边界：[[skills/remote-exec-baidu/SKILL.md]]
- relay 并发上限等未解卡点：[[skills/overnight-test-campaign/blockers.md]]
