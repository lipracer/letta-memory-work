---
description: 陈龙龙个人知识库(repo XKvIcmPUF0「个人笔记」等)中编译器/硬件研究类笔记的提炼索引。KB 链接格式 https://ku.baidu-int.com/knowledge/HFVrC7hq1Q/pKzJfZczuc/XKvIcmPUF0/<docGuid>
---

# 个人 KB 编译器/硬件研究笔记索引(提炼版)

> 提炼索引,非原文拷贝。要原文用 ku 工具 `query-content --doc-id <guid>` 回 KB 读。
> ku:`/Users/chenlonglong01/.letta/skills/ku-doc-manage/bin/ku`,需 `SANDBOX_USERNAME=chenlonglong01`。
> ⚠️ 迁移鲁棒性(同 inference 索引):`docGuid`/URL 是脆指针,KB 迁移会失效;每条留**中文标题**作稳定锚点,提炼正文自包含存在本 agent git 记忆里。迁移时只需换指针,正文不动。

## JAX.Pallas 第三方硬件对接分析 `fLchsq_rxz-QUl`(用户自己写的重磅分析,直接是 m300 codegen 工作资产)
用户系统调研了"把 Pallas 作为编程模型对接昆仑等第三方硬件"的可行性,结论成体系:
- **Pallas 流水线**:Python kernel → JAX tracing → Jaxpr(含 GridMapping/BlockMapping)→ `pallas_call_p` → MLIR lowering(按 platform 分发)→ 后端 IR → 后端编译器。GPU 默认 Triton、TPU 默认 Mosaic TPU、CPU 只 interpret。
- **TPU dialect 开源边界**(关键):JAX primitive→TPU dialect IR(`mosaic/lowering.py`)、dialect 定义、serde 序列化**都开源**;但 `apply_vector_layout`(vreg 映射)和**最终代码生成在 libtpu,闭源**。序列化后经 `tpu_custom_call` 交给 libtpu。
- **三种对接方案**:①复用 TPU dialect + 自己替换 libtpu(工作量最小,复用 100+ lowering rules,但绑 TPU 语义 vreg/DMA);②新建 dialect 从 Jaxpr 重写 lowering(完全自由但全部重写);③A 变体——保留 `vector/arith/scf` 走标准 MLIR,只把 `tpu.matmul`/`tpu.dma` 换成自己硬件的 op。
- **Pallas vs Triton/TileLang(为什么适合脉动阵列)**:Pallas = block 粒度 + **显式 DMA** + **显式多级内存(VMEM/HBM)** + **无 SIMT 假设**;Triton 把 shared memory/DMA 隐藏、底层是 warp/thread;TileLang 核心是线程粒度(SIMT)。脉动阵列不是 SIMT、需精确控制数据搬运时序,故 Pallas 最贴。
- **Pallas 独有能力**:kernel 内跨设备通信(TPU ICI `async_remote_copy` / GPU NVLink `remote_ref`,可在 kernel 内实现 all_gather/psum/collective matmul)、MPMD 异构核协同、计算-通信 overlap(double buffering、nested pipeline)——对 MoE all-to-all、TP、ring attention 价值大。Triton 做不到(kernel 边界=通信边界)。
- **TPU 内存层次**:VMEM(core 私有)/VMEM_SHARED(跨核共享 SRAM,核间快速通信)/SMEM/CMEM/SEMAPHORE/HBM。核间通信走 VMEM_SHARED+SEMAPHORE 不走 HBB。→ 第三方硬件若无跨核共享 SRAM,MPMD 模式难高效。
- **待确认硬件信息清单**(对接前要问):DMA 模型(异步?几个 engine?能否 overlap 计算)、内存层次、脉动阵列 feed 接口/weight 预加载、vreg 宽度与 tile 对齐、核间同步原语、有无现成 MLIR dialect。

## dma h2d 带宽 benchmark `nyRcfzRlWwziIB`
- 一段 C++ 基准脚本:测不同小 shape(如 (8,5000,65)/(16,42632) 等,short 类型)下 `cudaMemcpy` H2D 带宽,对比 pageable(malloc)vs pinned(cudaMallocHost)。WARMUP=4/MEASURE=320。Makefile 链昆仑 `xre-Linux-x86_64-5.0.21.26` 的 libcudart。测这些真实小算子形状的 h2d 拷贝开销用。

## Symbol(XPU 库符号 dump)`XogWEt5RUc20dd`
- 一大坨 `nm/readelf` 符号表(xblas_xpu3、baidu::xpu::api 的 Context/Profiler/ThreadPool、内嵌 json 库等)。查 XPU 库导出符号/mangled name 时的原始素材,无提炼价值,需要再回原文。

## 空壳(用户还没填内容,以后填了再提炼)
- pytorch `3BNvbO4ZfJxTpM`、sdn编程 `TsEPAMq9klI3EB`、9月计划 `ZUY6XmongVgzZ2`。
