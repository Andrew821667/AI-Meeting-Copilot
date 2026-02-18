import asyncio

from models import SystemStateEvent
from orchestrator import TriggerOrchestrator
from profile_loader import load_profile


def test_orchestrator_disables_optional_signals_in_degraded_mode() -> None:
    orchestrator = TriggerOrchestrator(load_profile("tech_sync"))
    assert orchestrator.scorer.optional_signals_enabled is True

    asyncio.run(
        orchestrator.on_system_state(
            SystemStateEvent(
                schemaVersion=1,
                seq=1,
                timestamp=1.0,
                batteryLevel=0.15,
                thermalState="nominal",
            )
        )
    )
    assert orchestrator.scorer.optional_signals_enabled is False

    asyncio.run(
        orchestrator.on_system_state(
            SystemStateEvent(
                schemaVersion=1,
                seq=2,
                timestamp=2.0,
                batteryLevel=0.9,
                thermalState="nominal",
            )
        )
    )
    assert orchestrator.scorer.optional_signals_enabled is True
