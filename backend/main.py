from __future__ import annotations

import argparse
import asyncio
import json
import os
import time
from pathlib import Path

from models import AudioLevelEvent, MicEvent, SystemStateEvent, TranscriptSegment
from orchestrator import TriggerOrchestrator
from postfactum import build_markdown_report
from profile_loader import load_profile
from session_export import export_session_json
from telemetry import TelemetryCollector


class SessionRuntime:
    def __init__(self, exports_dir: Path) -> None:
        self.exports_dir = exports_dir
        self.profile = load_profile("negotiation")
        self.telemetry = TelemetryCollector()
        self.orchestrator = TriggerOrchestrator(self.profile, telemetry=self.telemetry)

        self.session_id = ""
        self.started_at = 0.0
        self.ended_at = 0.0
        self.active = False

        self.transcript: list[TranscriptSegment] = []
        self.cards = []

    def start(self, session_id: str, profile: str) -> None:
        self.session_id = session_id
        self.started_at = time.time()
        self.ended_at = 0.0
        self.active = True

        self.profile = load_profile(profile)
        self.telemetry = TelemetryCollector()
        self.orchestrator = TriggerOrchestrator(self.profile, telemetry=self.telemetry)
        self.orchestrator.set_paused(False)

        self.transcript = []
        self.cards = []

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

        return {
            "session_id": self.session_id,
            "profile": self.profile.id,
            "export_json_path": str(json_path),
            "report_md_path": str(report_path),
            "metrics": metrics,
        }


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

        if event == "start":
            self.runtime.start(session_id=session_id, profile=profile)
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
    parser = argparse.ArgumentParser(description="AI Meeting Copilot backend")
    parser.add_argument("--socket", required=True, help="Unix domain socket path")
    parser.add_argument("--exports-dir", default="exports", help="Directory for session exports")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    try:
        asyncio.run(run(args.socket, Path(args.exports_dir)))
    except KeyboardInterrupt:
        pass
