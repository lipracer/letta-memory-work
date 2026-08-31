#!/usr/bin/env python3
"""classify.py — 把一次 run 的 meta.env 判成一个 verdict。

存在理由:同一个 rc=124 至少三种含义(预算不够 / 真卡死 / 环境自证失败),
处置完全不同,分错就污染兼容性缺口清单。这个判断我已经做过第二遍了,
所以它必须是纯函数,不能是散文。

用法:
    classify.py <meta.env>            # 单个
    classify.py <meta.env> ...        # 批量,输出 TSV
退出码 0 恒定;判定结果在 stdout。
"""
import sys
import re

# verdict → 处置。新增类别时同时补这里,别让处置只活在人脑里。
ACTION = {
    "ok":          "归档;与基线对比,新增 fail 排报告最前",
    "env_broken":  "不算 fail,原样重排(修环境后重跑)",
    "budget_short":"加时限重排(建议 x2),或拆到用例级",
    "hung":        "单独立案为 blocker,不要再放进夜间批量",
    "no_summary":  "零信息片;查日志尾部,按需重排",
    "unknown":     "人工看一眼",
}


def parse(path):
    d = {}
    with open(path) as f:
        for line in f:
            if "=" in line:
                k, _, v = line.partition("=")
                d[k.strip()] = v.strip()
    return d


def classify(m):
    """meta dict -> (verdict, reason)"""
    rc = m.get("RC", "")
    has_summary = m.get("HAS_SUMMARY_LINE", "no") == "yes"
    try:
        elapsed = int(m.get("ELAPSED_S", "0"))
        budget = int(m.get("BUDGET_S", "0"))
    except ValueError:
        return "unknown", "ELAPSED_S/BUDGET_S 不可解析"

    if rc == "3":
        return "env_broken", "环境自证失败(runner exit 3)"

    if rc == "124":
        if has_summary:
            return "no_summary", "rc=124 但有汇总行,异常组合,人工确认"
        # 撞满预算 = 时间不够;远未用满 = 卡死在某处
        if budget and elapsed >= budget * 0.95:
            return "budget_short", f"用满预算 {elapsed}/{budget}s 仍未出汇总"
        return "hung", f"仅用 {elapsed}/{budget}s 就停止推进,疑似卡死"

    if not has_summary:
        return "no_summary", f"rc={rc} 且无 pytest 汇总行,零信息"

    if rc in ("0", "1"):
        # rc=1 = 有 fail,那是有价值的产出,不是故障
        return "ok", m.get("SUMMARY", "")

    return "unknown", f"未预期 rc={rc}"


def counts(summary):
    """'13 passed 4 failed 2 skipped ' -> dict"""
    return {k: int(n) for n, k in re.findall(r"(\d+) (passed|failed|skipped|error\w*)", summary)}


def main(argv):
    if not argv:
        print(__doc__)
        return 0
    multi = len(argv) > 1
    if multi:
        print("verdict\ttestfile\telapsed_s\tsummary\treason")
    for path in argv:
        m = parse(path)
        v, why = classify(m)
        if multi:
            print(f"{v}\t{m.get('TESTFILE','?')}\t{m.get('ELAPSED_S','?')}"
                  f"\t{m.get('SUMMARY','').strip()}\t{why}")
        else:
            print(f"VERDICT: {v}")
            print(f"REASON: {why}")
            print(f"ACTION: {ACTION.get(v, '?')}")
            print(f"TESTFILE: {m.get('TESTFILE','?')}")
            print(f"ELAPSED_S: {m.get('ELAPSED_S','?')}  BUDGET_S: {m.get('BUDGET_S','?')}")
            print(f"COUNTS: {counts(m.get('SUMMARY',''))}")
            print(f"LOG: {m.get('LOG','?')} LINES={m.get('LOG_LINES','?')} MD5={m.get('LOG_MD5','?')}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
