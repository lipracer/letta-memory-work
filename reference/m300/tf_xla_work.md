---
description: chenlonglong01(@陈龙龙) 在 TensorFlow xpu 适配战线的工作与关键技术结论
---
# TensorFlow xpu 适配工作索引（chenlonglong01 = @陈龙龙）

数据来源：如流知识库 TF xpu 适配库，2026-08-27 用 ku-doc-manage 检索。
- 库根：`https://ku.baidu-int.com/knowledge/HFVrC7hq1Q/BeQck0ZK7s/3VD655KZzI`
- repo-id = `3VD655KZzI`（与 PyTorch 战线 AI4AMs73rr 平行，见 [[reference/m300/xpytorch_work.md]]）

## 这条战线是什么
TF/XLA 在 xtrans（昆仑 XPU 的 CUDA 兼容层）上落地。与 PyTorch/inductor 战线并行，技术栈是 TF → XLA → LLVM IR → PTX → xpu。
项目起点：最早 TF 需求文档 2023-11-07，立项申请 2023-11-22，对接排期 2023-11-26。

## 研发计划（doc `gL6u0SE2OO-PND`）：6 阶段 20 工作项
主线：业务 8 模型 → 算子盘点 → 模拟器跑通 → XLA/PTX 链路分析 → 精度/性能验证。
- S1 业务模型算子盘点(P0, 陈勇) → S2 算子单测 dump & 仓库化(P0, 陈勇) → S3 tf2.12.1+cuda12 xpu 模拟器 eager 跑通(蒋东港) → S4 XLA/LLVM IR bitcode dump(蒋东港) → **S5 PTX 种类/变体统计 + LLVM→PTX 与 CUDA 版本关系调研(我@陈龙龙)，产出 PTX 表面积报告，依赖 S4** → S6 精度对比+Zebu 性能验证。

## 核心技术结论：XLA GPU 路径当前不可用（doc `j_pMYFo0_5Khb_`, 2026-05-08）
这是整条 TF/XLA 战线的根本拦路石：
- eager / 传统 `.cu.cc` kernel（`enable_gpu=false`）→ **OK**，当前生产默认。
- XLA GPU 路径（`jit_compile=True`）→ **NG**。编译全过(HLO→LLVM→PTX→ptxas→CUBIN)，但卡最后一步 `cuModuleLoadData(cubin)` → xtrans 的 `libcuda.so`(实为 `libxpucuda.so.515.58.kunlun`)不认 NV cubin 格式，报 `CUDA_ERROR_NOT_SUPPORTED`。根因=昆仑 driver 不吃 NV cubin。
- MLIR kernel_gen(`enable_gpu=true`)产物路径同 XLA，预计同样卡，待验证。
- 生产配置：`enable_gpu=false` + 禁 `jit_compile=True` +（防 auto-cluster）`TF_XLA_FLAGS='--tf_xla_auto_jit=0'`。
- **长期解法**：照 ROCm 分叉模型给 XLA 加一个 xpu backend（不要在 TF 侧反编译 cubin fallback）。需与 xtrans/xpu LLVM 团队确认：xpu LLVM fork 是否注册了 LLVM Target、`cuModuleLoadData` 认的二进制 magic、有没有 xpu device-libs bitcode(对标 libdevice/ocml)。
- 我的 S5 任务本质=为这个长期解法铺路（摸清 PTX 变体与 CUDA 版本绑定关系）。

## 库内其他关键文档
- 06-m300/xla对接验证 `B5Tr5-I4ALbK9x`：含 01/02/03 llvmir 对接验证、`nv2xcn-llc reduce 翻译问题复现包`、TF↔XTRANS cuBLAS/cuDNN 接口矩阵。
- 05-m300环境搭建 `sF6n7arY4i5FWQ`：tensorflow-cuda12 / cuda11.7 / XPU 支持改动清单。
- 99-Legacy/00-Tensorflow立项&需求 `TBbEa4thYDFJ9R`：立项申请、初步排期、MRD&PRD 等历史文档。
