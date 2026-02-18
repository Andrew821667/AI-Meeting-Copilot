from asr_benchmark import compare


def test_asr_benchmark_winner_qwen() -> None:
    whisper = [
        {"reference": "мы согласовали дедлайн", "hypothesis": "мы согласовали дедлаин"},
        {"reference": "нужен план", "hypothesis": "нужен план"},
    ]
    qwen = [
        {"reference": "мы согласовали дедлайн", "hypothesis": "мы согласовали дедлайн"},
        {"reference": "нужен план", "hypothesis": "нужен план"},
    ]

    report = compare(whisper, qwen)
    assert report["winner"] == "qwen3_asr"


def test_asr_benchmark_winner_whisper() -> None:
    whisper = [
        {"reference": "ошибка в проде", "hypothesis": "ошибка в проде"},
    ]
    qwen = [
        {"reference": "ошибка в проде", "hypothesis": "ошибка прод"},
    ]

    report = compare(whisper, qwen)
    assert report["winner"] == "whisperkit"
