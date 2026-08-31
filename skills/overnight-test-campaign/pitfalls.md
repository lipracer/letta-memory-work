---
description: 夜间测试战役踩过的常见坑与规避方式(overnight-test-campaign 参考文件)
---

## 常见坑

- **工作目录建在 home/根分区** —— 最常见的自毁方式。必须落 `/ssd<N>/$(id -un)`,
  容器内统一映射成 `/workspace`。选盘要看 P0 的 `df -h`,别抄别的机器的盘号。
- **越界写** —— 宿主机除 `docker pull/run/exec` 和建自己的工作目录外禁止写;
  容器内只许写 `/workspace`,`/klxlake` 和别人的目录**禁写**。详见上文写权限边界。
- **"盘满就顺手清一下"** —— 绝对不许。共享机上删的可能是别人的训练产物。换机器。
- **用户名写死** —— 路径里用 `$(id -un)`,别硬编码某个账号名。
- **新容器没跑初始化就 clone** —— 没有 ssh key,`ssh://git@icode.baidu.com:8235/...` 直接失败。
  先跑 P1 第 3 步。
- **凭据不落盘** —— 初始化用的 BOS AK/SK 在 KU 文档明文里,现场读、用完不写进任何文件、
  不进日志、不进 subagent 的 prompt。
- **没 activate 就跑 python** —— 容器 PATH 上是 miniconda base(3.13,无 torch)。
  进容器**第一件事** `source /root/miniconda/etc/profile.d/conda.sh && conda activate python312_torch212`。
  且 `docker exec bash -lc` **每条都是新 shell,activate 不跨命令保留** —— 每条都要带,
  或 `source` 工作目录里的 `env.sh`。这条不做,整夜任务会在第一跳全片 `ModuleNotFoundError`。
  2026-08-29 双 agent 独立踩到同一处。
- **用 `torch.xpu.*` 接口** —— **M300 软件栈兼容 CUDA,一律按 CUDA 写法用**:
  `torch.cuda.is_available()` / `device="cuda"` / `.cuda()` / `TestCommonCUDA`。
  实测 `torch.xpu.is_available()` = False 而 `torch.cuda.is_available()` = True,
  拿前者当 device 门禁会让用例**全部误 skip**,早上看到一片假绿。好处是上游 CUDA 测试可原样复用。
- **自己调模拟器环境变量** —— 镜像已把那一堆 `XPUSIM_*` / `CUDA_AMODEL_*` 配成自洽默认值,
  **开箱就能跑通,一个都别改**(它们互相耦合,动一个就可能整套失配)。
  唯一该主动设的是 `XPUSIM_LAUNCH_LOG_LEVEL=DISABLE`。要换档位按 `machines.md` 的成对配方改。
- **把模拟器析构日志当报错** —— pytest 结束后 stderr 打印 `Kl5Top destructed` /
  `XpuSystem destructed`,设了 `XPUSIM_LAUNCH_LOG_LEVEL=DISABLE` 也照打,退出码不受影响。
- **here-doc 写脚本** —— 引号转义反复出错。可靠做法:本机生成 → `base64 -i`(macOS **不支持
  `-w0`**)→ 容器内 `base64 -d` 落盘 → 双端 `md5sum` 比对。2026-08-29 实测一次成功。
- **别指望容器内 agent** —— 容器里起不了 ducx/baidu-codex。二进制**确实存在**于
  `/root/.comate/.baidu-cx/*/bin/` 但不在 PATH(2026-08-29 实测 `which` rc=1),
  **不要因为文件在那儿就去启动它**。执行主体是本机 subagent,经 `ssh` + `docker exec` 下发。
- **subagent 派发失败 ≠ 任务失败** —— 症状:`exited with code null`、0 次工具调用、1~2 秒就结束。
  这是**进程创建阶段**就没起来,不是它在远端出错。2026-08-29 同时并发派两个长 prompt 时复现过一次。
  处理:把 prompt 收短(尤其去掉大段 markdown 代码块模板,改成一行字段清单),重试一次;
  同一格式不要反复硬试。模板类内容放进 runbook 文件让它自己读,prompt 只留指路。
- **交付要摊开给用户看** —— handback 写进磁盘不等于交付。回复里要把
  ip / hostname / 容器名 / 工作目录 / 命令数 / pass-fail / 日志 md5 做成一张对照表贴出来,
  文件路径只是补充。2026-08-29 有过"报告早就在盘上、但用户等于没拿到"的先例。
- **确认命令真的落在容器里** —— 2026-08-25 有过本地 subagent 被误当成容器 agent、结果作废的先例。
  用 `docker exec <容器> hostname` 之类的自证命令确认落点。
- **不要内联长脚本** —— here-doc / 引号转义反复炸(`zsh: parse error`)。
  写到容器内临时文件再执行。
- **`du` 在满盘机器上很慢** —— 限制 `-x -h -d 1`,超 30s 就跳过只留 `df`。
- **交叉复核** —— 重要结果让第二个只读 agent 独立重算一遍,不给它看第一份结果,
  只报告一致性和分歧点。


## 哨兵撞上旧产物 → 假报完成(2026-08-30 真踩过)

复用同一个目录派发时,Monitor 只判"文件存在",撞上**上一轮残留的 handback**,
**39ms 就报完成** —— 而本轮什么都还没跑。

**根治方式不是加强判据,是隔离路径**:一次派发一个新的 `runs/<时间戳>-<机器>-<任务>/`。
目录是新建的 ⟹ 文件存在 ⟺ 本轮产物。改名 `*.STALE-*` 那套 hack 已废弃。
布局见 `HANDBACK-schema.md`。

### 哨兵自身还有两种失效方式(2026-08-30 实测)

- **Monitor 的 `timeout` 参数不生效** —— 传 `timeout: 900000` 或 `3600000`,回执照样是
  `timeout 300000ms`,**5 分钟就断**。夜间任务的哨兵一律用 **`persistent: true`**
  (正确回执长这样:`persistent — runs until TaskStop or session end`),
  否则派出去的活跑到一半就没人看着了。
- **只盯"成功"会漏掉"根本没起来"** —— 哨兵至少要覆盖三种结局:
  ① `handback.md` 出现 = 完成;② `NEEDS_DECISION.md` 出现 = 求助;
  ③ **执行者进程已消失、两个文件都没有 = 派发失败**。
  **静默不等于在跑**:ducx 在 ssh 阶段就死过,而只盯成功文件的哨兵完全无感。


## 环境不闭环会伪装成"测试红",而不是报环境错(2026-08-30 实证)

`test_multi_kernel.py` 同文件同容器,两次 `4 passed` vs `13 passed`。
成因:少了 `PYTHONPATH=.` → `sitecustomize` 未加载 → M300 bridge/backend 没接上。
**pytest 不会告诉你"环境没接上",它只会把用例判红。**

推论(适用于整套战役):
- **配方必须逐字照抄,少一项都不行**;不要"看起来差不多就行"。
- 看到大面积 fail,**先怀疑环境不闭环,再怀疑代码**。
- 每个 agent 在正式跑之前应**自证环境已闭环**(不只是 `import torch` 成功),
  并把自证输出写进 handback —— 否则一晚的红都无法判读。
- **每条远端命令必须留原文**。`4 passed` 那次没留档,导致"哪一项缺失贡献了多少"永远无法重建,
  只能重跑。这就是留档要求的实际代价来源。

## fail 有规律时,那是缺口不是噪声(2026-08-30 实证)

`test_multi_kernel.py` 稳定 4 fail,**全部是 `cpp_wrapper` 变体**,
对应的非 cpp_wrapper 版本全绿。这种"沿某个特性维度成片红"的形态,
是**真实兼容性缺口**的signature,应直接记进缺口清单并上报,不要当抖动重跑掩盖。

反之,**同一用例时红时绿**才是抖动,那时才去查缓存/并发/环境。
判据:**先确认稳定性(至少两次逐用例一致),再解读红的含义。**


## 基准测试混入撞天花板的样本 → 数字整个废掉(2026-08-30 真踩过)

测"2 进程并行省多少时间",选了 `test_multi_kernel.py`(约200s)+ `test_combo_kernels.py`。
后者**两轮都撞 1800s timeout**,于是串行 2055s / 并行 1810s —— **两个数字测的都是 timeout 上限**,
算出的 1.135x speedup 毫无意义。安全性结论有效(逐用例对照仍成立),但**性能结论作废**。

规则:**做墙钟对比之前,先确认每个样本都能在时限内跑完。**
`--collect-only` 只能证明它能被收集,**不能证明它能跑完** —— 那是两件事。
先单跑一遍拿到真实耗时,再拿它做基准。

## 别按"一进程一核"估算并行度(2026-08-30 实测)

即使设了 `TORCHINDUCTOR_COMPILE_THREADS=1`,单个 pytest 进程实测仍吃 **8~32 核** ——
**功能模拟器本身是多线程的**,那个 env 拦不住它。
按"一进程一核"排并行度会严重高估机器能承载的路数,直接导致抢爆共享机器。
**并行度必须按实测的每进程核数算**,不是按进程数算。


## 模拟器 CUDA event 返回 0 → autotune benchmark 迭代数不收缩(2026-08-31 取证)

**这是全局性能问题,不是某个文件的问题。凡是重度依赖 autotune benchmark 的测试都受影响。**

链路(已实测取证):
1. 镜像默认 `XPUSIM_SIMULATOR_MODE=FUNCTION`(功能模拟器,非真硬件);
2. CUDA event 计时拿到 **`ELAPSED_MS=0.0`**(实测打印两个 event 均为 0);
3. inductor 默认走 **experimental benchmarker**,该路径**只在 `estimated_timing > 0` 时才收缩
   `benchmark_iters`**(`xTorch/torch/_inductor/runtime/benchmarking.py:501-505`),
   否则**保持 100 次迭代**;
4. → 每个 autotune 候选都被跑 100 遍,整体被放大约两个数量级。

**规避开关(上游已有逻辑,默认没走它)**:
```bash
TORCHINDUCTOR_USE_EXPERIMENTAL_BENCHMARKER=0   # 切到 TritonBenchmarker
```
依据:`xTorch/torch/_inductor/config.py:483-490`、`runtime/benchmarking.py:19-21,547-548`;
Triton 的 `do_bench` 有 `estimate_ms = max(estimate_ms, 1e-3)` 下钳
(`site-packages/triton/testing.py`),因此不会由 0 推出巨大重复次数。
**默认值是 True(走 experimental),即默认踩坑** —— 必须显式设 0。

⚠️ **未测项:开关对整文件墙钟的实际收益。** 复测只验了单用例(30~31s,通过),
整文件那次只给了 339s 预算故仍 rc=124 —— **不能据此说开关无效**。
下一步该做的是:带开关给整文件 ≥3000s 预算跑一次,和 2656s 基线对比。

**教训**:功能模拟器不是"慢一点的真卡",它会让**依赖真实计时的上游启发式整体失效**。
遇到"模拟器上某类测试异常慢",先怀疑计时返回 0,而不是先怀疑测试本身。
