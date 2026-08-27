---
description: chenlonglong01(@陈龙龙) 在 XPyTorch/M300 知识库中负责的工作与关键文档索引
---
# XPyTorch / M300 工作索引（chenlonglong01 = @陈龙龙）

数据来源：如流知识库 XPyTorch 库，2026-08-27 用 ku-doc-manage 检索。
- 知识库根：`https://ku.baidu-int.com/knowledge/HFVrC7hq1Q/BeQck0ZK7s/AI4AMs73rr`
- repo-id = `AI4AMs73rr`，space=HFVrC7hq1Q，group=BeQck0ZK7s(XPyTorch)

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
- T1.2 auto tune 调研 + inductor 测试拆解修复(P0)，与上面性能线强相关。
- xcuda13 对接 xtorch(长期基建，部分子模块仍 cuda12 不可用，xfa 对接中)。
