"""Exercise the exact built wheel in a fresh environment outside the checkout."""

import argparse
from datetime import datetime, timezone
import hashlib
import http.client
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
import venv


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def read(url, *, token=None, instance=None):
    headers = {}
    if token is not None:
        headers["Authorization"] = "Bearer " + token
    if instance is not None:
        headers["X-Workspace-Instance"] = instance
    try:
        with urlopen(Request(url, headers=headers), timeout=1) as response:
            return response.status, response.read()
    except HTTPError as error:
        try:
            return error.code, error.read()
        finally:
            error.close()


def wait_ready(url, process):
    for _ in range(100):
        if process.poll() is not None:
            raise RuntimeError(f"server exited: {process.returncode}")
        try:
            if read(url + "/v1/identity")[0] == 200:
                return
        except URLError:
            pass
        time.sleep(0.05)
    raise RuntimeError("server did not become ready")


def verify_loopback_host_binding(port, instance_id, token):
    """Probe raw authority headers against the installed Server."""
    def raw(path, hosts, origins=(), method="GET"):
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
        try:
            connection.putrequest(method, path, skip_host=True, skip_accept_encoding=True)
            for host in hosts:
                connection.putheader("Host", host)
            for origin in origins:
                connection.putheader("Origin", origin)
            connection.putheader("Authorization", "Bearer " + token)
            connection.putheader("X-Workspace-Instance", instance_id)
            connection.endheaders()
            response = connection.getresponse()
            body = response.read()
            return response.status, response.getheader("Content-Length"), body
        finally:
            connection.close()
    for host in (f"127.0.0.1:{port}", f"localhost:{port}"):
        get = raw("/v1/status", (host,), (f"http://{host}",))
        head = raw("/v1/status", (host,), method="HEAD")
        assert get[0] == head[0] == 200 and get[1] == head[1] and head[2] == b""
        assert raw("/", (host,))[0] == 200
        for method in ("POST", "OPTIONS", "TRACE", "CONNECT"):
            assert raw("/v1/status", (host,), method=method)[0] == 405
    for hosts in ((), (f"evil.example:{port}",),
                  (f"127.0.0.1:{port}", f"127.0.0.1:{port}")):
        assert raw("/v1/status", hosts)[0] == 403
        assert raw("/v1/identity", hosts)[0] == 403
        assert raw("/", hosts)[0] == 403
        for method in ("POST", "HEAD", "OPTIONS", "TRACE", "CONNECT"):
            assert raw("/v1/status", hosts, method=method)[0] == 403
    host = f"127.0.0.1:{port}"
    assert raw("/v1/status", (host,), ("http://evil.example",))[0] == 403
    assert raw("/", (host,), (f"http://{host}", f"http://{host}"))[0] == 403


def verify_catalogue_failure_isolation(url, instance_id, token, catalogue, page):
    """Qualify the distinct installed Server and catalogue failure states."""
    catalogue.write_bytes(b"\xff")
    assert read(url + "/v1/projects", token=token, instance=instance_id)[0] == 503
    code, body = read(url + "/v1/status", token=token, instance=instance_id)
    assert code == 200
    assert json.loads(body)["project_source"] == "SOURCE_UNAVAILABLE"
    page.locator("#connect").click()
    page.get_by_role("status").get_by_text("CONNECTED").wait_for()
    page.locator("#project-state").get_by_text("UNAVAILABLE").wait_for()
    assert instance_id in page.locator("#server").inner_text()
    assert page.locator("#projects li").count() == 0
    catalogue.write_text(json.dumps({"source": "DEMO", "observed_at": datetime.now(timezone.utc).isoformat(),
                                     "projects": [{"id": "demo", "name": "Demo project"}]}))
    page.locator("#connect").click()
    page.locator("#project-state").get_by_text("AVAILABLE · DEMO").wait_for()


def verify_stale_partial_catalogue(url, instance_id, token, catalogue, page):
    """Preserve independent age, completeness and empty evidence in installed UI."""
    stamp = "2020-01-01T00:00:00Z"
    catalogue.write_text(json.dumps({"source": "LOCAL", "observed_at": stamp,
                                     "projects": [], "partial": True}))
    code, body = read(url + "/v1/projects", token=token, instance=instance_id)
    assert code == 200
    result = json.loads(body)
    assert (result["state"], result["partial"], result["stale"], result["projects"]) == ("STALE", True, True, [])
    assert json.loads(read(url + "/v1/status", token=token, instance=instance_id)[1])["project_source"] == "STALE"
    page.locator("#connect").click()
    page.locator("#project-state").get_by_text("STALE · PARTIAL · EMPTY · LOCAL").wait_for()
    assert page.locator("#projects li").count() == 0
    catalogue.write_text(json.dumps({"source": "LOCAL", "observed_at": datetime.now(timezone.utc).isoformat(),
                                     "projects": [{"id": "restored", "name": "Restored"}], "partial": False}))
    page.locator("#connect").click()
    page.locator("#project-state").get_by_text("AVAILABLE · LOCAL").wait_for()


def verify_unique_project_ids(url, instance_id, token, catalogue, page):
    """Reject duplicate identities while retaining distinct IDs with one label."""
    stamp = datetime.now(timezone.utc).isoformat()
    catalogue.write_text(json.dumps({"source": "LOCAL", "observed_at": stamp,
                                     "projects": [{"id": "same", "name": "First"},
                                                  {"id": "same", "name": "Second"}]}))
    assert read(url + "/v1/projects", token=token, instance=instance_id)[0] == 503
    assert json.loads(read(url + "/v1/status", token=token, instance=instance_id)[1])["project_source"] == "SOURCE_UNAVAILABLE"
    page.locator("#connect").click()
    page.get_by_role("status").get_by_text("CONNECTED").wait_for()
    page.locator("#project-state").get_by_text("UNAVAILABLE").wait_for()
    assert page.locator("#projects li").count() == 0
    catalogue.write_text(json.dumps({"source": "LOCAL", "observed_at": stamp,
                                     "projects": [{"id": "one", "name": "Shared"},
                                                  {"id": "two", "name": "Shared"}]}))
    page.locator("#connect").click()
    page.locator("#project-state").get_by_text("AVAILABLE · LOCAL").wait_for()
    assert page.locator("#projects li").count() == 2
    assert {item["id"] for item in json.loads(read(url + "/v1/projects", token=token,
                                                instance=instance_id)[1])["projects"]} == {"one", "two"}
    catalogue.write_text(json.dumps({"source": "DEMO", "observed_at": stamp,
                                     "projects": [{"id": "demo", "name": "Demo project"}]}))


def verify_unique_catalogue_keys(url, instance_id, token, catalogue, page):
    """Reject duplicate provenance and nested identity keys in installed reads."""
    valid = catalogue.read_text()
    catalogue.write_text(valid.replace('"source": "DEMO"', '"source": "LOCAL", "source": "DEMO"', 1))
    assert read(url + "/v1/projects", token=token, instance=instance_id)[0] == 503
    assert json.loads(read(url + "/v1/status", token=token, instance=instance_id)[1])["project_source"] == "SOURCE_UNAVAILABLE"
    page.locator("#connect").click()
    page.get_by_role("status").get_by_text("CONNECTED").wait_for()
    page.locator("#project-state").get_by_text("UNAVAILABLE").wait_for()
    assert page.locator("#projects li").count() == 0
    catalogue.write_text(valid.replace('"id": "demo"', '"id": "hidden", "id": "demo"', 1))
    assert read(url + "/v1/projects", token=token, instance=instance_id)[0] == 503
    catalogue.write_text(valid)
    page.locator("#connect").click()
    page.locator("#project-state").get_by_text("AVAILABLE · DEMO").wait_for()


def verify_catalogue_schema(url, instance_id, token, catalogue, page):
    """An unknown top-level claim must not appear as available project evidence."""
    valid = json.loads(catalogue.read_text())
    for invalid in ({**valid, "peer_status": "QUALIFIED"},
                    {**valid, "parital": True},
                    {key: value for key, value in valid.items() if key != "observed_at"}):
        catalogue.write_text(json.dumps(invalid))
        assert read(url + "/v1/projects", token=token, instance=instance_id)[0] == 503
        code, body = read(url + "/v1/status", token=token, instance=instance_id)
        assert code == 200 and json.loads(body)["project_source"] == "SOURCE_UNAVAILABLE"
        page.locator("#connect").click()
        page.get_by_role("status").get_by_text("CONNECTED").wait_for()
        page.locator("#project-state").get_by_text("UNAVAILABLE").wait_for()
        assert page.locator("#projects li").count() == 0
    catalogue.write_text(json.dumps(valid))
    page.locator("#connect").click()
    page.locator("#project-state").get_by_text("AVAILABLE · DEMO").wait_for()


def main(wheel):
    wheel = wheel.resolve()
    digest = hashlib.sha256(wheel.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix="workspace-installed-") as directory:
        root = Path(directory)
        venv.create(root / "venv", with_pip=True)
        python = root / "venv" / "bin" / "python"
        server_exe = root / "venv" / "bin" / "workspace-server"
        subprocess.run([str(python), "-m", "pip", "install", "--no-deps", str(wheel)], check=True,
                       stdout=subprocess.DEVNULL)
        env = dict(os.environ)
        env.pop("PYTHONPATH", None)
        for name in ("one", "two"):
            instance_root = root / name
            instance_root.mkdir(mode=0o700)
            subprocess.run([str(server_exe), "--root", str(instance_root), "init"], check=True,
                           cwd=root, env=env, stdout=subprocess.DEVNULL)
        first = root / "one"
        second = root / "two"
        first_id = json.loads((first / "instance.json").read_text())["instance_id"]
        second_id = json.loads((second / "instance.json").read_text())["instance_id"]
        assert first_id != second_id
        token = (first / "token").read_text().strip()
        other_token = (second / "token").read_text().strip()
        first_port, second_port = free_port(), free_port()
        processes = []
        try:
            for instance_root, port in ((first, first_port), (second, second_port)):
                process = subprocess.Popen([str(server_exe), "--root", str(instance_root), "serve", "--port", str(port)],
                                           cwd=root, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                processes.append(process)
                wait_ready(f"http://127.0.0.1:{port}", process)
            first_url = f"http://127.0.0.1:{first_port}"
            second_url = f"http://127.0.0.1:{second_port}"
            verify_loopback_host_binding(first_port, first_id, token)
            assert read(first_url + "/v1/status")[0] == 401
            assert read(first_url + "/v1/status", token=other_token, instance=first_id)[0] == 401
            assert read(first_url + "/v1/status", token=token, instance=second_id)[0] == 409
            assert read(first_url + "/v1/capabilities")[0] == 401
            assert read(first_url + "/v1/capabilities", token=token, instance=second_id)[0] == 409
            capabilities = json.loads(read(first_url + "/v1/capabilities", token=token, instance=first_id)[1])
            assert capabilities["instance_id"] == first_id and capabilities["peer_operations_qualified"] is False
            inventory = {item["id"]: item for item in capabilities["operations"]}
            assert inventory["capabilities.read"]["path"] == "/v1/capabilities"
            assert inventory["instance.init"]["exposure"] == "LOCAL_ONLY_ADMIN"
            assert "path" not in inventory["instance.init"]
            assert json.loads(read(first_url + "/v1/projects", token=token, instance=first_id)[1])["state"] == "UNCONFIGURED"
            assert b"/client.js" in read(first_url + "/")[1]
            assert b"fetch('/v1/projects'" in read(first_url + "/client.js")[1]
            from playwright.sync_api import sync_playwright
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch(headless=True, executable_path="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
                page = browser.new_page()
                page.goto(first_url)
                page.locator("#token").fill("wrong")
                page.locator("#connect").click()
                page.get_by_role("status").get_by_text("UNAUTHORIZED").wait_for()
                page.locator("#token").fill(token)
                page.locator("#connect").click()
                page.locator("#project-state").get_by_text("UNCONFIGURED").wait_for()
                page.evaluate("localStorage.setItem('workspace.instanceId', 'wrong')")
                page.locator("#connect").click()
                page.get_by_role("status").get_by_text("WRONG INSTANCE").wait_for()
                page.locator("#forget").click()
                page.locator("#connect").click()
                page.locator("#project-state").get_by_text("UNCONFIGURED").wait_for()
                assert json.loads(read(second_url + "/v1/status", token=other_token, instance=second_id)[1])["instance_id"] == second_id
                catalogue = first / "projects.json"
                catalogue.write_text(json.dumps({"source": "DEMO", "observed_at": datetime.now(timezone.utc).isoformat(),
                                                 "projects": [{"id": "demo", "name": "Demo project"}]}))
                catalogue.chmod(0o600)
                assert json.loads(read(first_url + "/v1/projects", token=token, instance=first_id)[1])["state"] == "AVAILABLE"
                page.locator("#connect").click()
                page.locator("#project-state").get_by_text("AVAILABLE · DEMO").wait_for()
                page.get_by_text("Demo project (demo) · DEMO").wait_for()
                catalogue.write_text(json.dumps({"source": "DEMO", "observed_at": "2020-01-01T00:00:00Z",
                                                 "projects": [{"id": "demo", "name": "Demo project"}]}))
                page.locator("#connect").click()
                page.locator("#project-state").get_by_text("STALE · DEMO").wait_for()
                verify_stale_partial_catalogue(first_url, first_id, token, catalogue, page)
                verify_catalogue_failure_isolation(first_url, first_id, token, catalogue, page)
                verify_unique_project_ids(first_url, first_id, token, catalogue, page)
                verify_unique_catalogue_keys(first_url, first_id, token, catalogue, page)
                verify_catalogue_schema(first_url, first_id, token, catalogue, page)
                processes[0].send_signal(signal.SIGTERM)
                processes[0].wait(timeout=5)
                assert processes[0].returncode == -signal.SIGTERM
                page.locator("#connect").click()
                page.get_by_role("status").get_by_text("UNAVAILABLE").wait_for()
                replacement = subprocess.Popen([str(server_exe), "--root", str(first), "serve", "--port", str(first_port)],
                                               cwd=root, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                processes[0] = replacement
                wait_ready(first_url, replacement)
                assert json.loads(read(first_url + "/v1/status", token=token, instance=first_id)[1])["instance_id"] == first_id
                assert json.loads(read(first_url + "/v1/projects", token=token, instance=first_id)[1])["projects"][0]["id"] == "demo"
                cli = subprocess.run([str(server_exe), "--root", str(first), "status"], check=True,
                                     cwd=root, env=env, capture_output=True, text=True)
                assert json.loads(cli.stdout)["instance_id"] == first_id
                browser.close()
            print(json.dumps({"result": "PASS", "wheel_sha256": digest, "installed_outside_checkout": True,
                              "server_instances": 2, "restart_identity_and_catalogue": "PASS",
                              "api_cli_browser": "PASS", "operation_inventory": "PASS",
                              "catalogue_failure_isolation_and_recovery": "PASS",
                              "unique_project_ids": "PASS",
                              "unique_catalogue_keys": "PASS",
                              "catalogue_schema": "PASS",
                              "loopback_host_origin_binding": "PASS",
                              "peer_contacted": False}, sort_keys=True))
        finally:
            for process in processes:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("wheel", type=Path)
    main(parser.parse_args().wheel)
