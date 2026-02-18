# Stage 21 Report (ASR WER benchmark: WhisperKit vs Qwen3-ASR)

## Scope
Добавить стандартный benchmark pipeline для сравнения ASR-провайдеров по WER и выбора победителя.

## Delivered
1. Benchmark CLI:
   - `backend/asr_benchmark.py`
   - вход: два JSON-набора гипотез (`whisper`, `qwen`) с reference/hypothesis
   - выход: WER по каждому провайдеру + winner + delta
2. Тесты:
   - `backend/tests/test_asr_benchmark.py`

## Result
Сравнение WhisperKit и Qwen3-ASR стало формальным и воспроизводимым, что закрывает A/B decision loop для ASR.
