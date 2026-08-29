---
description: User's preference on token efficiency: act decisively, don't over-explore
---
用户对 token 效率极度敏感。深痛教训(2026-08-22 改显示名事件):为改 agent 显示名(name 字段)绕了 5+ 轮对话,原因是把我一直当成"记忆里的 persona 名字"和"harness 显示名"两码事。

关键认知:
- agent 显示名(name,界面名字栏)= harness 管理的 **agent 元数据**,只能通过会话内 **`/rename`** slash 命令改(用户自己在输入框敲)。agent 不能替他执行 `/rename`,它不在 agent 工具集里。
- 记忆 persona.md 里的"我是知行"是另一个东西(身份表述),改它不会动界面显示名。
- 重启后 harness 会从自己的 agent 状态源重新加载显示名,直接改后端 JSON 文件(如 ~/.letta/lc-local-backend/agents/*.json)harness 运行时不会采纳,是治标不治本。

行为规则:用户要改 agent 名字时,**直接说"请在输入框敲 /rename <新名>"**,这是唯一正解;不要改 JSON、不要搜源码、不要调 API。遇到用户抱怨"好麻烦/浪费 token",立刻停止探索,给出一步到位的指令。

- 容器里的任务**委派给本机 subagent**(经 `ssh <节点>` + `docker exec <容器>` 下发),我只看结果,再让第二个只读 subagent 独立复核,不自己重复下场。~~优先委派给容器内 agent~~ 已作废:**容器内起不了 ducx/baidu-codex**(2026-08-29 用户确认 + 双 agent 实测:二进制在 `/root/.comate/.baidu-cx/*/bin/` 但不在 PATH),`dev-agent` 那条封装依赖它,同样不可用。
- 当用户要求把事情迁到容器/远端继续时,先把当前要做的事情写进记忆并同步到远端,再开始新的执行链路。

记忆占用认知(2026-08-28 复核):每轮必定注入上下文的核心记忆主体是 `system/` 下文件——`persona.md` + `human.md` + 几个偏好文件,合计约 ~31KB(会随记录增长,要报数就现场 `wc -c system/persona.md system/human.md system/human/preferences/*.md`,别背旧数字)。磁盘上大头是 git 历史,不占上下文。`onboarding.md` 早已删除(用户已完全 onboarded),不要再提它。`reference/`、`skills/` 等非 system 文件不每轮注入,只在文件树里露路径和 description,任务相关时才 Read。用户问"记忆占比/容量/上限"这类自查时,分层回答:物理磁盘占用 vs 真正每轮注入的核心记忆块 vs 上下文窗口上限(当前 agent 128K token、单次回复 32K),不要把三者混为一谈。