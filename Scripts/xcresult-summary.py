#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class TestSummary:
    result: str
    total: int
    passed: int
    failed: int
    skipped: int
    environment: str | None
    title: str | None
    failures: list[str]


def _run(cmd: list[str]) -> str:
    return subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT)


def read_test_summary(bundle_path: Path) -> TestSummary:
    raw = _run(
        [
            "xcrun",
            "xcresulttool",
            "get",
            "test-results",
            "summary",
            "--path",
            str(bundle_path),
            "--format",
            "json",
        ]
    )
    data = json.loads(raw)

    failures: list[str] = []
    for f in data.get("testFailures", []) or []:
        # Observed shapes vary between Xcode versions.
        name = (
            f.get("testName")
            or f.get("testCaseName")
            or f.get("name")
            or f.get("identifier")
            or ""
        )
        if isinstance(name, str) and name.strip():
            failures.append(name.strip())

    def _int(key: str) -> int:
        v = data.get(key, 0)
        return int(v) if isinstance(v, (int, float)) else 0

    return TestSummary(
        result=str(data.get("result", "Unknown")),
        total=_int("totalTestCount"),
        passed=_int("passedTests"),
        failed=_int("failedTests"),
        skipped=_int("skippedTests"),
        environment=data.get("environmentDescription"),
        title=data.get("title"),
        failures=failures,
    )


def to_markdown(kind: str, bundle_path: Path, s: TestSummary) -> str:
    lines: list[str] = []
    lines.append(f"### {kind}")
    lines.append("")
    lines.append(f"- Resultado: `{s.result}`")
    lines.append(f"- Total: `{s.total}` | Passou: `{s.passed}` | Falhou: `{s.failed}` | Pulou: `{s.skipped}`")
    lines.append(f"- Bundle: `{bundle_path}`")
    if s.title:
        lines.append(f"- Titulo: `{s.title}`")
    if s.environment:
        lines.append(f"- Ambiente: `{s.environment}`")
    if s.failures:
        lines.append("")
        lines.append("Falhas:")
        for name in s.failures[:20]:
            lines.append(f"- `{name}`")
        if len(s.failures) > 20:
            lines.append(f"- ... (+{len(s.failures) - 20})")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Gera um resumo em Markdown a partir de um .xcresult.")
    parser.add_argument("bundle", type=Path, help="Caminho para o .xcresult")
    parser.add_argument("--kind", default="Testes", help="Nome do grupo (ex: Unit Tests, UI Tests)")
    args = parser.parse_args()

    bundle = args.bundle
    if not bundle.exists():
        print(f"Erro: bundle nao encontrado: {bundle}", file=sys.stderr)
        return 2

    try:
        summary = read_test_summary(bundle)
    except subprocess.CalledProcessError as e:
        print("Erro ao executar xcresulttool:", file=sys.stderr)
        print(e.output, file=sys.stderr)
        return 3
    except Exception as e:
        print(f"Erro ao ler bundle: {e}", file=sys.stderr)
        return 4

    sys.stdout.write(to_markdown(args.kind, bundle, summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

