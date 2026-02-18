# Stage 19 Report (DeepFilterNet3 A/B tooling)

## Scope
Подготовить формализованный A/B-проход для DeepFilterNet3 decision gate (включать/не включать в production).

## Delivered
1. CLI утилита:
   - `backend/deepfilter_ab.py`
   - считает:
     - WER baseline/candidate
     - hallucination rate
     - latency delta
     - intelligibility average
   - итоговое решение: `enable` / `keep_off` по 4 критериям
2. Тесты:
   - `backend/tests/test_deepfilter_ab.py`

## Result
Решение по DeepFilterNet3 стало воспроизводимым и метрико-ориентированным, без ручной интерпретации «на глаз».
