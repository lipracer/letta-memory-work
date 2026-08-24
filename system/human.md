---
description: What I know about chenlonglong01's work environment and engineering projects (work agent for 知行·工作)
---
Name: chenlonglong01(GitHub 用户名 lipracer)。算法/系统工程师,在百度工作(内网环境)。我是他的**工作角色 agent(知行·工作)**,与他共享"知行"人格(由生活 agent 知行手动复制来 persona.md + 偏好)。

> 分工:本 agent 专管**工作域**(开发机、远程容器、codex/ducx agent、qa-exec、代码库 cuda-rt-hook 等)。生活域(美股/新闻/飞书/生活偏好)在生活 agent(知行,记忆仓库 letta-memory.git)里,本 agent 不管生活细节。

## 开发机远程执行(核心通路,2026-08-24 打通)
- **本机 SSH 经 relay proxy 审计连接开发机**:开发机 = `chenlonglong01@10.206.192.139`(主机名 wxtky02-p800-8nic-vd-node41.wxtky02.baidu.com,有 3×P800 OAM XPU,跑很多容器)。
- `~/.ssh/config` 已配 `Host devbox → ProxyCommand relay-cli proxy %h %p %r`。这个 devbox 以后我记作 `node41/m300/pytorch`；`ssh devbox` 免密直接执行远端命令(已验证连通)。
- 常用容器:ghs_qwen35/luodan12_p800_tle/NODE41_IPIPE/chenlonglong01_dev/chenlonglong01_m300_py312_torch212 等。

## 远端代码库项目
- `cuda-rt-hook`(PyPI 包名 `cuda_mock`):C++/Python 库,通过修改 PLT 拦截 CUDA/XPU Runtime 接口(cudaMalloc/xpu_malloc 等),用于堆栈追踪、耗时统计、精度调试;位于 `~/cuda-rt-hook`。注意:它在**宿主机 /home/users/chenlonglong01**,容器 /workspace 里看不到(未挂载)。

## 开发机上的 codex/ducx AI agent(2026-08-24 探测)
- **宿主机 agent**:`~/.baidu-cx/baidu-cx-linux-amd64-10.147.0.3/bin/codex`(ducx 定制版,连 oneapi-comate 网关 gpt-5.5)。命令:`export PATH=$HOME/.baidu-cx/.../bin:$PATH; codex exec "任务" --skip-git-repo-check`。
- **注意**:远端 `/usr/bin/codex` 是百度 pb 数据处理工具(Codex 3.0 atlas2/flume),**不是 AI agent**,勿混淆。
- **容器内 agent(已定位并验证成功,2026-08-24)**:在你的专属容器 **`chenlonglong01_m300_py312_torch212`**(HOME=/root)里,agent 装在 **`/root/.comate/.baidu-cx/baidu-cx-linux-amd64-10.147.0.3/bin/`** 下的 **`ducx` 和 `baidu-codex`**(命令名不是 `codex`,故 `which codex` 找不到)。驱动命令(实测返回 CONTAINER_AGENT_OK):
  ```bash
  docker exec chenlonglong01_m300_py312_torch212 bash -lc 'export PATH=/root/.comate/.baidu-cx/baidu-cx-linux-amd64-10.147.0.3/bin:$PATH; ducx exec "任务" --skip-git-repo-check'
  ```
  workdir=/workspace,连 oneapi-comate 网关模型 gpt-5.5。`/root/.baidu-cc/user.json` 存用户凭据。
- **容器内 agent 沙箱限制(2026-08-24 验证)**:默认 `--sandbox read-only` 在容器里**起不来**(缺 bubblewrap,报"本地命令执行被环境挂载限制拦住",读不了文件)。**必须加 `-s danger-full-access`** 才能让 agent 真正读文件干活(容器本身已是隔离沙箱)。已验证:`ducx exec "任务" --skip-git-repo-check -s danger-full-access` 能读到 /workspace 下 migration.md 并产出分析。容器内 /workspace 是 agent 工作目录(有 m300/jit_fuser_migate/torchcompile 等),**看不到宿主机 /home/users**。
  - 另:e2e 确认容器 ducx **不支持 `--security-model`**,sandbox 走 `-s/--sandbox`(选项 read-only/workspace-write/danger-full-access),也支持 `-c 'sandbox_permissions=["disk-full-read-access"]'` 等 config override。
- **一键驱动工具 `dev-agent`(2026-08-24 已封装并验证跑通)**:`~/.local/bin/dev-agent "任务"` 封装整套链路:`ssh devbox(relay 审计)` → `docker exec chenlonglong01_m300_py312_torch212` → `ducx exec -s danger-full-access "任务"`。我在本机跑 `dev-agent "任务"` 即可驱动容器内 agent 列目录/读文件/分析。下次直接用,不必手写 docker exec 长路径。

## 远程 QA 机器
- QA 机器自动化已打通(2026-08-20):脚本 `~/.local/bin/qa-exec "命令"` 可远程在 qa_work@172.19.53.15(主机名 thor,有 H100 GPU)执行命令。原理:`script` 伪PTY 跑 relay-cli(复用当天指纹)→ 跳板机 → ssh qa(密码 isa1234)→ 执行。前提:当天用户手动跑过一次 relay-cli 解锁指纹。relay 服务端禁 exec 通道和端口转发,此 PTY 方案是唯一通路。
- H100 登录触发词为 **relayH100**(旧词"登录H100"已废弃),详见偏好文件 [[system/human/preferences/h100_login.md]];配套 expect 脚本 `~/.local/bin/h100`。

## m300 容器网络拓扑(2026-08-24 查明)
- 该容器是 **host 网络模式**(`--network host`),无独立 bridge IP、docker 端口映射为空。容器内 sshd pid 224410 只监听宿主网络下的 **22222** 端口;但 `ssh -p 22222 devbox` 落到的是**宿主机普通用户环境**(uid 589435, HOME=/home/users/chenlonglong01,有 /workspace 但非容器内),**不是容器本体**——所以"映射/ssh 进容器"这条路不通,正确方式是 `ssh devbox` + `docker exec`。
- 另一个专属容器 `chenlonglong01_dev` 也是 HOME=/root,但**没找到** codex/ducx(待确认是否也用 .comate 路径,未细查)。

## relay-cli v1.0.5(2026-08-24 升级)
- 装在 `~/.local/bin/relay-cli`(旧版在 /usr/local/bin,已备份 ~/relay-cli.old.bak)。支持:
  - `relay-cli proxy <host> <port> <user>` :SSH ProxyCommand 透传,让 SSH/VS Code/Codex/cursor 通过 relay 审计连接开发机。
  - `relay-cli ssh [user@]host[:port]`:一次命令登录开发机。
  - AI 交互模式(Ctrl+A):登录后用自然语言拆解任务逐步执行。
  - `relay-cli proxy setup`:一键配置。开发机密码存 `~/.relay-cli/devbox-passwords/<开发机地址>`。
  - 交互式 ssh 我无法直接操作,需用一次性命令模式 + 免密;旧版 `operation not supported by device` panic 已随新版本解决。

## ducx/codex 远端架构(2026-08-24 查明)
- 百度定制 codex 客户端(ducx/baidu-cx)是**瘦客户端**——配置里只有 oneapi 推理网关(`oneapi-comate.baidu-int.com` 或 `ai-chat.host:8602`),真正执行在百度服务端沙箱内,本机**看不到也枚举不到**它背后用了哪些机器(`remote_control_enrollments`/`agent_jobs` 表均空)。驱动它干活:非交互用 `codex exec "任务" --skip-git-repo-check`,或用 `codex mcp-server`(stdio MCP 端点)。macOS 无 `timeout` 命令。若用户要"本机对话、远端机器干活"且机器指定,应走 relay-cli proxy 那条 SSH 通路(见上文)把命令发到那台装了 codex 的机器,而不是依赖 ducx 客户端。

## 大任务派发策略(2026-08-24 与用户约定)
- 用户问过"大任务要不要拆/超长文档怎么传给 agent"。已答并记住:先读再派,但只读最小量;环境背景(容器/代码位置/flag)由我消化编进 prompt,agent 的领域代码让它自己读。超长文档三种传法(推荐排序):①放到 agent 可见路径(`/workspace`)让它自己读,最省 token;②我读+摘要转述成干净 prompt;③分段硬塞给 prompt(不推荐,易断上下文)。涉及容器内 agent 时最优 = docker cp 文档进 /workspace + `dev-agent "读 /workspace/xxx,然后执行 X"`。

## 本机 Letta 工作习惯(与生活 agent 通用知识)
- 记忆同步用 harness 内建 `/memory-repository`,本 agent remote 是 `letta-memory-work.git`。push/pull 由 harness 自动管理。
- backend 数据目录为 `~/.letta/lc-local-backend` 真实目录。用户偏好中文交流。
- 当前模型不支持读图(2026-08-24 实测:GLM-5.2/DeepSeek-V4-Flash 都不支持)。读 PDF/图片改走文本提取:`pip3 install --user pypdf` 后用脚本提取。文本提取对数据密集型报告反而更准。
- letta 升级流程:见生活 agent 或 `~/.local/bin/verify-letta` 验证工具(post-commit hook 自动 push)。
