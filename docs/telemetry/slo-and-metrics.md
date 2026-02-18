# SLO and Metrics (Stage 0)

## Realtime SLO
- card_show_latency p50 <= 2.0s
- card_show_latency p95 <= 2.5s
- fallback card latency <= 3.5s

## Reliability goals
- No dropped final transcript events.
- No lost cards during overlap (pending queue correctness).
- Timeout path always returns fallback card (never silence).

## Metrics to collect
- llm_discarded_responses
- llm_canceled_after_send_rate
- llm_timeout_rate
- avg_asr_partial_latency_ms
- avg_asr_final_latency_ms
- avg_llm_latency_ms
- card_show_latency_p50_ms
- card_show_latency_p95_ms
- pending_queue_max_len
- audio_source_suspect_count
- diarization_disabled_seconds
- thermal_state_time_serious_seconds
- python_rss_peak_mb

## Queue policy
- transcript_queue maxsize: 200
- partial may be dropped under pressure
- final must never be dropped
- pending card queue max: 20, then collapse into summary card
