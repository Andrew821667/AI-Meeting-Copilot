from __future__ import annotations

import argparse
import asyncio
import json
import os
from dataclasses import asdict

from models import MicEvent, TranscriptSegment
from orchestrator import TriggerOrchestrator
from profile_loader import load_negotiation_profile


class BackendServer:
    def __init__(self) -> None:
        self.profile = load_negotiation_profile()
        self.orchestrator = TriggerOrchestrator(self.profile)

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

                cards = []
                if msg_type == "mic_event":
                    cards = await self.orchestrator.on_mic_event(MicEvent(**payload))
                elif msg_type == "transcript_segment":
                    cards = await self.orchestrator.on_transcript_segment(TranscriptSegment(**payload))
                elif msg_type == "panic_capture":
                    cards = await self.orchestrator.on_manual_capture()

                for card in cards:
                    packet = {"type": "insight_card", "payload": card.to_wire()}
                    writer.write((json.dumps(packet, ensure_ascii=False) + "\n").encode("utf-8"))

                await writer.drain()
        finally:
            writer.close()
            await writer.wait_closed()


async def run(socket_path: str) -> None:
    if os.path.exists(socket_path):
        os.remove(socket_path)

    server = BackendServer()
    uds = await asyncio.start_unix_server(server.handle_client, path=socket_path)

    async with uds:
        await uds.serve_forever()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="AI Meeting Copilot backend")
    parser.add_argument("--socket", required=True, help="Unix domain socket path")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    try:
        asyncio.run(run(args.socket))
    except KeyboardInterrupt:
        pass
