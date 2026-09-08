#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
import unittest
from unittest.mock import patch
import json
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "xcresult-summary.py"
SPEC = importlib.util.spec_from_file_location("xcresult_summary", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Nao foi possivel carregar {MODULE_PATH}")
xcresult_summary = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = xcresult_summary
SPEC.loader.exec_module(xcresult_summary)


def make_summary(*, result: str = "Passed", total: int = 2, failed: int = 0, skipped: int = 0):
    return xcresult_summary.TestSummary(
        result=result,
        total=total,
        passed=max(total - failed - skipped, 0),
        failed=failed,
        skipped=skipped,
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

    def test_rejects_all_skipped_run_even_when_result_says_passed(self) -> None:
        self.assertTrue(xcresult_summary.validation_errors(make_summary(skipped=2)))

    def test_rejects_partially_skipped_release_gate(self) -> None:
        self.assertTrue(xcresult_summary.validation_errors(make_summary(skipped=1)))

    def test_rejects_inconsistent_counts(self) -> None:
        from dataclasses import replace

        self.assertTrue(xcresult_summary.validation_errors(replace(make_summary(), passed=1)))

    def test_rejects_negative_counts(self) -> None:
        from dataclasses import replace

        self.assertTrue(xcresult_summary.validation_errors(replace(make_summary(), skipped=-1)))


class CountParsingTests(unittest.TestCase):
    def test_accepts_exact_integer_counts(self) -> None:
        data = {"result": "Passed", "totalTestCount": 1, "passedTests": 1,
                "failedTests": 0, "skippedTests": 0}
        with patch.object(xcresult_summary, "_run", return_value=json.dumps(data)):
            summary = xcresult_summary.read_test_summary(Path("fixture.xcresult"))
        self.assertEqual(summary.total, 1)
        self.assertEqual(xcresult_summary.validation_errors(summary), [])

    def test_rejects_missing_count_fields(self) -> None:
        for field in ("totalTestCount", "passedTests", "failedTests", "skippedTests"):
            with self.subTest(field=field):
                data = {"result": "Passed", "totalTestCount": 1, "passedTests": 1,
                        "failedTests": 0, "skippedTests": 0}
                del data[field]
                with patch.object(xcresult_summary, "_run", return_value=json.dumps(data)):
                    with self.assertRaises(ValueError):
                        xcresult_summary.read_test_summary(Path("fixture.xcresult"))

    def test_rejects_malformed_count_fields(self) -> None:
        for field in ("totalTestCount", "passedTests", "failedTests", "skippedTests"):
            for value in (True, False, 1.5, "1", None):
                with self.subTest(field=field, value=value):
                    data = {"result": "Passed", "totalTestCount": 1, "passedTests": 1,
                            "failedTests": 0, "skippedTests": 0}
                    data[field] = value
                    with patch.object(xcresult_summary, "_run", return_value=json.dumps(data)):
                        with self.assertRaises(ValueError):
                            xcresult_summary.read_test_summary(Path("fixture.xcresult"))


if __name__ == "__main__":
    unittest.main()
