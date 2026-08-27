---
description: chenlonglong01(@陈龙龙) 在 XPyTorch/M300 知识库中负责的工作与关键文档索引
---
# XPyTorch / M300 工作索引（chenlonglong01 = @陈龙龙）

数据来源：如流知识库 XPyTorch 库，2026-08-27 用 ku-doc-manage 检索。
- 知识库根：`https://ku.baidu-int.com/knowledge/HFVrC7hq1Q/BeQck0ZK7s/AI4AMs73rr`
- repo-id = `AI4AMs73rr`，space=HFVrC7hq1Q，group=BeQck0ZK7s(XPyTorch)

## 用户带过的训练交付项目:P800/KL3 电信运营商模型支持(doc `PbEn1-DpqF_3a1`，2024年，用户主写、后被人移动)
KL3 第一个外部训练客户,用户负责端到端交付+复盘。这是他"带过训练项目"的硬证据,面试/履历可用。
- **覆盖模型(一人一模型端到端)**:resnet50、yolox/yolov5、bert-large、ChatGLM-6B、qwen7B/14B、SD2.1、GPT-NeoX-20B、llama2-7B/13B/70B。含单卡→8卡→多机(llama70B 4机调试)。
- **目标**:精度对齐 A100/竞对、性能达 GPU 90%。
- **他踩过并解决的真实坑(可作面试"过来人"弹药)**:
  - 8卡 chatglm-6b 增 layer 后某算子规模越界溢出,定位+修复各花一周;
  - yolox 单卡 OK、多卡因 dataloader 多进程加载导致 loss 跟 GPU 对不齐,定位一周;
  - SD xpu 与 gpu 随机数生成不一致→多卡 loss 跳变;
  - 性能优化:FA 融合、FA lod tensor 去 h2d/d2h、FA_GEMM 走 fp16 / accu 保 fp32、xblas 默认 fp32→fp16、xblas handle 单例减少 xpu_wait(57→22)、swiglu 查表、rms_layernorm、caching allocator 接管 xdnn 内存;
  - bertlarge 卡 pytorch1.12 用不了 FA,dropout 算子极慢;
  - 分布式/megatron 最新优化策略反复验证、共享卡随机问题、坏卡定位。
- **他的管理/复盘视角**:想把模型支持沉淀成流水线(模型负责人 dump 算子列表→算子组按列表优化),但没推下去导致主分支频繁 break;工时复盘显示精度对齐(15%→71%→79%)和算子开发(44%)是大头,根因是硬件资源缺、基础软件不稳、缺 QA 看护。→ 说明他不只写 kernel,带过团队、做过交付复盘、懂工程管理短板。
- 子文档:运营商复盘 `c58b3193ac0848`、模型调优方法总结 `iunHNp2IkduziO`、模型支持FAQ `h6G_2gDw15SQON`、最终交付 `ApvgDFQP1ZUL2u`、个人模型进度更新 `aiI3auy86An4V9`、模型数据统计 `2gvJTqiHIRlylc`。

## 我(用户)署名负责的任务（来自 m300/Task 任务表 doc `cdOJVhODJXh9vg`）
- **T1.2 (PyTorch-1, P0)**：auto tune 调研 + inductor 相关测试拆解与修复。产出=auto tune 测试拆解清单 + 归因/修复。依赖 T1。
- **T4 (PyTorch-2/3, P0)**：推理算子——全部初步跑通 + 常用规模 + 精度严格对齐 + 性能分析。产出=推理算子通过率报告 + 性能报告。
  - 参考代码库：`dev.kunlunxin.com/klx/XTrainer/code/XTrainer/torchcompile-test/code`
  - **T4.4 / T4.5 已完成**（见下方 week5/week6 周报，2026-08-27 用户纠正：勿再当作待办）。任务表快照是旧的。
- 同表相邻协作者：罗丹(@)负责 T1.1 codegen、T8 训练算子；陈勇负责 T10(TF eager 业务模型摸底)。

## 我近期在改的文档（最近编辑，均在 XPyTorch 库）
- **M300最新周报** doc `wydOwr6_AcxdAd`：我在 Pytorch 基建栏——基于 xcuda13 初步对接 xtorch(部分子模块仍 cuda12 版本不可用)，xfa 对接中。
- **SFT/CPT最新周报** doc `losxYnBWVvpuiO`。
- **迁移仓库(icode→gittee)** 在线表格 doc `9e25c75bbc2247`。
- **m300/Task** doc `cdOJVhODJXh9vg`（总任务表）。
- **parts** doc `DHRElIyeWG3QR7`、**week6** doc `dZM0_yMMLfoR-r`（周报拆分）。

## 检索命令备忘
```bash
export SANDBOX_USERNAME=chenlonglong01
ku=/Users/chenlonglong01/.letta/skills/ku-doc-manage/bin/ku
$ku query-recent-doc --action recent-edit --page-size 20   # 我最近编辑的文档
$ku query-repo-dir --repo-id AI4AMs73rr --depth 1           # 库目录树
$ku query-content --doc-id <ID> --protocol markdown         # 读正文
```

## 重点方向与关键路径(2026-08-27 与用户梳理，当日晚间修正)
**修正：T4.4 基线、T4.5 性能分析已完成**——用户已产出 V4F 真实形状(DeepSeek-V4 Flash 推理规模)的完整性能报告，勿再当作待办。任务表 124/126 是旧快照。

### T4.4/T4.5 成果：V4F 形状 torch.compile 性能报告（week5 `TnYnsnVwe-le8C` / week6 `dZM0_yMMLfoR-r`）
- 覆盖 `.skills/shape_catalog.yaml` 的 `V4F-*` 档：16 算子 / 47 case / 54 triton kernel。
- **week5 = H100 PCIe 80G 基线**（torch2.9，roofline+ncu 双路互证）：真实形状下 triton kernel 已把 HBM 打满(达成率 92%，ncu DRAM 91.6%)，大部分算子无优化空间、可作 XPU 验收基线。两个真问题：`compiled_random_sample` 并行度崩塌(37~42ms vs 理论 2µs，reduction 切分只用 256 线程)；`per_block_cast_to_fp8` 达成率<1%(访存非合并，需重写 bytes())。bf16 掉带宽定位到 `_swiglu_gpt_oss_sigmoid_alpha`/`swiglu_limit_func` 两条 codegen(向量化宽度)，非通病。
- **week6 = KUNLUN5 模拟器 vs H100 对比**（KL5 走本地 Jupiter/KUNLUN5 cycle 级模拟器，无真卡）：KL5 峰值带宽 2.8×H100，但工作集>L3(48MB)的 6 个 case 实测只 0.70~1.66×；fp32 打平或略胜，**bf16 系统性劣化**(norm 家族 1.49~1.81×，elementwise 1.05~1.20×)。根因核到 inductor 源码：`triton.codegen_upcast_to_fp32=True` 让 bf16 kernel 载入即上转 fp32、全程 fp32 算、存回前下转，指令数≥fp32 而字节减半，KL5 指令预算下必更差；H100 靠 5.5× 每字节指令预算吃下。反向：小 kernel/低并行 case KL5 更快(fp8 快 14~18×)。
- 报告口径严谨：week6 经独立审阅修订三处口径错误；MP 模式在 bf16 上比 CYCLE 低估 31%，norm 家族已全改 CYCLE 重测。原始数据 `v4f_*.csv`、脚本 `run_v4f_sim.py`/`make_v4f_compare.py`。

### 仍在推进
- T1.2 auto tune 调研 + inductor 测试拆解修复(P0)，与上面性能线强相关。**调研部分基本完成**(见下)。
- xcuda13 对接 xtorch(长期基建，部分子模块仍 cuda12 不可用，xfa 对接中)。

### T1.2 调研成果:inductor 深度调研(基本完成，2026-08-27 用户确认)
- 载体 doc `oldIOCe_6OLX25`("torchcompile"，本身空壳)下两棵子树:
  - **inductor调研 `H1PSlJSteSJr-G`(13篇)**:把 torch.compile 全流水线逐层拆透——pipeline overview / tracing / dynamo / functionalization / aot_autograd_backward / inductor lowering / compile scenarios / decompose·lowering·fallback / dynamic shapes / **10_codegen·autotune `CFdP1yrNqHcSHd`** / 11_codegen / cudagraph。
  - **开发记录 `A0tB_jckObhVzI`(3篇)**:megatron.jit_fuser `_6C1-Wz4wa9GcY`、小模型调度 cluster/sdn `KN_TUmMs1PF5sE`、m300/inductor支持 `PFJ0WXudJW3EFe`。
- **关键成果(10_codegen/autotune)**:定位并修复 KUNLUN5 模拟器上大 shape 测试"卡住"的真 bug——模拟器上 `torch.cuda.Event.elapsed_time()` 恒返回 0.000000ms,使 inductor benchmark 协议退化成每候选 config 跑 106 次全量 kernel 且计时全 0(单 kernel 5.7min ×4候选×106次 ≈40h、产出为零,选中 config 等于取列表第一个)。破除误解:与 `TRITON_DISABLE_AUTOTUNE` 无关(那只管 triton 自己的 Autotuner,inductor 生成 kernel 走自抄实现读不到)。已在 `sitecustomize` 打补丁。
