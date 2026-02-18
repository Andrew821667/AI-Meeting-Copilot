from __future__ import annotations

import argparse
import json
from pathlib import Path


def _simple_wer(reference: str, hypothesis: str) -> float:
    ref = reference.split()
    hyp = hypothesis.split()
    if not ref:
        return 0.0 if not hyp else 1.0
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


def wer(reference: str, hypothesis: str) -> float:
    try:
        import jiwer  # type: ignore

        return float(jiwer.wer(reference, hypothesis))
    except Exception:
        return _simple_wer(reference, hypothesis)


def evaluate_rows(rows: list[dict], provider_name: str) -> dict:
    if not rows:
        return {"provider": provider_name, "wer": 0.0, "samples": 0}
    values = [wer(r["reference"], r["hypothesis"]) for r in rows]
    return {
        "provider": provider_name,
        "wer": sum(values) / len(values),
        "samples": len(values),
    }


def compare(whisper_rows: list[dict], qwen_rows: list[dict]) -> dict:
    whisper = evaluate_rows(whisper_rows, "whisperkit")
    qwen = evaluate_rows(qwen_rows, "qwen3_asr")
    winner = "whisperkit" if whisper["wer"] <= qwen["wer"] else "qwen3_asr"
    return {
        "whisperkit": whisper,
        "qwen3_asr": qwen,
        "winner": winner,
        "wer_delta": abs(whisper["wer"] - qwen["wer"]),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="ASR WER benchmark: WhisperKit vs Qwen3-ASR")
    parser.add_argument("--whisper", required=True, help="JSON с гипотезами WhisperKit")
    parser.add_argument("--qwen", required=True, help="JSON с гипотезами Qwen3-ASR")
    parser.add_argument("--out", default="asr_benchmark_report.json", help="Путь к output JSON")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    whisper_rows = json.loads(Path(args.whisper).read_text(encoding="utf-8"))
    qwen_rows = json.loads(Path(args.qwen).read_text(encoding="utf-8"))
    report = compare(whisper_rows, qwen_rows)
    Path(args.out).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
