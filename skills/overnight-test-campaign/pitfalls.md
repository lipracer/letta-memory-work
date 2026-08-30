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
