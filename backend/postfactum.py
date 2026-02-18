from __future__ import annotations

from models import InsightCard, TranscriptSegment


def build_meeting_memory(transcript: list[TranscriptSegment], cards: list[InsightCard]) -> dict:
    decisions: list[str] = []
    risks: list[str] = []
    open_questions: list[str] = []
    action_items: list[str] = []

    for seg in transcript:
        t = seg.text.lower()
        if any(word in t for word in ["решили", "подтвердили", "согласовали"]):
            decisions.append(seg.text)
        if any(word in t for word in ["риск", "штраф", "неустойка", "ультиматум"]):
            risks.append(seg.text)
        if "?" in seg.text or any(word in t for word in ["уточнить", "вопрос"]):
            open_questions.append(seg.text)
        if any(word in t for word in ["сделаем", "отправлю", "подготовим", "зафиксируем"]):
            action_items.append(seg.text)

    for card in cards:
        if card.severity in {"warning", "alert"}:
            risks.append(card.insight)

    them_count = len([x for x in transcript if x.speaker.startswith("THEM")])

    return {
        "summary_bullets": [
            f"Реплик собеседника: {them_count}",
            f"Карточек показано: {len(cards)}",
        ],
        "decisions": _dedupe(decisions)[:10],
        "risks": _dedupe(risks)[:10],
        "open_questions": _dedupe(open_questions)[:10],
        "action_items": _dedupe(action_items)[:10],
    }


def build_markdown_report(
    session_id: str,
    profile: str,
    meeting_memory: dict,
    cards: list[InsightCard],
    metrics: dict,
) -> str:
    lines: list[str] = []
    lines.append(f"# Постфактум-отчёт — {session_id}")
    lines.append("")
    lines.append(f"Профиль: `{profile}`")
    lines.append("")

    lines.append("## Краткая сводка")
    for item in meeting_memory.get("summary_bullets", []):
        lines.append(f"- {item}")
    lines.append("")

    for title, key in [
        ("Решения", "decisions"),
        ("Риски", "risks"),
        ("Открытые вопросы", "open_questions"),
        ("Действия", "action_items"),
    ]:
        lines.append(f"## {title}")
        values = meeting_memory.get(key, [])
        if values:
            for value in values:
                lines.append(f"- {value}")
        else:
            lines.append("- (нет)")
        lines.append("")

    lines.append("## Карточки")
    for card in cards[-20:]:
        suffix = " [резервная]" if card.is_fallback else ""
        lines.append(f"- [{_severity_ru(card.severity)}] {card.insight}{suffix}")
    lines.append("")

    lines.append("## Метрики")
    for k, v in metrics.items():
        lines.append(f"- {k}: {v}")
    lines.append("")

    return "\n".join(lines)


def _severity_ru(value: str) -> str:
    value = value.lower()
    if value == "info":
        return "инфо"
    if value == "warning":
        return "внимание"
    if value == "alert":
        return "критично"
    return value


def _dedupe(values: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for value in values:
        key = value.strip()
        if not key:
            continue
        if key in seen:
            continue
        seen.add(key)
        out.append(key)
    return out
