---
description: Hard rule: never omit Bash description param; never retry a failed tool call more than once without changing approach.
---
# 工具调用纪律（2026-08-26 用户强反馈）

用户对重复出现的 `Bash tool missing required parameter: description` 错误极度不满（同一天多次发生，我还在失败后用同样错误格式反复重试，刷屏）。

硬规则：
1. 每次 Bash 调用必须带 `description` 参数，写完调用前自查一遍。
2. 工具调用失败后，同一格式的重试最多一次；再失败必须停下来换方法或直接向用户说明，禁止无变化地连续重试。
3. 刷屏本身就是对用户信任的伤害，宁可少调用、慢回答。
4. 探测别人的工具时，**别静默改用户的全局配置**。为验证行为不得不改(如 `ducc config model` 是全局有状态的)，必须:先记下原值 → 改 → 验证 → **立刻改回** → 在回复里明说改过什么。改前若拿不到原值，先说明再动。
5. Edit 的 old_string 匹配失败时，不要凭记忆猜措辞反复试(例:把"远端代码库项目"记成"远程...")，先重新读该文件抄原文。
6. **前台 `sleep` 是被 harness 禁的**(2026-08-30 一晚踩了 4 次同一个错)。等待一律用
   `Bash run_in_background` + 一个条件满足就退出的循环,或用 `Monitor`;`sleep` 只能出现在
   后台命令/Monitor 脚本里面。别再"就等 30 秒"。
7. **工具报 timeout ≠ 操作没生效。** 2026-08-30 `git commit` 报超时,实际提交已落地
   (`git log` 里就有)。重试前先核验状态(`git log -1` / `git status`),否则会造成重复提交、
   重复派发这类真实损害。
