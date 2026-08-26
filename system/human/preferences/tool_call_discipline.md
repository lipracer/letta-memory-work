---
description: Hard rule: never omit Bash description param; never retry a failed tool call more than once without changing approach.
---
# 工具调用纪律（2026-08-26 用户强反馈）

用户对重复出现的 `Bash tool missing required parameter: description` 错误极度不满（同一天多次发生，我还在失败后用同样错误格式反复重试，刷屏）。

硬规则：
1. 每次 Bash 调用必须带 `description` 参数，写完调用前自查一遍。
2. 工具调用失败后，同一格式的重试最多一次；再失败必须停下来换方法或直接向用户说明，禁止无变化地连续重试。
3. 刷屏本身就是对用户信任的伤害，宁可少调用、慢回答。