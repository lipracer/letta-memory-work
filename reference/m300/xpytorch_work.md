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
  - T4.3 现状：推理算子 **124/126**（未通过 2 个为非常见规模），需基于常用规模复测。
  - T4.5：性能优化路径待定——inductor tune 改 torch 配置 vs 调整 hw layout 逻辑。
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

## 重点方向与关键路径(2026-08-27 与用户梳理)
用户 P0 任务是一条链:**T1.2(auto tune 认知) → T4.3(常用规模复测) → T4.4(GPU 基线) → T4.5(拍板优化路径)**。
- **T4.3 常用规模复测 = 当前最紧堵点**:现 124/126 通过率建立在"非常见规模"上,须按常用规模重算,否则挡住 T4.4/T4.5。T4.1 参考文档=M300 推理 P99 Triton 算子统计、glm 5.2 vllm 算子清单(在知识库)。
- **T4.5 / T8.5 优化路径未决**:两处同一岔路——inductor tune 改 torch 配置 vs 调 hw layout 逻辑。需用户拍板,建议等 T4.4 实测差距出来再定。
- T1.2 auto tune 与 T4 强相关,可并道走。xcuda13 对接 xtorch 是长期基建项(部分子模块仍 cuda12 不可用,xfa 对接中)。
