#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "xcresult-summary.py"
SPEC = importlib.util.spec_from_file_location("xcresult_summary", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Nao foi possivel carregar {MODULE_PATH}")
xcresult_summary = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = xcresult_summary
SPEC.loader.exec_module(xcresult_summary)


def make_summary(*, result: str = "Passed", total: int = 2, failed: int = 0):
    return xcresult_summary.TestSummary(
        result=result,
        total=total,
        passed=max(total - failed, 0),
        failed=failed,
        skipped=0,
        environment=None,
        title=None,
        failures=[],
    )


class ValidationErrorsTests(unittest.TestCase):
    def test_accepts_successful_non_empty_run(self) -> None:
        self.assertEqual(xcresult_summary.validation_errors(make_summary()), [])

    def test_rejects_zero_tests(self) -> None:
        self.assertIn(
            "nenhum teste foi executado",
            xcresult_summary.validation_errors(make_summary(total=0)),
        )

    def test_rejects_failed_tests_even_when_result_says_passed(self) -> None:
        self.assertIn(
            "1 teste(s) falharam",
            xcresult_summary.validation_errors(make_summary(failed=1)),
        )

    def test_rejects_non_success_result(self) -> None:
        errors = xcresult_summary.validation_errors(make_summary(result="Unknown"))
        self.assertIn("resultado nao indica sucesso: 'Unknown'", errors)


if __name__ == "__main__":
    unittest.main()
