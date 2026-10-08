"""Build and install the declared wheel from source in disposable environments."""

import configparser
from email.parser import Parser
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import venv
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_FILES = {"workspace_control/__init__.py", "workspace_control/service.py",
                 "workspace_control/http.py", "workspace_control/cli.py",
                 "workspace_control/review_peer.py",
                 "workspace_control/worklist_peer.py",
                 "workspace_control/worklist_contract.py",
                 "workspace_control/worklist_control_contract.py",
                 "workspace_control/worklist_control_peer.py",
                 "workspace_control/client.html", "workspace_control/client.js",
                 "workspace_control/client.css"}


def inspect_wheel(wheel, expected_version):
    with ZipFile(wheel) as archive:
        names = set(archive.namelist())
        prefix = f"pcvantol_workspace_control-{expected_version}.dist-info/"
        required = PACKAGE_FILES | {prefix + "METADATA", prefix + "entry_points.txt"}
        if not required <= names:
            raise ValueError(f"wheel lacks required files: {sorted(required - names)}")
        metadata = archive.read(prefix + "METADATA").decode("utf-8")
        fields = Parser().parsestr(metadata)
        if fields.get("Name") != "pcvantol-workspace-control" or fields.get("Version") != expected_version:
            raise ValueError("wheel metadata does not match canonical product identity/version")
        python_range = fields.get("Requires-Python", "")
        if {clause.strip() for clause in python_range.split(",")} != {">=3.14", "<3.15"}:
            raise ValueError("wheel metadata must require Workspace-owned Python 3.14.x only")
        entries = configparser.ConfigParser()
        entries.read_string(archive.read(prefix + "entry_points.txt").decode("utf-8"))
        expected = {"workspace-server": "workspace_control.cli:main",
                    "workspace-client": "workspace_control.cli:client_main"}
        if dict(entries["console_scripts"]) != expected:
            raise ValueError("wheel role entrypoints do not match declared roles")


def inspect_sdist(sdist, expected_version):
    prefix = f"pcvantol_workspace_control-{expected_version}/"
    required = {"pyproject.toml", "setup.py", "product-version.json"} | PACKAGE_FILES
    with tarfile.open(sdist, "r:gz") as archive:
        names = set(archive.getnames())
        missing = {prefix + name for name in required} - names
        if missing:
            raise ValueError(f"sdist lacks required source files: {sorted(missing)}")
        version_file = archive.extractfile(prefix + "product-version.json")
        if version_file is None or json.load(version_file)["version"] != expected_version:
            raise ValueError("sdist canonical version differs from product version")


def semantic_wheel_contents(wheel, expected_version):
    prefix = f"pcvantol_workspace_control-{expected_version}.dist-info/"
    with ZipFile(wheel) as archive:
        names = {name for name in archive.namelist()
                 if name.startswith("workspace_control/") or
                 name in {prefix + "METADATA", prefix + "entry_points.txt"}}
        return {name: archive.read(name) for name in names}


def assert_equivalent_wheels(source_wheel, rebuilt_wheel, expected_version):
    source = semantic_wheel_contents(source_wheel, expected_version)
    rebuilt = semantic_wheel_contents(rebuilt_wheel, expected_version)
    if source != rebuilt:
        raise ValueError("sdist-rebuilt wheel differs in product files or role metadata")


def main():
    expected_version = json.loads((ROOT / "product-version.json").read_text())["version"]
    with tempfile.TemporaryDirectory(prefix="workspace-wheel-gate-") as directory:
        temp = Path(directory)
        build_env, rebuild_env, install_env = temp / "build-env", temp / "rebuild-env", temp / "install-env"
        venv.create(build_env, with_pip=True)
        build_python = build_env / "bin" / "python"
        subprocess.run([str(build_python), "-m", "pip", "wheel", "--no-deps", "--wheel-dir", str(temp / "source-wheel"), str(ROOT)],
                       check=True, cwd=temp, stdout=subprocess.DEVNULL)
        wheels = list((temp / "source-wheel").glob("*.whl"))
        if len(wheels) != 1 or wheels[0].name != f"pcvantol_workspace_control-{expected_version}-py3-none-any.whl":
            raise ValueError("unexpected wheel identity")
        inspect_wheel(wheels[0], expected_version)
        subprocess.run([str(build_python), "-m", "pip", "install", "build"],
                       check=True, cwd=temp, stdout=subprocess.DEVNULL)
        subprocess.run([str(build_python), "-m", "build", "--sdist", "--outdir", str(temp / "sdist"), str(ROOT)],
                       check=True, cwd=temp, stdout=subprocess.DEVNULL)
        sdists = list((temp / "sdist").glob("*.tar.gz"))
        if len(sdists) != 1 or sdists[0].name != f"pcvantol_workspace_control-{expected_version}.tar.gz":
            raise ValueError("unexpected sdist identity")
        inspect_sdist(sdists[0], expected_version)
        venv.create(rebuild_env, with_pip=True)
        rebuild_python = rebuild_env / "bin" / "python"
        subprocess.run([str(rebuild_python), "-m", "pip", "wheel", "--no-deps", "--wheel-dir",
                        str(temp / "rebuilt-wheel"), str(sdists[0])],
                       check=True, cwd=temp, stdout=subprocess.DEVNULL)
        rebuilt_wheels = list((temp / "rebuilt-wheel").glob("*.whl"))
        if len(rebuilt_wheels) != 1 or rebuilt_wheels[0].name != wheels[0].name:
            raise ValueError("unexpected sdist-rebuilt wheel identity")
        inspect_wheel(rebuilt_wheels[0], expected_version)
        assert_equivalent_wheels(wheels[0], rebuilt_wheels[0], expected_version)
        venv.create(install_env, with_pip=True)
        install_python = install_env / "bin" / "python"
        env = dict(os.environ)
        env.pop("PYTHONPATH", None)
        subprocess.run([str(install_python), "-m", "pip", "install", "--no-index", "--no-deps", str(rebuilt_wheels[0])],
                       check=True, cwd=temp, env=env, stdout=subprocess.DEVNULL)
        probe = ("import importlib.resources, json, pathlib, workspace_control; "
                 "root = importlib.resources.files('workspace_control'); "
                 "assert (root / 'client.html').is_file(); "
                 "assert (root / 'client.js').is_file(); "
                 "assert (root / 'client.css').is_file(); "
                 "print(json.dumps({'version': workspace_control.__version__, "
                 "'path': str(pathlib.Path(workspace_control.__file__).resolve())}))")
        result = subprocess.run([str(install_python), "-c", probe], check=True,
                                cwd=temp, env=env, capture_output=True, text=True)
        installed = json.loads(result.stdout)
        if installed["version"] != expected_version or not Path(installed["path"]).is_relative_to(install_env.resolve()):
            raise ValueError("runtime import escaped the fresh installed wheel")
        for role in ("workspace-server", "workspace-client"):
            subprocess.run([str(install_env / "bin" / role), "--help"], check=True,
                           cwd=temp, env=env, stdout=subprocess.DEVNULL)
        print(f"Workspace source wheel, sdist rebuild, semantic parity and isolated install passed: {expected_version}.")


if __name__ == "__main__":
    main()
