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
**三层分母，不得互相换算**：整个 PyTorch（**团队的**）⊃ torch.compile/inductor 全量（**我们的天花板**）
⊃ Autotuning 6 个 feature（当前战场）。feature 数与用例数也是两个口径。
⚠️ 旧记的 `DENOM=4959` 出处未留证（既不知哪些文件，也不知哪个环境），**别直接用**。

⚠️ **不许抄文档里的用例数**:`count_tests.py` 在仓库里不存在(AUDIT 已标为复现性缺陷),
子特性用例数逐行相加会重复计数(子特性共享测试文件)。分母一律现场
`--collect-only` 取证,详见 [[skills/overnight-test-campaign/phase-p0-p1.md]]。

⚠️ **顶层汇总表(含"合计 7272")现在不可引用**:15 个分类里只有 3 个数字与明细卷对得上,
最大偏差是分布式分类 396 vs 501,而 part 06 自己写明 396 是它正在纠正的旧数。
引用前必须按明细卷重算。

## AST 静态计数 ≠ 分母(2026-08-31 定,这是 M0 的核心区分)

`torch_feature/` 的用例数是 **AST 口径**:源码里名为 `test_*` 的方法数,
`instantiate_device_type_tests` / `@parametrize` / `copy_tests` / `make_test_cls_with_patches`
的**展开倍数不计入**(文档自己也这么声明)。

M0 要的分母是**在最终跑测试的那个环境里 `--collect-only` 收到的实际用例数**。
两者差的不是误差,是数量级(一展开就乘设备数 × dtype 数);而且 collect 数**随环境变**
(同批 16 个 inductor 文件装 Triton 前后 1997→2994)。

→ **两个数都要,并列成两栏**,差值本身就是信息(展开倍数)。
→ 因此 `torch_feature/` 的定位是 **feature 拆解清单**(方向 1 的关键产出、M1 分批的骨架:
  93 个 feature 就是天然批次单位),**不是分母**。分母只能在容器里 collect 出来。

## 相关
- 硬件规格:[[reference/m300/hw_spec.md]]
- 已确认的兼容性缺口:[[reference/m300/cuda_compat_gaps.md]]
- 夜间战役流程:[[skills/overnight-test-campaign/SKILL.md]]

## 研发计划正文（KB）

《研发计划：AI 编译器全链路适配与使能》 `n4sA1lj34OAgW-`
（团队库 XPyTorch `AI4AMs73rr`，group `BeQck0ZK7s`，用户 2026-08-17 起草 v0.2）
—— 8 条方向（PyTorch 5 + TF 3）、M1~M4 里程碑、依赖图。
这是**比 feature.md 更上层**的文档：feature.md 只管 torch.compile，
这份还包含推理/训练算子、TF eager/XLA、分布式通信。

我提的 v0.3 修订在本机 `/Users/chenlonglong01/workspace/zhixing-work/PLAN-v0.3.md`，
核心改动（用户尚未拍板）：① 新增 **M0 取证期**（分母/业务模型清单/常见规模）；
② 结束标准从"通过率/测试清零"改成 **`pending`=0 四分类归因**（通过率会奖励 skip）；
③ 拆掉 v0.2 把方向 1→·2 串行的错（基建线与业务线应并行）；
④ 验收三级 **功能 → 精度 → 性能**（用户 2026-08-31 定），精度标准见 [[reference/m300/precision_criteria.md]]。
（已作废：我曾说“功能模拟器无时间信息→性能线阵亡”—— event 返 0 用户说已修，不要再引用。）

**v0.3 已上 KB（2026-08-31）**：`RXckLFp0zlb1SH`
《研发计划：AI 编译器全链路适配与使能（v0.3 草案·验收标准细化）》
—— 作为 v0.2 (`n4sA1lj34OAgW-`) 的**子文档**新建，未覆盖原稿。
本地源文件 `/Users/chenlonglong01/workspace/zhixing-work/PLAN-v0.3.md`。
v0.3 相对 v0.2 四处实质改动：① 新增 M0 取证期；② 结束标准改为 `pending`=0 七分类归因；
③ 拆掉 (1)→(2) 串行错误；④ 新增**精度验收标准**整节（见 [[reference/m300/precision_criteria.md]]）。
后续同一篇被**覆盖重写**成"里程碑先行"结构（用户挪过它的位置，覆盖时位置未动）：
新增 skip 三分类、精度归因并入 M1、人机分工节。

**写 KB 长文档的可用命令**（已实测）：
`ku create-doc -repo-id <repo> -parent-doc-id <父> -title <标题> -md-file <本地md> -username chenlonglong01`
—— 直接传本地 markdown 文件，不用拼 `-content` 字符串；表格/代码块保留完整。
验证用 `ku query-content -doc-id <guid>` 回读关键字。

**改已发布文档要走两步，缺一不可**：`edit-mdsl-content`（mode=cover 全文覆盖 / append / insert_*）
**只存编辑态**，必须紧接 `publish-doc` 才对读者生效；**未发布视为任务未完成**。
改完要回读校验：发布是否生效、占位符有没有残留。
用户挪过文档位置时，**覆盖同一篇 guid**，不要删了重建 —— 重建会丢掉他挪好的位置。

## M0→M4 里程碑与结束标准（v0.3，2026-08-31）

用户要求**结论先行：里程碑放最前面**。文档结构 = 里程碑 → 口径声明 → 当前状态与取证缺口
→ 方向与依赖图 → 验收标准 → 精度验收标准 → 这份文档给谁看（人机分工）→ 风险 → 待细化。

| 里程碑 | 内容 | 结束标准 |
|---|---|---|
| **M0 取证期** | ①文件清单 + 逐文件用例数（AST 与 collect **两栏**）+ 环境指纹，**一条命令可重现** ②业务模型清单 ③常见规模定义 ④精度对照开关清单（tf32 / fast-math / 累加精度，两侧都取） | 四项齐备 |
| **M1** | 按 feature 分批跑通，**精度归因随手做**（不是独立阶段） | 每批 `pending`=0 才放下一批 |
| **M2** | 只补上游根本不做的两件事：**dtype 矩阵补全** + **bit-exact 断言 harness** | —— |
| M3 / M4 | 见 KB 正文 | —— |

- 结束标准是 **`pending`=0 的七分类归因，不是通过率** —— 通过率会奖励 skip。
- ②③**必须用户给输入**（业务模型是哪几个、常见规模按什么定）；①④是纯取证，不需要他在场。
- 用户曾提"先全部跑通，再抽算子测试按精度搞，再看性能"。**精度不能拆成独立阶段**，
  理由见 [[reference/m300/precision_criteria.md]]。
- **归因是瓶颈，不是机时** —— 已作为独立风险项写进计划，M1 强制分批。
- M0 当前唯一还卡人的一项是 **④精度对照基准**（GPU 型号 + torch 版本 + 开关清单）。

## 人机分工：谁验收什么（v0.3 第七节，已定）

| 机器判 | 人签 |
|---|---|
| `pending` 数、新增 fail、skip 按类的变化 | ①豁免是否成立 ②修复优先级 ③精度对照基准 ④feature 收尾 |

**硬判据：验收需要人读日志，就说明分类器没做完。**
