from __future__ import annotations

import argparse
import asyncio
import json
import os
import time
from dataclasses import dataclass
from pathlib import Path

from feedback_store import FeedbackStore
from models import AudioLevelEvent, MicEvent, SystemStateEvent, TranscriptSegment
from orchestrator import TriggerOrchestrator
from pdf_export import export_report_pdf
from postfactum import build_markdown_report
from profile_loader import apply_overrides, load_profile, profile_runtime_settings
from session_export import export_session_json
from session_history_store import SessionHistoryStore
from telemetry import TelemetryCollector


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
        try:
            while not reader.at_eof():
                line = await reader.readline()
                if not line:
                    break

                try:
                    envelope = json.loads(line.decode("utf-8"))
                except json.JSONDecodeError:
                    continue

                msg_type = envelope.get("type")
                payload = envelope.get("payload", {})

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

                for packet in outbound:
                    writer.write((json.dumps(packet, ensure_ascii=False) + "\n").encode("utf-8"))

                await writer.drain()
        finally:
            writer.close()
            await writer.wait_closed()

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
    if os.path.exists(socket_path):
        os.remove(socket_path)

    server = BackendServer(exports_dir=exports_dir)
    uds = await asyncio.start_unix_server(server.handle_client, path=socket_path)

    async with uds:
        await uds.serve_forever()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Backend-сервис AI Meeting Copilot")
    parser.add_argument("--socket", required=True, help="Путь к Unix Domain Socket")
    parser.add_argument("--exports-dir", default="exports", help="Каталог для экспорта сессий")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    try:
        asyncio.run(run(args.socket, Path(args.exports_dir)))
    except KeyboardInterrupt:
        pass
