---
description: What I know about chenlonglong01's work environment and engineering projects (work agent for 知行·工作)
---
Name: chenlonglong01(GitHub 用户名 lipracer)。AI compiler 资深工程师,了解 llvm, 熟悉 mlir, 也是 llvm 社区贡献者, 熟悉 tensorflow / pytorch, 目前在做 m300 下一代芯片 AI compiler 相关工作,包括 tensorflow xla、pytorch inductor,以及 tensorflow 整个框架适配支持(个人 KB 编译器/硬件研究笔记——JAX.Pallas 对接第三方硬件分析、dma 带宽 bench、XPU 符号——提炼索引见 [[reference/m300/kb_research_notes.md]])。熟悉 c++ / python, 也会 javascript、object-c、java、swift; 做过 iOS 开发、Windows app 开发,了解底层驱动,也熟悉 sglang。约 10 年从业经验,不止 compiler——带过端到端训练交付项目(P800/KL3 运营商,见 [[reference/m300/xpytorch_work.md]])、也负责过推理项目,推理笔记已提炼索引见 [[reference/inference/index.md]](StepMesh 国产芯片通信适配、RDMA、PD分离/DistServe 等)。核心诉求(2026-08-27 明确):把可复现的重复劳动(算子复测、PTX/性能统计、周报对齐)委托给 AI,自己腾出来专注判断与拍板。 我是他的**工作角色 agent(知行·工作)**,与他共享"知行"人格(由生活 agent 知行手动复制来 persona.md + 偏好)。

> 分工:本 agent 专管**工作域**(开发机、远程容器、codex/ducx agent、qa-exec、代码库 cuda-rt-hook 等)。生活域(美股/新闻/飞书/生活偏好)在生活 agent(知行,记忆仓库 letta-memory.git)里,本 agent 不管生活细节。

> 他的如流知识库:个人库 repo `XKvIcmPUF0`(「陈龙龙的知识库」,技术笔记主力在「个人笔记」知识本下),团队库 XPyTorch repo `AI4AMs73rr`(1.1w+ 篇)。工具 `~/.letta/skills/ku-doc-manage/bin/ku`(需 `SANDBOX_USERNAME=chenlonglong01`)。**KB 未来可能整体迁移**(用户 2026-08-28 提出),所以记忆里只存"提炼+双锚点(标题+docGuid)",不拷原文——整理/迁移流程见 skill `kb-note-distillation`。

## 开发机远程执行(核心通路,2026-08-24 打通)
- **本机 SSH 经 relay proxy 审计连接开发机**:开发机 = `chenlonglong01@10.206.192.139`(主机名 wxtky02-p800-8nic-vd-node41.wxtky02.baidu.com,有 3×P800 OAM XPU,跑很多容器)。
- `~/.ssh/config` 已配 `Host devbox → ProxyCommand relay-cli proxy %h %p %r`。这个 devbox 以后我记作 `node41/m300/pytorch`；`ssh devbox` 免密直接执行远端命令(已验证连通)。
- 常用容器:ghs_qwen35/luodan12_p800_tle/NODE41_IPIPE/chenlonglong01_dev/chenlonglong01_m300_py312_torch212 等。
- `chenlonglong01_m300_py312_torch212` 是这台机器上专门做 PyTorch 相关工作的容器。
- `m300_tf212_cuda12_chenlonglong01_20260706_162019` 是专门给 TensorFlow 做的容器。

## codex 接 oneapi 网关(2026-08-28 查证)
- 开发机 `~/.codex/config.toml` 只有 provider 段:`[model_providers.oneapi]` name=oneapi / `base_url="https://oneapi-comate.baidu-int.com/v1"` / `env_key="ONEAPI_AUTH_TOKEN"` / `wire_api="responses"`。**缺顶层 `model` + `model_provider="oneapi"`,且 ONEAPI_AUTH_TOKEN 未写进任何 rc**,即只定义未启用。token 在 `https://oneapi-comate.baidu-int.com/mine` 领(每月 1500 额度)。
- KB 里 `codex使用技巧`(`PQWWTAGaGsu0fL`)是空壳。可参考同类:`comate连接服务器使用说明 YEanljyRmEZ-iA`、`Ducc使用说明 CMZnRdLpiznoht`(自定义 gateway 走 ~/.claude/settings.json + `ducc --disable-model-proxy`)、`内网容器用 claude-code Ipdvyp6YZcABPp`(千帆 anthropic 端点包装脚本)。
- 容器内 ducx/baidu-codex **不需要 key**(靠厂内登录;`/root/.baidu-cc/user.json` 只存 ANTHROPIC_*_MODEL 等 env,无 token)。

## 远端代码库项目
- `cuda-rt-hook`(PyPI 包名 `cuda_mock`):C++/Python 库,通过修改 PLT 拦截 CUDA/XPU Runtime 接口(cudaMalloc/xpu_malloc 等),用于堆栈追踪、耗时统计、精度调试;位于 `~/cuda-rt-hook`。注意:它在**宿主机 /home/users/chenlonglong01**,容器 /workspace 里看不到(未挂载)。
- PyTorch 相关源码库: `ssh://git@dev.kunlunxin.com:30004/klx/XTrainer/xTorch.git`。这个任务先记着,明天再开始。

## 开发机上的 codex/ducx AI agent(2026-08-24 探测)
- **宿主机 agent**:`~/.baidu-cx/baidu-cx-linux-amd64-10.147.0.3/bin/codex`(ducx 定制版,连 oneapi-comate 网关 gpt-5.5)。命令:`export PATH=$HOME/.baidu-cx/.../bin:$PATH; codex exec "任务" --skip-git-repo-check`。
- **注意**:远端 `/usr/bin/codex` 是百度 pb 数据处理工具(Codex 3.0 atlas2/flume),**不是 AI agent**,勿混淆。
- **容器内 agent 已作废(2026-08-29 用户确认 + 双 subagent 实测)**:容器 `chenlonglong01_m300_py312_torch212` 里**起不了 ducx/baidu-codex**。二进制确实存在于 `/root/.comate/.baidu-cx/*/bin/`,但**不在 PATH**(`which ducx baidu-codex codex` rc=1)——**不要因为文件在那儿就去启动它**。2026-08-24 记的"已验证成功 CONTAINER_AGENT_OK"和沙箱 flag 已作废,历史细节见 [[ARCHIVE.md]]。
- **现行唯一通路:本机 Letta subagent + `ssh <节点>` + `docker exec <容器>`**,容器只是被操作对象,不是执行者。因此 `~/.local/bin/dev-agent`(ssh devbox → docker exec → `ducx exec`)也**不可用**,不要再派它。

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
- 用户问过"大任务要不要拆/超长文档怎么传给 agent"。已答并记住:先读再派,但只读最小量;环境背景(容器/代码位置/flag)由我消化编进 prompt,agent 的领域代码让它自己读。超长文档三种传法(推荐排序):①放到 agent 可见路径(`/workspace`)让它自己读,最省 token;②我读+摘要转述成干净 prompt;③分段硬塞给 prompt(不推荐,易断上下文)。涉及容器内工作时最优 = 把文档送进容器 `/workspace`(`docker cp` 或 base64 落盘),再派**本机 subagent** 经 `ssh` + `docker exec` 去读它干活(容器内 agent 已作废,见上)。

## M300 CUDA 兼容大目标(2026-08-30 用户交代)
M300 硬件**在编译层面兼容 CUDA**。终极目标:用**自己编译的 PyTorch + 自研 CUDA 兼容运行时**,
覆盖**上游 PyTorch 的全部单元测试**。夜间战役、autotune 分片这些都是该目标下的子任务。
判读口径由此确定(细节见 skill `overnight-test-campaign` 开头):测试套件是上游的,
不许改测试去适配后端;**大面积 skip 比 fail 危险**(fail 暴露缺口,skip 是假装通过);
分母按上游全量算(当前 DENOM=4959);相对基线**新增的 fail 是最重要的产出**。
长期产出是一张持续演进的**兼容性缺口清单**,不是一次性绿灯。

## 夜间远端测试战役(2026-08-28 起沉淀为可复用流程)
用户要做 M300 PyTorch **autotune**(torch.compile,6 个子特性 ~228 用例)的夜间批量测试:委托 agent 登录环境 → 体检磁盘 → 拉镜像建容器 → 搭环境 → 调度分片跑测试。**该套测试没有统一 runner,必须由 agent 统一调度分配。** 用户明确要求(2026-08-28):**先不跑,先把工作流定义清楚、沉淀成可复用流程**;并认同"先跑通一个例子,后面就好办"。
流程已固化为技能 `overnight-test-campaign`(四阶段硬门禁:P0 选机体检 → P1 打通单例(人在场)→ P2 定分片 → P3 夜间铺开),机器/镜像/环境事实在其 `machines.md`,subagent 手册模板 `RUNBOOK-template.md`,回传格式 `HANDBACK-schema.md`。**做这类任务先加载该技能,不要凭记忆复述细节。**
用户在 2026-08-29 追加的四条硬约束(细节在技能里):①**执行主体是本机 subagent**,连接/体检/建目录/起容器/冒烟每个环节都委托出去,不在主上下文逐条 ssh;②**每个 subagent 必须回传结构化 handback**(机器 ip、状态、工作目录、容器名、进容器后逐条命令原文+rc、结果计数、远端日志路径+行数+md5),完整测试日志留远端,**没有 handback 视为没干活**;③**写权限边界**:宿主机除 `docker pull/run/exec` 和建自己工作目录外禁止任何写,容器内只许写 `/workspace`,`/klxlake` 和其他用户目录禁写("盘满就顺手清"绝对不许,换机器);④**技能里不许写死用户名**,路径用 `$(id -un)`。
四条决定性环境事实(展开与命令见技能 `machines.md`,别凭记忆复述):①官方镜像默认跑**功能模拟器**,不用真卡不用锁卡,瓶颈是 CPU/内存,那堆 `XPUSIM_*`/`CUDA_AMODEL_*` **开箱可用一个都别改**;②**M300 软件栈兼容 CUDA,一律按 CUDA 写法用**(`torch.cuda.is_available()`/`device="cuda"`/`TestCommonCUDA`)——实测 `torch.xpu.is_available()`=False,用它当门禁会让用例全部误 skip(假绿比报红危险),好处是上游 CUDA 测试可原样复用;③进容器**每条命令**都要先 activate 统一环境 `python312_torch212`(`docker exec bash -lc` 每条是全新 shell,activate 不跨命令);④容器建好后须跑 KU`iLP-gei3L_-MnK` 的环境初始化(BOS→`restore.sh` 配网盘+ssh key)才能 clone 内网仓库,**必须在任何 clone 之前**跑掉;该文档正文有明文长期凭据(BOS AK/SK、GitHub token、密码)——现场读取,不落盘不进 prompt,已建议用户轮换。宿主机工作目录 `/ssd<N>/$(id -un)`(N 按各机最空盘选)→ 容器内统一 `/workspace`。
镜像权威出处:KU《M300软件产出镜像用户手册》`w_NznaMuJTnLdD`,当前 v2 `iregistry.baidu-int.com/xpu/m300_pytorch212_ubuntu2204_x86_64_cuda12:20260714_27`。
2026-08-29 机制试点已通:两个本机 subagent 各进容器跑最简 torch add,3 passed × 2,交叉复核一致 —— `本机 → ssh devbox → docker exec → pytest` 这条链路是验证过的。下一步 P1 用 `test_multi_kernel.py`(14 用例)取分片基线;注意 feature 文档里到处引用的 `count_tests.py` **实际不存在**(AUDIT 标为复现性缺陷),228 这个用例数要重新取证。

## GPU 机器与测试环境
- 美研 GPU 机器：ALCHEMY（172.19.53.18，A100/3090/A10/A30）、THANOS（172.19.53.5，8×A100 SXM）、ATOM（172.19.53.2，A100/A10/A30）、THOR（172.19.53.15，H100）。使用前需在 5794977 群锁卡，避免从国内大量拷数据。
- THOR 的现有自动化通路已验证；ALCHEMY/THANOS/ATOM 的登录链路仍需实际验证。ATOM 在出现 no kex algorithm 时，记录的备用方式是先登录 THANOS 再跳转。
- GPU 测试流程适合封装成按需 skill，但具体测试命令、环境初始化和各机器容器入口尚未统一确认；不要在这些信息未确认时假定所有机器登录方式相同。

## 本机 AI CLI:ducc / ducx / 原生 codex(2026-08-28 实测)
- 本机三条线都在:`ducc`(`~/.comate/baidu-cc/bin/ducc`,百度对标 Claude Code)、`ducx`/`baidu-codex`(`~/.baidu-cx/baidu-cx/bin/`,对标 Codex,走 oneapi 网关,会自更新)、原生 OpenAI `codex`(`~/.local/opt/node/bin/codex`)。**ducc/ducx 免 key**(靠厂内登录);原生 codex 缺 `ONEAPI_AUTH_TOKEN`,现在跑不了,别用。
- 安装方式:ducc/ducx **不走 npm**,随 Comate AI IDE 装(`https://comate.baidu.com/zh/download#aiIde`,员工账号登录),或 Comate settings 里 ducc 那栏"重新安装";装的时候**必须关代理**,否则连不上 `ducc-auth.baidu-int.com:8201`。
- **选模型机制两边不同(已实测)**:
  - `ducx exec -m <model> --skip-git-repo-check -s danger-full-access "任务"` —— `-m` **无状态**、每次调用生效。可选 `gpt-5.5 / gpt-5.6-luna / gpt-5.6-terra / gpt-5.6-sol / DeepSeek-V4-Flash`。
  - `ducc` 的 `--model` 在 `-p` 模式下**不生效**(报 `[claude-code:unrecognized_model]` 但任务照跑、用的还是旧模型);必须先 `ducc config model '<名>'` **全局**切,再 `ducc -p "任务"`。代价:全局有状态,并发派不同模型会互相踩;用完记得切回 `auto`,并在报告里写明用了哪个模型。ducc 模型池大得多(auto/GLM-5.x/Grok/gpt-5.x/Claude Sonnet 5/Opus 5/Kimi K3/MiniMax-M3/DeepSeek-V4-Pro),但 Claude/Grok 这类外部模型要代码库 L0 密级授权,内网仓大概率走不通。
- **任务分派原则(2026-08-28 定)**:分界线是"有没有并发和状态污染"——批量可复现劳动(算子复测、PTX/性能统计)→ **ducx**(无状态 `-m`,可并发,开发机容器 `dev-agent` 本来就是这条);读改大量代码的长任务(如 xTorch 源码摸底)→ **ducc**(Claude Code 血统,工具/subagent 生态更稳,可挑更强模型);周报对齐/文档汇总这类轻量文本活 → `ducc -p` 配 `auto` 即可。

## 本机 Letta 工作习惯(与生活 agent 通用知识)
- 记忆同步用 harness 内建 `/memory-repository`,本 agent remote 是 `letta-memory-work.git`。push/pull 由 harness 自动管理。
- backend 数据目录为 `~/.letta/lc-local-backend` 真实目录。用户偏好中文交流。
- 当前默认工作区是 `/Users/chenlonglong01/workspace/zhixing-work`；后续与该会话相关的工作默认以这个目录为准。
- 工作/生活两个 agent 的配置不要混用；模型可以分别配置，connect/通道也按 agent 或项目分开管理，不默认共享同一套。
- 当前模型不支持读图(2026-08-24 实测:GLM-5.2/DeepSeek-V4-Flash 都不支持)。读 PDF/图片改走文本提取:`pip3 install --user pypdf` 后用脚本提取。文本提取对数据密集型报告反而更准。
- letta 升级流程:见生活 agent 或 `~/.local/bin/verify-letta` 验证工具(post-commit hook 自动 push)。
- 存在兄弟工作 agent **xpytorch-team**(id `agent-local-5ac1c143-...`,workspace `/Users/chenlonglong01/workspace/xpytorch-team`,模型 `GLM-5.3-Flash`),专做 XPyTorch 团队相关。它和本 agent 各自独立、记忆不共享;用户可能让我隔空探它状态(用 messaging-agents 发消息做健康检查)或帮忙排查。
- **安全终止卡死的 letta CLI 进程**(2026-08-27 教训):本机常同时跑多个 `node .../letta` CLI 进程(本 agent、生活 agent、xpytorch-team 等)。用户说"某个会话窗口卡死、杀了它"时,**绝不能盲目 kill**——先 `ps` 列出所有 letta 进程,用**每个进程的 cwd**(如 `lsof -p <pid> -d cwd` 或 ps 的工作目录)区分是哪条会话,认准目标再动手;尤其要先定位并保护本 agent 自己那条会话的 pid(杀错会中断当前对话)。流程:先 `kill`(TERM)让其优雅退出,卡到不理信号再 `kill -9`。agent 记忆/会话在服务端,杀终端进程不丢数据,重开 `letta` + `/resume` 即可恢复。
