---
description: 夜间测试战役 P3 无人值守铺开前必须先解决的未决卡点(阻塞清单;解决一条就从这里移除并把结论写进对应参考文件)
---

# P3 铺开前的未决卡点

**这些没解决,就不许安排无人值守的夜间铺开。** 每条都是实证踩出来的,不是假想风险。
解决一条 → 把结论写进对应文件 → 从本清单删掉。

## 1. relay 指纹跨零点失效(2026-08-30 实证)

relay 指纹**按天失效**。2026-08-30 01:46 的 P1 基线就断在这:
`Connection timed out during banner exchange`,16 个文件全部 `UNAVAILABLE`。
**夜间窗口(23:00→06:00)必然跨零点**,所以这是必然事件,不是偶发。

候选出路(**均未验证**):①零点后再启动;②睡前手动解锁一次,验证新指纹能否覆盖整夜;
③查 relay 有无长效凭据。

## 2. relay 并发上限 vs 池子规模(2026-08-30)

2026-08-28 实测 **4 路并行**时本机堆约 80 个 relay 长连接、5 台出现
`Connection timed out during banner exchange`。瓶颈在**本机→relay 网关**这一跳,
**与远端机器数量无关**。

⚠️ **但这条不阻塞第一晚。** 第一晚每实例只派一个测试、机器数很少,
2 路够用。**不许因为这条去提前造复杂方案** —— 等真要加倍到并发吃紧时再解决。

候选出路(**均未验证**):①下发即断(`nohup` 起远端脚本后断开,agent 只在轮询状态时才连);
②状态经文件/网盘回收,不靠 ssh 长连接读 stdout;③首批错开首连认证。

## 3. ~~`test_multi_kernel.py` pass 数两次不一致~~ **已解决(2026-08-30 晚)**

真值:**13 passed / 4 failed / 2 skipped**(19 总),两次完整配方运行**逐用例完全一致**,
`MK_STABLE=yes`。

**成因不是缓存、不是 collect 漂移、不是 skip 漂移 —— 是启动环境不完整。**
`4 passed` 那次缺 `PYTHONPATH=.`,导致 `sitecustomize` 没被加载
(同时缺 `TC_PLATFORM` / `TRITON_ENABLE_XCN_BACKEND`,M300 bridge/backend 整个没接上)。
**教训:环境不闭环时,失败会伪装成"测试本身红",而不是报环境错。** 所以配方必须逐字照抄,
少一项都不行。

唯一正确命令(逐字照抄,少一项就不是这个结果):
```bash
cd /workspace/multinode-20260829/p1-triton && \
TC_PLATFORM=xpu TRITON_ENABLE_XCN_BACKEND=true TORCHINDUCTOR_COMPILE_THREADS=1 \
LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/local/xcuda/targets/x86_64-linux/lib/" \
PYTHONPATH=. python -m pytest xTorch/test/inductor/test_multi_kernel.py -q
```

**4 个 fail 有清晰规律 —— 全部是 `cpp_wrapper` 变体**(两次一致):
`test_softmax_cpp_wrapper`、`test_reduction_scratch_buffer_cpp_wrapper`、
`+_non_persistent_reduction`、`+_persistent_reduction`。
对应的非 cpp_wrapper 版本(`test_softmax`、`test_reduction_scratch_buffer`)**全绿**。
→ 指向一个**真实且成片的兼容性缺口:inductor 的 cpp_wrapper 代码路径**。
这正是大目标要的产出(见 SKILL.md 开头):不是环境噪声,是该记进缺口清单的东西。

**2 个 skip 是合法的**:`templates require big gpu`(test 文件 111/140 行)——
上游自身的能力门禁,不是我们误 skip。✅ 符合"skip 必须有正当理由"的要求。

⚠️ 遗留:`4 passed` 那次的具体命令没有留档,所以"到底哪一项缺失贡献了多少"只能靠推断。
**这就是为什么每条远端命令都必须留原文** —— 事后无法重建的现场,只能重跑。

