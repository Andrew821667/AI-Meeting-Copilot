from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import signal
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from feedback_store import FeedbackStore
from models import AudioLevelEvent, MicEvent, SystemStateEvent, TranscriptSegment
from orchestrator import TriggerOrchestrator
from pdf_export import export_report_pdf
from postfactum import build_markdown_report
from profile_loader import apply_overrides, load_profile, profile_runtime_settings
from session_export import export_session_json
from session_history_store import SessionHistoryStore
from telemetry import TelemetryCollector

try:
    from dotenv import load_dotenv  # type: ignore
except Exception:  # pragma: no cover
    load_dotenv = None

logger = logging.getLogger("aimc.backend")


@dataclass
class CardFeedback:
    session_id: str
    card_id: str
    useful: bool
    excluded: bool
    trigger_reason: str
    insight: str


@dataclass
class ExcludePhrase:
    session_id: str
    phrase: str


def configure_logging() -> None:
    level_name = os.environ.get("AIMC_LOG_LEVEL", "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )


def load_environment_files() -> None:
    if load_dotenv is None:
        return

    explicit = os.environ.get("AIMC_ENV_FILE", "").strip()
    candidates = []
    if explicit:
        candidates.append(Path(explicit).expanduser())

    app_support_env = Path.home() / "Library/Application Support/AIMeetingCopilot/.env"
    candidates.extend(
        [
            app_support_env,
            Path.cwd() / ".env",
            Path(__file__).resolve().parent / ".env",
        ]
    )

    seen: set[Path] = set()
    for candidate in candidates:
        normalized = candidate.resolve() if candidate.exists() else candidate
        if normalized in seen:
            continue
        seen.add(normalized)
        if candidate.exists():
            load_dotenv(candidate, override=False)


def build_runtime_error(category: str, message: str) -> dict:
    return {
        "type": "runtime_error",
        "payload": {
            "severity": "warning",
            "category": category,
            "message": message,
        },
    }


def run_healthcheck(exports_dir: Path) -> tuple[bool, dict[str, Any]]:
    checks: dict[str, bool] = {}
    details: dict[str, Any] = {}

    try:
        exports_dir.mkdir(parents=True, exist_ok=True)
        probe = exports_dir / ".healthcheck-probe"
        probe.write_text("ok", encoding="utf-8")
        probe.unlink(missing_ok=True)
        checks["exports_writable"] = True
    except Exception as exc:
        checks["exports_writable"] = False
        details["exports_error"] = str(exc)

    try:
        load_profile("negotiation")
        checks["default_profile_load"] = True
    except Exception as exc:
        checks["default_profile_load"] = False
        details["profile_error"] = str(exc)

    deepseek_key_present = bool(os.environ.get("AIMC_DEEPSEEK_API_KEY", "").strip())
    details["deepseek_api_key_present"] = deepseek_key_present
    details["llm_mode"] = "deepseek" if deepseek_key_present else "local_fallback"

    ok = all(checks.values())
    payload = {
        "ok": ok,
        "checks": checks,
        "details": details,
    }
    return ok, payload


class SessionRuntime:
    def __init__(self, exports_dir: Path) -> None:
        self.exports_dir = exports_dir
        self.feedback_store = FeedbackStore(exports_dir / "feedback.sqlite3")
        self.history_store = SessionHistoryStore(exports_dir / "sessions.sqlite3")
        self.profile = load_profile("negotiation")
        self.profile_settings = profile_runtime_settings(self.profile)
        self.telemetry = TelemetryCollector()
        self.orchestrator = TriggerOrchestrator(self.profile, telemetry=self.telemetry)

        self.session_id = ""
        self.started_at = 0.0
        self.ended_at = 0.0
        self.active = False

        self.transcript: list[TranscriptSegment] = []
        self.cards = []

    def start(self, session_id: str, profile: str, profile_overrides: dict | None = None) -> None:
        self.session_id = session_id
        self.started_at = time.time()
        self.ended_at = 0.0
        self.active = True

        self.profile = apply_overrides(load_profile(profile), profile_overrides)
        self.profile_settings = profile_runtime_settings(self.profile)
        self.telemetry = TelemetryCollector()
        self.orchestrator = TriggerOrchestrator(self.profile, telemetry=self.telemetry)
        self.orchestrator.set_paused(False)
        self.orchestrator.set_excluded_phrases(self.feedback_store.load_excluded_phrases(profile_id=self.profile.id))

        self.transcript = []
        self.cards = []

    def record_card_feedback(self, payload: CardFeedback) -> None:
        if payload.session_id != self.session_id:
            return

        self.feedback_store.save_feedback(
            session_id=payload.session_id,
            card_id=payload.card_id,
            useful=payload.useful,
            excluded=payload.excluded,
            trigger_reason=payload.trigger_reason,
            insight=payload.insight,
        )
        self.telemetry.on_card_feedback(useful=payload.useful, excluded=payload.excluded)

        for card in self.cards:
            if card.id == payload.card_id:
                if payload.excluded:
                    card.excluded = True
                break

    def add_excluded_phrase(self, payload: ExcludePhrase) -> None:
        if payload.session_id != self.session_id:
            return

        normalized = self.orchestrator.add_excluded_phrase(payload.phrase)
        if not normalized:
            return
        self.feedback_store.save_excluded_phrase(
            profile_id=self.profile.id,
            phrase=payload.phrase,
            normalized_phrase=normalized,
        )

    def pause(self) -> None:
        self.orchestrator.set_paused(True)

    def resume(self) -> None:
        self.orchestrator.set_paused(False)

    def end(self) -> dict:
        self.active = False
        self.ended_at = time.time()

        meeting_memory = self.orchestrator.meeting_memory_snapshot(ended_ts=self.ended_at, cards=self.cards)
        metrics = self.telemetry.build_metrics()

        json_path = export_session_json(
            exports_dir=self.exports_dir,
            session_id=self.session_id,
            profile=self.profile.id,
            started_at=self.started_at,
            ended_at=self.ended_at,
            transcript=self.transcript,
            cards=self.cards,
            meeting_memory=meeting_memory,
            metrics=metrics,
            settings=self.profile_settings,
        )

        report_md = build_markdown_report(
            session_id=self.session_id,
            profile=self.profile.id,
            meeting_memory=meeting_memory,
            cards=self.cards,
            metrics=metrics,
        )
        report_path = self.exports_dir / f"{self.session_id}-report.md"
        report_path.write_text(report_md, encoding="utf-8")
        report_pdf_path = export_report_pdf(report_path, self.session_id)

        self.history_store.save_session(
            session_id=self.session_id,
            profile_id=self.profile.id,
            started_at=self.started_at,
            ended_at=self.ended_at,
            total_cards=int(metrics.get("total_cards", 0)),
            fallback_cards=int(metrics.get("fallback_cards", 0)),
            export_json_path=str(json_path),
            report_md_path=str(report_path),
            report_pdf_path=str(report_pdf_path) if report_pdf_path is not None else None,
        )

        summary = {
            "session_id": self.session_id,
            "profile": self.profile.id,
            "export_json_path": str(json_path),
            "report_md_path": str(report_path),
            "metrics": metrics,
        }
        if report_pdf_path is not None:
            summary["report_pdf_path"] = str(report_pdf_path)
        return summary


class BackendServer:
    def __init__(self, exports_dir: Path) -> None:
        self.runtime = SessionRuntime(exports_dir=exports_dir)

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        peer = writer.get_extra_info("peername")
        logger.info("Клиент подключен: %s", peer)
        try:
            while not reader.at_eof():
                line = await reader.readline()
                if not line:
                    break

                try:
                    envelope = json.loads(line.decode("utf-8"))
                except json.JSONDecodeError:
                    await self._write_packets(writer, [build_runtime_error("invalid_json", "Некорректный JSON пакет")])
                    continue
                except UnicodeDecodeError:
                    await self._write_packets(writer, [build_runtime_error("invalid_encoding", "Ожидался UTF-8 пакет")])
                    continue

                if not isinstance(envelope, dict):
                    await self._write_packets(
                        writer,
                        [build_runtime_error("invalid_envelope", "Пакет должен быть объектом JSON")],
                    )
                    continue

                msg_type = envelope.get("type")
                payload = envelope.get("payload", {})
                if not isinstance(payload, dict):
                    payload = {}

                try:
                    outbound = await self._dispatch_message(msg_type=msg_type, payload=payload)
                except TypeError as exc:
                    logger.warning("Неверная структура payload для %s: %s", msg_type, exc)
                    outbound = [build_runtime_error("invalid_payload", f"Неверная структура payload: {msg_type}")]
                except Exception as exc:
                    logger.exception("Ошибка обработки сообщения %s", msg_type)
                    outbound = [build_runtime_error("internal_error", f"Ошибка обработки события: {exc}")]

                warnings = self.runtime.telemetry.consume_runtime_warnings()
                for message in warnings:
                    outbound.append(
                        {
                            "type": "runtime_warning",
                            "payload": {
                                "severity": "warning",
                                "category": "llm_latency",
                                "message": message,
                            },
                        }
                    )

                await self._write_packets(writer, outbound)
        finally:
            logger.info("Клиент отключен: %s", peer)
            writer.close()
            await writer.wait_closed()

    async def _dispatch_message(self, msg_type: str, payload: dict) -> list[dict]:
        outbound = []
        if msg_type == "session_control":
            outbound.extend(self._handle_session_control(payload))
        elif msg_type == "mic_event":
            cards = await self.runtime.orchestrator.on_mic_event(MicEvent(**payload))
            outbound.extend(self._wrap_cards(cards))
        elif msg_type == "transcript_segment":
            seg = TranscriptSegment(**payload)
            if seg.isFinal:
                self.runtime.transcript.append(seg)
            cards = await self.runtime.orchestrator.on_transcript_segment(seg)
            outbound.extend(self._wrap_cards(cards))
        elif msg_type == "panic_capture":
            cards = await self.runtime.orchestrator.on_manual_capture()
            outbound.extend(self._wrap_cards(cards))
        elif msg_type == "audio_level":
            await self.runtime.orchestrator.on_audio_level(AudioLevelEvent(**payload))
        elif msg_type == "system_state":
            await self.runtime.orchestrator.on_system_state(SystemStateEvent(**payload))
        elif msg_type == "card_feedback":
            self.runtime.record_card_feedback(CardFeedback(**payload))
        elif msg_type == "exclude_phrase":
            self.runtime.add_excluded_phrase(ExcludePhrase(**payload))
        else:
            outbound.append(build_runtime_error("unknown_event", f"Неизвестный тип события: {msg_type}"))
        return outbound

    async def _write_packets(self, writer: asyncio.StreamWriter, packets: list[dict]) -> None:
        for packet in packets:
            writer.write((json.dumps(packet, ensure_ascii=False) + "\n").encode("utf-8"))
        await writer.drain()

    def _handle_session_control(self, payload: dict) -> list[dict]:
        event = payload.get("event")
        session_id = payload.get("session_id", "")
        profile = payload.get("profile", "negotiation")
        profile_overrides = payload.get("profile_overrides")

        if event == "start":
            self.runtime.start(session_id=session_id, profile=profile, profile_overrides=profile_overrides)
            return [{"type": "session_ack", "payload": {"event": "start", "session_id": session_id}}]

        if event == "pause":
            self.runtime.pause()
            return [{"type": "session_ack", "payload": {"event": "pause", "session_id": self.runtime.session_id}}]

        if event == "resume":
            self.runtime.resume()
            return [{"type": "session_ack", "payload": {"event": "resume", "session_id": self.runtime.session_id}}]

        if event == "end":
            summary = self.runtime.end()
            return [{"type": "session_summary", "payload": summary}]

        return []

    def _wrap_cards(self, cards: list) -> list[dict]:
        wrapped: list[dict] = []
        for card in cards:
            self.runtime.cards.append(card)
            wrapped.append({"type": "insight_card", "payload": card.to_wire()})
        return wrapped


async def run(socket_path: str, exports_dir: Path) -> None:
    exports_dir.mkdir(parents=True, exist_ok=True)
    socket = Path(socket_path)
    socket.parent.mkdir(parents=True, exist_ok=True)
    if socket.exists():
        socket.unlink()

    server = BackendServer(exports_dir=exports_dir)
    uds = await asyncio.start_unix_server(server.handle_client, path=str(socket))

    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop_event.set)
        except (NotImplementedError, RuntimeError):
            pass

    logger.info("Backend UDS запущен: %s", socket)
    try:
        async with uds:
            await stop_event.wait()
    finally:
        uds.close()
        await uds.wait_closed()
        if socket.exists():
            socket.unlink()
        logger.info("Backend UDS остановлен: %s", socket)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Backend-сервис AI Meeting Copilot")
    parser.add_argument("--socket", default="/tmp/ai-meeting-copilot.sock", help="Путь к Unix Domain Socket")
    parser.add_argument("--exports-dir", default="exports", help="Каталог для экспорта сессий")
    parser.add_argument("--healthcheck", action="store_true", help="Проверить готовность backend и выйти")
    return parser.parse_args()


if __name__ == "__main__":
    load_environment_files()
    configure_logging()
    args = parse_args()
    if args.healthcheck:
        ok, payload = run_healthcheck(Path(args.exports_dir))
        print(json.dumps(payload, ensure_ascii=False))
        raise SystemExit(0 if ok else 1)
    try:
        asyncio.run(run(args.socket, Path(args.exports_dir)))
    except KeyboardInterrupt:
        pass
