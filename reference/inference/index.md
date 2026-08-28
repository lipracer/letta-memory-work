---
description: 陈龙龙推理方向知识库(KB「个人笔记」等)的提炼索引——每篇一句话摘要+KB链接,需细节时顺链接回 KB 读原文。KB 根:XKvIcmPUF0(陈龙龙的知识库),链接格式 https://ku.baidu-int.com/knowledge/HFVrC7hq1Q/pKzJfZczuc/XKvIcmPUF0/<docGuid>
---

# 推理方向笔记索引(提炼版)

> 这是对用户 KB 推理相关笔记的**提炼索引**,不是原文拷贝。要原文/细节时用 ku 工具 `query-content --doc-id <guid>` 回 KB 读。
> ku 工具:`/Users/chenlonglong01/.letta/skills/ku-doc-manage/bin/ku`,需 `SANDBOX_USERNAME=chenlonglong01`。
>
> ⚠️ **迁移鲁棒性(用户 2026-08-28 提出,KB 未来可能迁移)**:下面每条的 `docGuid` 和如流 URL 是**脆指针**,KB 一迁移大概率失效。但每条都同时留了**中文标题+仓库名**作为稳定锚点——guid 断了就拿标题去新系统搜。真正的资产是每条下面的**提炼文字本身**(自包含,存在本 agent 的 git 记忆里,不依赖 KB 存活)。将来若 KB 迁移:①先确认新平台的定位方式(新 id 还是仍按标题),②批量把下面的 guid/URL 换成新指针即可,提炼正文不用动。

## StepMesh(用户自己的仓库,推理通信库)`ioDCMRjXnk2sML`
- 仓库:https://github.com/lipracer/StepMesh/tree/develop (用户 GitHub=lipracer)。基于 RDMA 的 PS(parameter-server)风格通信框架,scheduler/server/worker 三角色。
- **用户干的核心活:把它适配到昆仑 XPU/KLX 后端**。CUDA 编译走 `USE_CUDA=1 make af` + `pip install --no-build-isolation -e .`;XPU 编译会报找不到 `libcuda.so`,**要手动造一个假 so**(写个空的 `cuStreamWaitValue32` 符号,`g++ -shared -fPIC` 编出 libcuda.so 塞进 /usr/local/cuda/lib64)再编。KLX 后端启动:`STEPMESH_BACKEND=KLX ROLE=joint RNIC=xgbe0 bash tests/fserver/run_single_gpu.sh`。
- 通信流程他摸透了:init→`ps::StartPS`→`Postoffice::Init`→`RdmaVan::Start`(起 CM event polling 线程)→Bind(rdma_create_id/bind_addr/listen)→所有节点连 scheduler+起 receiver 线程。首个消息是 ADD_NODE 控制包,走 `IBV_WR_SEND_WITH_IMM`(立即数=kRendezvousStart);数据面走 `IBV_WR_RDMA_WRITE` 单边直写。
- **他解过的 OOM bug**:改成给 StepMesh 注册一个大 Buffer 复用。关键坑=两端必须同时开 cache,保证 `StoreRemoteAndLocalInfo` 存的远程地址对不变,否则地址失效发送失败。
- 面试/履历弹药:这是他做推理**底层通信+国产芯片适配**的硬证据。

## RDMA 底层参考 `DRCX5JWmF06D98`
- 三层模型:连接管理(RDMA CM)→资源执行(verbs: PD/MR/QP/CQ/WR)→数据通信(Send/Recv/RDMA Read/Write/Atomic)。
- server/client 建连的完整 verbs 调用序列(create_event_channel→create_id→bind/listen vs resolve_addr/route/connect→get_cm_event→ack_cm_event)。
- 有一张**完整的 WR opcode 对照表**(双边/单边、是否需对端 Recv、是否访问远端内存、CQE 情况)——查 IBV_WR_* 语义时回这篇。

## PD分离 / DistServe `JVT9E1HPZ4joIR`
- DistServe 论文摘要:把 prefill 和 decode **拆开算**,解决两者共置时的相互干扰、以及资源分配/并行策略被耦合的问题。指标:prefill 看 TTFT(首 token 时间),decode 看 TPOT(每输出 token 时间)。严格延迟约束下,共置系统只能牺牲一个指标或过量配置资源。
- 目前只是论文笔记,没有他自己的实现记录。

## 推理规划散记 `grQmF-wUF8R9Eo`
- 零散 TODO,非成型笔记:qwen 精度问题、sglang 跑 ds-r1 / qwen3-235B、想做理论性能分析工具(memory/带宽/算力 roofline)、精度榜单统一(厂内 & 南湖 cc QA)、roofline 工具做极致性能优化。均价备注 500/12.5k。

## sglang-scheduler `gBpy5ZiIlEZ-Pc`
- 空壳,目前无内容。(用户对 sglang 调度器有兴趣但还没记东西——以后他填了再来提炼。)
