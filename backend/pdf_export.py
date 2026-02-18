from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


def export_report_pdf(report_md_path: Path, session_id: str) -> Path | None:
    cupsfilter_path = shutil.which("cupsfilter")
    if cupsfilter_path is None:
        return None

    pdf_path = report_md_path.with_name(f"{session_id}-report.pdf")
    process = subprocess.run(
        [
            cupsfilter_path,
            "-i",
            "text/plain",
            "-m",
            "application/pdf",
            str(report_md_path),
        ],
        capture_output=True,
        check=False,
    )

    if process.returncode != 0:
        return None

    if not process.stdout.startswith(b"%PDF"):
        return None

    pdf_path.write_bytes(process.stdout)
    return pdf_path
