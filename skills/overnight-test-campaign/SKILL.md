---
name: overnight-test-campaign
description: Use for auditable overnight PyTorch M300/XPU test campaigns with HTTP workers, strict environment gates, sharding, and handback collection.
---

# Overnight Test Campaign

## Current State

| Scope | Evidence | Boundary |
|---|---|---|
| node41 `10.206.192.139:8320` | Host HTTP gateway, controlled `docker exec` into existing `chenlonglong01_m300_py312_torch212`; `env_check` passed, `test_best_config.py` 1 passed, restart persistence and admin `pending_review` verified | One verified path, not a fleet guarantee |
| node41 `:8111` | Independent container direct HTTP verified | Example only |
| Other nodes/ports | Unverified | Must pass gates independently |
| KU ready | Image/documentation readiness only | Does not mean worker ready |

## Next-Step Gates

Use one parameterized `/Users/chenlonglong01/workspace/zhixing-work/init-http-worker.sh`; per machine inject parameters, never generate a new script.

1. Check Docker/container ownership, writable directory, and port. Refuse occupied ports; bridge is the default network. Host networking is an explicit exception only when the real XPU/egress contract requires it.
2. Start or attach an HTTP worker. Existing non-owned containers are only inspected and used through a safe exec entrypoint; never stop, delete, replace, or pretend the host is the execution container.
3. Run server-defined `env_check`.
4. Run the reviewed, evidence-backed minimal Triton/Inductor pytest node-id. A file-level success is not a node-id; when evidence lacks a node-id, require `--smoke-selector` and stop by default.
5. Check `/health`, then register the worker. A failed gate is not ready.

HTTP direct connection is preferred. SSH may do one bootstrap/start action only; do not default to a tunnel. Port reachability is a site fact to verify, not a rule inferred from another node.

## Non-Negotiable Rules

- Host writes stay inside the caller-owned work directory. Never clean shared disks, modify routes/firewalls, or install packages.
- Every worker has an ownership marker. Only a matching marker may authorize later lifecycle operations.
- Tokens are generated at runtime, stored mode 0600, and redacted from handback.
- The server owns Python, conda, cwd, source, bridge, environment, cache, log, and result paths. Ordinary `POST /jobs` accepts only `job_type`, `target`, `selectors`, `timeout_seconds`, and `request_id`; `argv`, `env`, `cwd`, and `python` are rejected.
- Verified contract: conda `python312_torch212`; Python `/root/miniconda/envs/python312_torch212/bin/python`; cwd `/workspace/m0-denominator-final`; source `/workspace/torchcompile/pytorch`; `TC_PLATFORM=xpu`; `TRITON_ENABLE_XCN_BACKEND=true`; `TORCHINDUCTOR_COMPILE_THREADS=1`; LD append `/usr/local/xcuda/targets/x86_64-linux/lib/`; bridge PYTHONPATH `/workspace/m0-denominator-final/triage-triton`; CUDA spelling `cuda:0`; per-job cache under `http-cache/<job_id>`.
- `POST /admin/commands` accepts arbitrary shell text only as an auditable `pending_review` record. It never executes. A separate admin token, digest match, explicit approve, audit record, and expiry are required for the designed approve endpoint; approval still records `approved_not_executed`. A worker token cannot approve.
- Make `GET /health`, `GET /jobs/<id>`, `GET /admin/commands/<id>`, log/handback paths, persisted job metadata, and dynamic-port registration explicit in reports.
- Ordinary jobs are fixed test operations. `job_init`/admin shell is review-only control plane, never a shortcut around environment gates.

## Routing

| Need | Read |
|---|---|
| Bootstrap and protocol | `init-http-worker.sh`, `remote-http-workspace/server.py`, `remote-http-workspace/runner.py` |
| P0/P1 gates and smoke | `phase-p0-p1.md` |
| HTTP channels and direct-connect evidence | `channels.md` |
| Ownership and write boundaries | `boundaries.md` |
| Sharding only after worker readiness | `sharding.md` |
| Failure taxonomy and blockers | `blockers.md`, `pitfalls.md` |
| Machine-specific examples | `machines.md` |
| Handback schema | `HANDBACK-schema.md` |

Keep verified facts separate from hypotheses. Record node, port, container, selector, status, rc, elapsed time, persisted paths, and failure class. Never generalize node41 success to another machine without its own evidence.
