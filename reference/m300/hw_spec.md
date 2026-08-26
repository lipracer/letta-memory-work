---
description: M300 hardware specification summary for future reference.
---
---
description: M300 hardware specification summary for future reference.
---

# M300 hardware spec

Source: `/workspace/m300/perf_sim_result/hw_spec.md`

## Overview
- M300 AI compute units:
  - XPU-Cluster: general-purpose compute unit for scalar/vector work.
  - XPU-SDNN: tensor unit for convolution and matrix multiplication acceleration.
- Memory system:
  - Global Memory and memory controller
  - System-level Last Level Cache
- Interconnect:
  - XPU Link for chip-to-chip communication
  - PCIe 5.0 x16 for host-device communication

## Cluster architecture
- SOC layer cluster count: 32 on M300
- PU count per cluster: 2 on M300
- Core count per PU: 4
- Threads/warp: 32
- Max warps/SM: 64/PU
- Max threads/SM: 2048/PU
- Max thread blocks/SM: 32/PU
- Shared memory size/SM: 64KB
- GM size: 216G
- L3 size: 48M

## Hardware features
- Mixed 32/64-bit instruction support
- Data types: u32/i32, fp32, fp16, u16/i16, u64/i64, fp64, bfp16, fp8(e4m3/e5m2), fp6(e3m2/e2m3), fp4(e2m1), e8m0
- i8/u8 storage with int32 computation conversion
- Atomic instructions based on global memory/shared memory


## Torch feature docs
- `torch_feature/` 这组文档（含 `feature.md`、`parts/` 等）是用户此前委托远端 Claude 整理、后来由用户自己在本地完成整理的版本；后续以用户本地整理稿为准。
