from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_build_package_contains_all_delivery_documents():
    required = {
        "README.md",
        "01-basic-design.md",
        "02-detailed-design.md",
        "03-parameter-sheet.md",
        "04-network-ip-plan.md",
        "05-build-procedure.md",
        "06-test-specification.md",
        "07-handover-checklist.md",
    }
    actual = {path.name for path in (ROOT / "docs" / "build-package").glob("*.md")}
    assert required <= actual


def test_test_specification_does_not_claim_unrun_results():
    text = (ROOT / "docs" / "build-package" / "06-test-specification.md").read_text(
        encoding="utf-8"
    )
    assert "NOT RUN" in text
    assert "PASS / FAIL / BLOCKED / NOT RUN" in text


def test_network_lab_declares_two_distinct_subnets():
    text = (
        ROOT / "labs" / "network-troubleshooting" / "compose.yaml"
    ).read_text(encoding="utf-8")
    assert "172.28.10.0/24" in text
    assert "172.28.20.0/24" in text
    assert text.count("internal: true") == 1

