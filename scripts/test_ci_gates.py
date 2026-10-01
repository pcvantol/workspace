"""Gate negatives: insufficient or missing evidence cannot pass."""

from pathlib import Path
import tempfile
import unittest
from zipfile import ZipFile

from validate_runtime_coverage import summarize
from validate_wheel import inspect_wheel


class CIGateTests(unittest.TestCase):
    def test_strict_coverage_and_missing_module(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "http.py"
            source.write_text("pass\n")
            cover = root / "workspace_control.http.cover"
            cover.write_text("".join(["    1: pass\n"] * 402 + [">>>>>> pass\n"] * 98))
            self.assertEqual(summarize(root, [source], root)["http.py"], (402, 500))
            cover.write_text("".join(["    1: pass\n"] * 401 + [">>>>>> pass\n"] * 99))
            with self.assertRaisesRegex(ValueError, "strictly exceed"):
                summarize(root, [source], root)
            cover.unlink()
            with self.assertRaisesRegex(ValueError, "missing executable-line evidence"):
                summarize(root, [source], root)

    def test_nested_product_module_requires_own_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            nested = root / "extra" / "module.py"
            nested.parent.mkdir()
            nested.write_text("pass\n")
            with self.assertRaisesRegex(ValueError, "missing executable-line evidence"):
                summarize(root, [nested], root)
            (root / "workspace_control.extra.module.cover").write_text("    1: pass\n")
            self.assertEqual(summarize(root, [nested], root)["extra/module.py"], (1, 1))

    def test_wheel_missing_role_files_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            wheel = Path(directory) / "incomplete.whl"
            with ZipFile(wheel, "w") as archive:
                archive.writestr("workspace_control/__init__.py", "")
            with self.assertRaisesRegex(ValueError, "wheel lacks required files"):
                inspect_wheel(wheel, "2.4.0")


if __name__ == "__main__":
    unittest.main()
