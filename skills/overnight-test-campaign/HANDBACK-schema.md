---
description: 每个 subagent 必须回传的结构化交接日志格式(overnight-test-campaign 技能的参考文件),用户要逐条 review
---

# 回传契约(handback)

**硬要求:每个 subagent 跑完必须回传一份结构化日志,用户要逐条检查。**
没有回传的 agent 视为没干活 —— 哪怕它说"成功了"。

## 远端存 vs 回传本机

| 类型 | 存哪 | 理由 |
|---|---|---|
| 完整测试日志(pytest 输出、模拟器输出、编译日志) | **只存远端** `/workspace/<战役名>/logs/` | 动辄几十万行,拖回来没意义 |
| 机器/容器/命令的**元信息 + 结果摘要** | **必须回传本机** `campaigns/<战役名>/logs/<机器>-<任务>/` | 用户 review 的对象;也是复现依据 |
| **摘要级 run.log**(几十行的 pytest 汇总) | **拉回本机**,并双端 md5 比对 | 用户要能直接翻,不必再登机器 |

远端大日志不回传,但**必须回传它的绝对路径、行数、`md5sum`** —— 这样事后能定位、能验证没被改过。

## 文件位置与命名:**一任务一目录**

```
campaigns/<战役名>/
├── INDEX.md                          # 主 agent 汇总索引表(必须有)
└── logs/<机器>-<任务>/                # 一个 subagent 一个目录
    ├── handback.md                   # 本文件定义的结构化回传
    ├── run.log                       # 从容器拉回的 pytest 日志(md5 须与远端一致)
    ├── <实际执行的脚本>                # 如 test_add.py / shard_03.sh
    └── fetch.err                     # 拉取过程 stderr(0 字节 = 干净)
```

例:`logs/node53-multi_kernel/`、`logs/node115-precheck/`、`logs/devbox-agentA/`。

**不要把所有 agent 的报告平铺在一个 handback/ 目录里** —— 一个 agent 的产出不止一份 md
(还有 run.log、脚本、stderr),平铺会让"哪个文件属于哪个任务"迅速失控。
一任务一目录,主 agent 只维护 INDEX.md。

拉回日志的标准动作:
```bash
mkdir -p campaigns/<战役名>/logs/<机器>-<任务>
ssh <节点> "docker exec <容器> bash -lc 'cat <远端日志>'" \
  > campaigns/<战役名>/logs/<机器>-<任务>/run.log \
  2> campaigns/<战役名>/logs/<机器>-<任务>/fetch.err
md5 -q .../run.log        # macOS;与远端 md5sum 比对,不一致就是传输出了问题
```

## 模板(subagent 照此填写)

```markdown
# <阶段> / <节点> / <分片>
agent: <subagent 标识>    开始: <ISO 时间>    结束: <ISO 时间>

## 机器
- ip: <ip>
- hostname: <实际 hostname 命令输出>
- 状态: 根分区剩余 <X>G / 选中数据盘 <ssdN> 剩余 <Y>G / nproc <N> / load <a,b,c>
- 同机他人任务: <docker ps 看到的、或"无">
- 卡: <真卡型号数量 且已锁 / 模拟器模式,不需要卡>

## 工作目录
- 宿主机: /ssd<N>/<user>
- 容器内: /workspace
- 选这块盘的理由: <df 输出里它最空 / 其他>

## 容器
- name: <容器名>
- image: <registry/image:tag>   ← 抄实际 tag,不许写"最新"
- container id: <短 id>
- 落点自证: `docker exec <name> bash -lc 'hostname; id -un; pwd'` → <原始输出三行>
- **conda 环境自证**: activate 后 `which python; python -V; python -c "import torch; print(torch.__version__)"`
  → <原始三行;预期 .../envs/python312_torch212/bin/python / 3.12.13 / 2.12.0a0+git0382020>
- 环境初始化(BOS/ssh key): <已跑,restore.sh rc=0 / 未跑,原因>

## 容器内执行的命令(逐条,不省略)
| # | 时间 | 命令原文 | rc | 耗时 | 输出摘要 |
|---|---|---|---|---|---|
| 1 | 21:40:12 | `hostname; id -un; pwd` | 0 | 0.4s | node53 / <user> / /workspace |
| 2 | ... | ... | ... | ... | ... |

## 测试结果
- pass / fail / skip: <数字,抄 pytest 汇总行>
- 单例平均耗时: <数字>
- 失败用例清单: <用例名 + 失败原因原文摘一句;无则写"无">

## 远端日志
- 路径: /workspace/<战役名>/logs/<文件名>
- 行数: <wc -l 输出>
- md5: <md5sum 输出>

## 异常与偏离
<跑的过程中任何与 runbook 不一致的地方、重试、跳过、临时变通。没有就写"无"。>

## 写操作自查(必填)
- 宿主机上执行过的写操作: <逐条列出;应只有 docker pull/run/exec 和 mkdir 工作目录>
- 容器内写过 `/workspace` 之外的路径吗: <否 / 是 + 具体路径 + 原因>
- 碰过 `/klxlake` 或其他用户目录吗: <否 / 是 —— 是则必须解释>
```

## 填写纪律

- **命令原文照抄** —— 不改写、不美化、不合并、不省略。用户 review 的就是这个。
  一条命令一行,包括失败的和重试的。
- **数字抄输出** —— pass/fail 数、耗时、剩余空间都从命令输出里抄,**不估算不换算**。
- **凭据一律 `<REDACTED>`** —— BOS AK/SK、token、密码绝不进 handback。
  涉及凭据的命令写成 `cat > ~/.go-bcecli/credentials <<EOF  # <REDACTED>`。
- **失败也要完整记录** —— 失败的 handback 比成功的更有价值。不要因为没跑成就不写。
- **写操作自查必填** —— 宿主机应只有 docker pull/run/exec + 建工作目录;
  容器内应只写过 `/workspace`。有越界必须如实写出来,隐瞒比越界更严重。
- **不许只交一句"完成了"** —— 没有这份文件就等于没干活。

## 主 agent 的责任

收齐所有 handback 后,在 `handback/INDEX.md` 汇总一张索引表,让用户一眼看全:

`| 阶段 | 节点 | 容器 | 工作目录 | 命令数 | pass/fail/skip | 远端日志 | handback 文件 |`

**缺哪份要点出来**,不要用"整体成功"盖掉某个 agent 没回传的事实。
