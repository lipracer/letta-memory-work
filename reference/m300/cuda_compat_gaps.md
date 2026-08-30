---
description: M300 CUDA-compat PyTorch 测试战役的兼容性缺口清单与已核实基线(cpp_wrapper 代码路径缺口、test_multi_kernel 真值 13/4/2);夜间战役的长期产出,写报告或判断新增 fail 时读
---
# M300 CUDA 兼容性缺口清单

夜间测试战役(`skills/overnight-test-campaign/`)的**长期产出**:一张持续演进的缺口清单,
不是一次性绿灯。判读口径见该 skill 开头(skip 比 fail 危险;分母按上游全量算)。

只记**已核实**的条目。每条要有:命令能重跑、失败形态、以及为什么这不是环境噪声的证据。

## 已核实基线

| 测试文件 | 真值 | 核实方式 |
|---|---|---|
| `test/inductor/test_multi_kernel.py` | **13 passed / 4 failed / 2 skipped**(19 总) | 2026-08-30 两次完整配方运行,**逐用例完全一致** |

完整环境配方(逐字照抄,少一项就拿不到这个结果)见
`skills/remote-exec-baidu/SKILL.md` 的「M300 跑 test/inductor」一节。
关键:`PYTHONPATH=.`(装载 `sitecustomize` target bridge)+ `TRITON_ENABLE_XCN_BACKEND=true`
+ `TC_PLATFORM=xpu`。

2 个 skip 是**合法的**:`templates require big gpu` —— 上游自身的能力门禁,不是我们误 skip。

## 缺口 1:inductor `cpp_wrapper` 代码路径(2026-08-30 首次成片确认)

`test_multi_kernel.py` 的 4 个 fail **全部是 `cpp_wrapper` 变体**,两次运行一致:

- `test_softmax_cpp_wrapper`
- `test_reduction_scratch_buffer_cpp_wrapper`
- 同名 `+_non_persistent_reduction` / `+_persistent_reduction`

**对照证据(这是它不是噪声的理由)**:对应的非 `cpp_wrapper` 版本
(`test_softmax`、`test_reduction_scratch_buffer`)**全绿**。唯一变量就是 cpp_wrapper 路径。

→ 判读:这是**真实的兼容性缺口**,属于该记进清单的产出。
→ 后续价值:凡是带 `cpp_wrapper` 的用例都应预期同类失败;铺开后如果出现
**非** cpp_wrapper 的新 fail,那才是新信息,优先级更高。
→ 未做:根因(生成的 C++ wrapper 走到哪一步坏的)未定位,只有现象级规律。
