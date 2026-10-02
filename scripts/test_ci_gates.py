"""Gate negatives: insufficient or missing evidence cannot pass."""

from pathlib import Path
import io
import tarfile
import tempfile
import unittest
from zipfile import ZipFile

from validate_runtime_coverage import summarize
from validate_wheel import PACKAGE_FILES, assert_equivalent_wheels, inspect_sdist, inspect_wheel


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

    def test_wheel_wrong_python_support_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            wheel = Path(directory) / "wrong-python.whl"
            prefix = "pcvantol_workspace_control-2.4.0.dist-info/"
            with ZipFile(wheel, "w") as archive:
                for name in PACKAGE_FILES:
                    archive.writestr(name, "")
                archive.writestr(prefix + "METADATA", "Metadata-Version: 2.4\nName: pcvantol-workspace-control\nVersion: 2.4.0\nRequires-Python: >=3.10\n")
                archive.writestr(prefix + "entry_points.txt", "[console_scripts]\nworkspace-server = workspace_control.cli:main\nworkspace-client = workspace_control.cli:client_main\n")
            with self.assertRaisesRegex(ValueError, "Python 3.14.x only"):
                inspect_wheel(wheel, "2.4.0")

    def test_sdist_missing_canonical_source_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            sdist = Path(directory) / "incomplete.tar.gz"
            with tarfile.open(sdist, "w:gz") as archive:
                data = b"[build-system]\n"
                info = tarfile.TarInfo("pcvantol_workspace_control-2.4.2/pyproject.toml")
                info.size = len(data)
                archive.addfile(info, io.BytesIO(data))
            with self.assertRaisesRegex(ValueError, "sdist lacks required source files"):
                inspect_sdist(sdist, "2.4.2")

    def test_sdist_rebuilt_wheel_content_mismatch_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.whl"
            rebuilt = Path(directory) / "rebuilt.whl"
            with ZipFile(source, "w") as archive:
                archive.writestr("workspace_control/client.js", "source")
            with ZipFile(rebuilt, "w") as archive:
                archive.writestr("workspace_control/client.js", "changed")
            with self.assertRaisesRegex(ValueError, "sdist-rebuilt wheel differs"):
                assert_equivalent_wheels(source, rebuilt, "2.4.2")


if __name__ == "__main__":
    unittest.main()
