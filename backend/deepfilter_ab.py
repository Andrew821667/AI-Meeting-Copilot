from __future__ import annotations

import argparse
import json
from pathlib import Path


def _simple_wer(reference: str, hypothesis: str) -> float:
    ref = reference.split()
    hyp = hypothesis.split()
    if not ref:
        return 0.0 if not hyp else 1.0

    # Levenshtein distance on tokens.
    dp = [[0] * (len(hyp) + 1) for _ in range(len(ref) + 1)]
    for i in range(len(ref) + 1):
        dp[i][0] = i
    for j in range(len(hyp) + 1):
        dp[0][j] = j

    for i in range(1, len(ref) + 1):
        for j in range(1, len(hyp) + 1):
            cost = 0 if ref[i - 1] == hyp[j - 1] else 1
            dp[i][j] = min(
                dp[i - 1][j] + 1,
                dp[i][j - 1] + 1,
                dp[i - 1][j - 1] + cost,
            )
    return dp[len(ref)][len(hyp)] / len(ref)


def _wer(reference: str, hypothesis: str) -> float:
    try:
        import jiwer  # type: ignore

        return float(jiwer.wer(reference, hypothesis))
    except Exception:
        return _simple_wer(reference, hypothesis)


def evaluate_candidate(rows: list[dict]) -> dict:
    if not rows:
        return {
            "wer": 0.0,
            "hallucination_rate": 0.0,
            "latency_ms_avg": 0.0,
            "intelligibility_avg": 0.0,
        }

    wers = [_wer(row["reference"], row["hypothesis"]) for row in rows]
    hallucinations = [1.0 if row.get("hallucinated", False) else 0.0 for row in rows]
    latencies = [float(row.get("latency_ms", 0.0)) for row in rows]
    intelligibility = [float(row.get("intelligibility", 0.0)) for row in rows]
    return {
        "wer": sum(wers) / len(wers),
        "hallucination_rate": sum(hallucinations) / len(hallucinations),
        "latency_ms_avg": sum(latencies) / len(latencies),
        "intelligibility_avg": sum(intelligibility) / len(intelligibility),
    }


def compare(baseline_rows: list[dict], candidate_rows: list[dict]) -> dict:
    baseline = evaluate_candidate(baseline_rows)
    candidate = evaluate_candidate(candidate_rows)

    wer_improvement = baseline["wer"] - candidate["wer"]
    latency_delta = candidate["latency_ms_avg"] - baseline["latency_ms_avg"]
    checks = {
        "wer_improvement_ge_2pct": wer_improvement >= 0.02,
        "hallucination_not_worse": candidate["hallucination_rate"] <= baseline["hallucination_rate"],
        "latency_delta_le_40ms": latency_delta <= 40.0,
        "intelligibility_ge_4": candidate["intelligibility_avg"] >= 4.0,
    }

    return {
        "baseline": baseline,
        "candidate": candidate,
        "wer_improvement": wer_improvement,
        "latency_delta_ms": latency_delta,
        "checks": checks,
        "decision": "enable" if all(checks.values()) else "keep_off",
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="DeepFilterNet3 A/B оценка")
    parser.add_argument("--baseline", required=True, help="JSON с baseline измерениями")
    parser.add_argument("--candidate", required=True, help="JSON с candidate измерениями")
    parser.add_argument("--out", default="deepfilter_ab_report.json", help="Куда сохранить отчёт")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    baseline_rows = json.loads(Path(args.baseline).read_text(encoding="utf-8"))
    candidate_rows = json.loads(Path(args.candidate).read_text(encoding="utf-8"))
    report = compare(baseline_rows, candidate_rows)
    Path(args.out).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
