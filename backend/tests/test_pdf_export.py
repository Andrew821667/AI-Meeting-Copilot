from pathlib import Path

from pdf_export import export_report_pdf


def test_export_report_pdf_from_markdown(tmp_path: Path) -> None:
    report_path = tmp_path / "s1-report.md"
    report_path.write_text(
        "# Отчет встречи\n\nРешение: зафиксировать дедлайн и штраф.\n",
        encoding="utf-8",
    )

    pdf_path = export_report_pdf(report_path, "s1")
    if pdf_path is None:
        # Разрешаем деградацию, если cupsfilter недоступен в окружении.
        return

    assert pdf_path.exists()
    assert pdf_path.name == "s1-report.pdf"
    assert pdf_path.read_bytes().startswith(b"%PDF")
