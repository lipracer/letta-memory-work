---
description: User's preference on token efficiency: act decisively, don't over-explore
---
用户对 token 效率极度敏感。深痛教训(2026-08-22 改显示名事件):为改 agent 显示名(name 字段)绕了 5+ 轮对话,原因是把我一直当成"记忆里的 persona 名字"和"harness 显示名"两码事。

关键认知:
- agent 显示名(name,界面名字栏)= harness 管理的 **agent 元数据**,只能通过会话内 **`/rename`** slash 命令改(用户自己在输入框敲)。agent 不能替他执行 `/rename`,它不在 agent 工具集里。
- 记忆 persona.md 里的"我是知行"是另一个东西(身份表述),改它不会动界面显示名。
- 重启后 harness 会从自己的 agent 状态源重新加载显示名,直接改后端 JSON 文件(如 ~/.letta/lc-local-backend/agents/*.json)harness 运行时不会采纳,是治标不治本。

行为规则:用户要改 agent 名字时,**直接说"请在输入框敲 /rename <新名>"**,这是唯一正解;不要改 JSON、不要搜源码、不要调 API。遇到用户抱怨"好麻烦/浪费 token",立刻停止探索,给出一步到位的指令。

- **我只统筹,不下场。执行主体优先 `ducx`**(2026-08-29 用户强反馈:「任务也是要给 ducx 跑啊,你只管统筹啊,探路的事情都不需要你,我不想污染你的记忆」)。
  - **探路也算任务**:`df`/`docker ps`/`docker images`/试写权限这类侦查,**一律连同正式任务一起交给执行者**。我自己 ssh 去探,原始输出(磁盘表、几十个容器名、逐条命令表)会整片灌进我的上下文 —— 这就是污染记忆,是被明确禁止的。
  - **ducx 是单向的(2026-08-30 实测)**:`ducx queue --thread <sid> --message` 对 `exec` 起的 session **无效** ——
  消息只写进 `~/.baidu-cx/queue_1.sqlite` 的 `queued_items` 表,executor 不消费(等了 10+ 轮心跳仍在)。
  `queue` 只服务交互式 `resume` session。验证后记得删那行,否则污染下次同 thread 会话。
  所以**回程只能用文件信箱**:执行者判断不了写 `NEEDS_DECISION.md`,我写 `DECISION.md`,我挂 Monitor 盯文件出现。
- **派 ducx 必须显式带三个参数(2026-08-30 实测)**:`-m <model> -c model_provider=oneapi -c model_reasoning_effort=high`。
  ①`~/.codex/config.toml` 顶层写着 `model_reasoning_effort = "low"`,**不覆盖就是低推理**,白瞎强模型;
  ②`-m` 不会自动带上 provider —— 只给 `-m` 会 fallback 到 `provider: openai` 然后死循环
  `ERROR: Reconnecting... waiting for network`(卡满 120s 无输出,极易误判成模型不可用);
  ③三个都给全时验证通过:`model: gpt-5.6-terra / provider: oneapi / reasoning effort: high`,11s 返回。
  可选模型:`gpt-5.6-terra`(最强,给硬任务)/`gpt-5.6-sol`(config 默认)/`gpt-5.6-luna`/`gpt-5.5`/`DeepSeek-V4-Flash`。
- **本机 ducx 派发**(无状态、可并发、输出不进我上下文):
    `ducx exec -m <model> --skip-git-repo-check -s danger-full-access "$(cat PROMPT.md)" > logs/<任务>/ducx.log 2>&1`
    ducx 跑在本机,能用我的 ssh config / relay-cli,自己 `ssh <节点>` + `docker exec` 下发。**stdout 重定向进任务目录,我不读它**,只读它写出来的 `handback.md`。
  - 因为 ducx 无记忆,PROMPT.md 里必须写全:机器/容器/目录**写死**、conda 自证、CUDA 口径、写权限边界、handback 格式与落盘路径。
  - Letta subagent 只在 ducx 不可用时兜底(它也有独立上下文,但比 ducx 贵、且我容易顺手读它的长篇回执)。
  - 容器内**起不了** ducx/baidu-codex(二进制在 `/root/.comate/.baidu-cx/*/bin/` 但不在 PATH),`dev-agent` 封装依赖它,同样不可用 —— 所以 ducx 跑在**本机或宿主机**,容器只是被 `docker exec` 操作的对象。
  - 收 handback 时**只读我要汇报的那几行**(结论、计数、缺口),不要 `cat` 整份报告进上下文。
- 当用户要求把事情迁到容器/远端继续时,先把当前要做的事情写进记忆并同步到远端,再开始新的执行链路。

记忆占用认知(2026-08-28 复核):每轮必定注入上下文的核心记忆主体是 `system/` 下文件——`persona.md` + `human.md` + 几个偏好文件,合计约 ~31KB(会随记录增长,要报数就现场 `wc -c system/persona.md system/human.md system/human/preferences/*.md`,别背旧数字)。磁盘上大头是 git 历史,不占上下文。`onboarding.md` 早已删除(用户已完全 onboarded),不要再提它。`reference/`、`skills/` 等非 system 文件不每轮注入,只在文件树里露路径和 description,任务相关时才 Read。用户问"记忆占比/容量/上限"这类自查时,分层回答:物理磁盘占用 vs 真正每轮注入的核心记忆块 vs 上下文窗口上限(当前 agent 128K token、单次回复 32K),不要把三者混为一谈。