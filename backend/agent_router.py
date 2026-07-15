"""Онлайн-роутер ассистентов: по текущей реплике выбирает из «Авто»-пула
1–2 реально уместных ассистента, а не запускает всех подряд.

Замысел системы: единый оркестратор подключает нужных ассистентов «по
необходимости». Ассистенты в режиме «Всегда» (pin) реагируют на каждый
триггер и роутер их не касается; ассистенты в режиме «Авто» попадают сюда
как кандидаты, и роутер оставляет только релевантных.

Роутинг гибридный:
  1. Эвристики по сигналам реплики (мгновенно, без затрат) — основной путь.
  2. Опциональный LLM-классификатор (AIMC_AGENT_ROUTER=llm|hybrid) для случаев,
     где эвристики молчат.
"""

from __future__ import annotations

import logging
import os
import re

logger = logging.getLogger("aimc.backend.agent_router")

# Профиль = (agent_name, instruction). Роутим по agent_name.
Profile = tuple[str, str]

# Сигналы на ассистента: (regex, вес, ci). ci=True — регистронезависимо
# (по умолчанию); ci=False — регистрозависимо (для детекции аббревиатур капсом,
# иначе с IGNORECASE regex ловит любое слово). Порог отбора — вес >= threshold.
_SIGNALS: dict[str, list[tuple[str, float, bool]]] = {
    "Юрист": [
        (r"догово[рв]|контракт|соглашен|услови[яйе]|пункт\b|раздел\b", 1.0, True),
        (r"обязательств|обязан|ответственност|гаранти|неустойк|штраф|пени?\b", 1.5, True),
        (r"расторж|претензи|подпис|срок[аи]?\b|аванс|предоплат|оплат|ндс", 1.0, True),
        (r"\b(contract|clause|liability|warranty|penalty|obligation|terms|indemnif)\w*", 1.5, True),
    ],
    "Терминолог": [
        (r"\b[A-ZА-Я][A-ZА-Я0-9]{1,5}\b", 1.0, False),  # аббревиатуры КАПСОМ (API, SLA, КПЭ)
        (r"\b(API|SDK|SLA|KPI|ROI|CRM|MVP|SaaS|LLM|RAG|CI/CD|SEO|B2B|B2C|NDA)\b", 1.5, True),
        (r"фреймворк|протокол|алгоритм|метрик|инфраструктур|деплой|пайплайн", 1.0, True),
    ],
    "Факт-чекер": [
        (r"\d+\s?%|процент|доля рынк|млн|млрд|тысяч|в разы|статистик|исследован", 1.5, True),
        (r"самый|крупнейш|лучший в|номер один|всегда\b|никогда\b|доказан|очевидно", 1.0, True),
        (r"\b(percent|largest|biggest|proven|statistics|always|never|guaranteed)\b", 1.0, True),
    ],
    "Психолог": [
        (r"срочно|немедленно|последн(ий|яя|ее) шанс|только сейчас|иначе\b|или мы", 1.5, True),
        (r"давлен|угроз|вынужден|обязаны согласиться|нельзя отказ|не оставля", 1.5, True),
        (r"\b(urgent|right now|last chance|pressure|ultimatum|or we)\b", 1.0, True),
    ],
    "Задачи": [
        (r"сделаю|сделаем|подготов|отправлю|возьму на себя|беру\b|договорил", 1.5, True),
        (r"к (понедельник|вторник|сред|четверг|пятниц|концу|след)|до \d|дедлайн|к сроку", 1.5, True),
        (r"\b(action item|i(?:'| wi)ll|by (monday|friday|eod|tomorrow)|deadline|follow up)\b", 1.0, True),
    ],
    "Секретарь": [
        (r"договорил|договорённост|решили\b|итог|резюмир|подытож|фиксир|принял[и]? решен", 1.5, True),
        (r"\b(agreed|decided|to summari|in summary|action items)\b", 1.0, True),
    ],
    "Оркестратор": [
        (r"\?|как (вы )?(думаете|считаете)|ваше мнение|что предлож|как насчёт|стоит ли", 1.0, True),
        (r"\b(what do you think|any thoughts|how about|should we)\b", 1.0, True),
    ],
}

_SELECT_THRESHOLD = 1.0
_MAX_SELECT = 2

_COMPILED: dict[str, list[tuple[re.Pattern, float]]] = {
    name: [(re.compile(pat, re.IGNORECASE if ci else 0), w) for pat, w, ci in sigs]
    for name, sigs in _SIGNALS.items()
}


def _score(agent_name: str, text: str) -> float:
    patterns = _COMPILED.get(agent_name)
    if not patterns:
        return 0.0
    score = 0.0
    for pat, weight in patterns:
        if pat.search(text):
            score += weight
    return score


def route_heuristic(
    pool: list[Profile], segment_text: str, context: str = "", max_select: int = _MAX_SELECT
) -> list[Profile]:
    """Возвращает ≤max_select профилей из pool, релевантных реплике.

    Свежая реплика весит вдвое против фонового контекста."""
    if not pool:
        return []
    seg = (segment_text or "").strip()
    ctx = (context or "").strip()
    scored: list[tuple[float, Profile]] = []
    for profile in pool:
        name = profile[0]
        s = _score(name, seg) * 2.0 + _score(name, ctx)
        if s >= _SELECT_THRESHOLD:
            scored.append((s, profile))
    scored.sort(key=lambda x: x[0], reverse=True)
    selected = [p for _s, p in scored[:max_select]]
    if selected:
        logger.info("router: selected %s from pool %s",
                    [p[0] for p in selected], [p[0] for p in pool])
    return selected


def route(
    pool: list[Profile],
    segment_text: str,
    context: str = "",
    llm_client=None,
    scenario: str = "",
    max_select: int = _MAX_SELECT,
) -> list[Profile]:
    """Главная точка входа. Режим из AIMC_AGENT_ROUTER:
      heuristic (по умолчанию) — только эвристики;
      hybrid — эвристики, а если молчат, добираем LLM-классификатором;
      llm — сразу LLM (fallback на эвристики при ошибке).
    """
    if not pool:
        return []
    mode = os.environ.get("AIMC_AGENT_ROUTER", "heuristic").strip().lower()

    if mode in ("heuristic", "hybrid"):
        picked = route_heuristic(pool, segment_text, context, max_select)
        if picked or mode == "heuristic" or llm_client is None:
            return picked
        # hybrid: эвристики молчат — спросим LLM
        return _route_llm(pool, segment_text, context, llm_client, scenario, max_select)

    if mode == "llm" and llm_client is not None:
        try:
            return _route_llm(pool, segment_text, context, llm_client, scenario, max_select)
        except Exception:
            logger.exception("router: llm routing failed, falling back to heuristic")
            return route_heuristic(pool, segment_text, context, max_select)

    return route_heuristic(pool, segment_text, context, max_select)


def _route_llm(
    pool: list[Profile], segment_text: str, context: str,
    llm_client, scenario: str, max_select: int,
) -> list[Profile]:
    """Дешёвая классификация: какие ассистенты уместны прямо сейчас.
    llm_client должен уметь route_select(...)-подобный вызов; если нет —
    используем универсальный chat. Реализация терпима к отсутствию метода."""
    names = [p[0] for p in pool]
    catalog = "\n".join(f"- {p[0]}: {p[1][:80]}" for p in pool)
    prompt = (
        "Идёт деловой разговор. Доступные ассистенты:\n"
        f"{catalog}\n\n"
        f"Последняя реплика: «{(segment_text or '').strip()[:400]}»\n\n"
        f"Выбери максимум {max_select} ассистентов, которые РЕАЛЬНО уместны именно "
        "сейчас (только если явно нужны). Верни их имена через запятую точно как в "
        "списке, или слово «нет». Без пояснений."
    )
    fn = getattr(llm_client, "route_select", None)
    if not callable(fn):
        # Нет спец-метода — не делаем лишний вызов, откатываемся на эвристики.
        return route_heuristic(pool, segment_text, context, max_select)
    raw = fn(prompt) or ""
    chosen = [n.strip() for n in re.split(r"[,\n;]+", raw) if n.strip()]
    by_name = {p[0]: p for p in pool}
    result = [by_name[n] for n in chosen if n in by_name][:max_select]
    logger.info("router(llm): %r -> %s", raw[:80], [p[0] for p in result])
    return result or route_heuristic(pool, segment_text, context, max_select)
