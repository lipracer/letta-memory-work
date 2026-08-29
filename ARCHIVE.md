---
description: Retired context — no longer load-bearing, kept for historical reference only. Re-verify before acting on anything here.
---

# 归档

## 容器内 AI agent(ducx / baidu-codex / dev-agent)—— 2026-08-24 打通,2026-08-29 作废

2026-08-24 曾验证成功:容器 `chenlonglong01_m300_py312_torch212`(HOME=/root)内
`/root/.comate/.baidu-cx/baidu-cx-linux-amd64-10.147.0.3/bin/{ducx,baidu-codex}`
可用 `docker exec ... bash -lc 'export PATH=...; ducx exec "任务" --skip-git-repo-check -s danger-full-access'`
驱动(实测返回 CONTAINER_AGENT_OK,workdir=/workspace,连 oneapi-comate gpt-5.5,
凭据在 `/root/.baidu-cc/user.json`)。当时结论:默认 `--sandbox read-only` 在容器里起不来
(缺 bubblewrap),必须 `-s danger-full-access`;不支持 `--security-model`;
支持 `-c 'sandbox_permissions=["disk-full-read-access"]'` 等 config override。
配套封装 `~/.local/bin/dev-agent "任务"` = ssh devbox → docker exec → ducx exec。

**2026-08-29 作废**:用户确认容器内起不了 ducx/baidu-codex,双 subagent 实测
`which ducx baidu-codex codex` rc=1(二进制在盘上但不在 PATH)。
现行通路见 [[system/human.md]] 与 skill `overnight-test-campaign`:
本机 Letta subagent + `ssh <节点>` + `docker exec <容器>`。
