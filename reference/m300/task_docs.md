---
description: M300 torch.compile 兼容性工作的权威任务文档索引(本机 /Users/chenlonglong01/workspace/zhixing-work/torch_feature/):93 个 feature 的总盘子、按子系统拆分的 parts/、feature→test 映射、AUDIT 与测试分类。夜间战役的每一片都要能对回这里的某个 feature。
---

# 任务文档:M300 torch.compile feature 总盘子

**位置(本机)**:`/Users/chenlonglong01/workspace/zhixing-work/torch_feature/`
(另有 `torch_feature.zip` 备份;容器内代码树是 `/workspace/m300/torch_feature/xTorch`,
**同名但那是代码,这里是文档**,别混。)

用户自己在本地整理定稿的版本,**以它为准**,不是我或远端 agent 的整理稿。

## 文件与用途

| 文件 | 大小 | 什么时候读 |
|---|---|---|
| `feature.md` | 11K | **总盘子**。15 个子系统 → **93 个 feature**,带优先级和 owner |
| `parts/01..07_*.md` | 7 份 | 按子系统展开的细节(dynamo/aot/codegen/**autotune**/cache/customop/debug) |
| `feature_test_mapping.md` | 11K | feature → 测试文件的映射,分片时查这个 |
| `test_type_classification.md` | 31K | 测试类型分类 |
| `AUDIT.md` | 47K | 对整理稿本身的复核(复现性缺陷记在这里) |

基线 **PyTorch 2.13**(2026-07-08 GA)。口径:一级=子系统,二级=可独立摸底与验收的能力项。

## 用户自己的那一格

`feature.md` 里 owner 标 **[@陈龙龙]** 的是 **Autotuning(优先级 p0,6 个 feature)**:
max-autotune 模式与 gemm backends / triton_heuristics 运行期 config / async pipelined autotuning /
分析式模型剪枝(nvMatmulHeuristics、Origami)/ **multi-kernel 与运行期变体选择** /
Custom op autotune。
(相邻的 `Inductor codegen` P0 9 个 feature owner 是 [@罗丹],不是我们这条线。)

夜间战役当前跑的就是这一格。`parts/04_backend_autotune.md` 是它的展开。

## 定位关系(别丢了尺度感)

```
93 个 feature(总盘子,feature.md)
  └─ Autotuning 6 个 feature(用户 owner 的那格,p0)
       └─ multi-kernel 与运行期变体选择(其中 1 个)
            └─ test_multi_kernel.py(1 个测试文件,19 例,基线 13/4/2)
```
**上游全量单测分母 DENOM=4959**,与 feature 数是两个不同口径,不要互相换算。

⚠️ **不许抄文档里的用例数**:`count_tests.py` 在仓库里不存在(AUDIT 已标为复现性缺陷),
子特性用例数逐行相加会重复计数(子特性共享测试文件)。分母一律现场
`--collect-only` 取证,详见 [[skills/overnight-test-campaign/phase-p0-p1.md]]。

## 相关
- 硬件规格:[[reference/m300/hw_spec.md]]
- 已确认的兼容性缺口:[[reference/m300/cuda_compat_gaps.md]]
- 夜间战役流程:[[skills/overnight-test-campaign/SKILL.md]]
