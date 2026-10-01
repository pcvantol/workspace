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
    def raw(path, hosts, origins=(), method="GET", authorizations=None, pins=None):
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
        try:
            connection.putrequest(method, path, skip_host=True, skip_accept_encoding=True)
            for host in hosts:
                connection.putheader("Host", host)
            for origin in origins:
                connection.putheader("Origin", origin)
            if authorizations is None:
                authorizations = ("Bearer " + token,)
            if pins is None:
                pins = (instance_id,)
            for authorization in authorizations:
                connection.putheader("Authorization", authorization)
            for pin in pins:
                connection.putheader("X-Workspace-Instance", pin)
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
    valid_auth = "Bearer " + token
    for authorizations in ((valid_auth, valid_auth), (valid_auth, "Bearer wrong"),
                           ("Bearer wrong", valid_auth)):
        response = raw("/v1/status", (host,), authorizations=authorizations)
        assert response[0] == 400 and json.loads(response[2])["error"] == "AMBIGUOUS_CREDENTIALS"
    for pins in ((instance_id, instance_id), (instance_id, "wrong"), ("wrong", instance_id)):
        response = raw("/v1/status", (host,), pins=pins)
        assert response[0] == 400 and json.loads(response[2])["error"] == "AMBIGUOUS_CREDENTIALS"
    assert raw("/v1/status", (host,), authorizations=())[0] == 401
    assert raw("/v1/status", (host,), pins=())[0] == 409
    assert raw("/v1/status", (host,))[0] == 200


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


def verify_installed_cli_projects(server_exe, instance_root, cwd, env, url, instance_id, token, catalogue):
    """The installed local CLI must expose exactly the own service projection."""
    original = catalogue.read_text()
    command = [str(server_exe), "--root", str(instance_root), "projects"]
    def cli():
        return subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
    try:
        catalogue.unlink()
        result = cli()
        assert result.returncode == 0 and result.stderr == ""
        assert json.loads(result.stdout) == json.loads(read(url + "/v1/projects", token=token,
                                                           instance=instance_id)[1])
        stamp = datetime.now(timezone.utc).isoformat()
        for payload in ({"source": "LOCAL", "observed_at": stamp, "projects": []},
                        {"source": "DEMO", "observed_at": stamp,
                         "projects": [{"id": "one", "name": "Sample"}]},
                        {"source": "LOCAL", "observed_at": "2020-01-01T00:00:00Z",
                         "projects": [], "partial": True}):
            catalogue.write_text(json.dumps(payload))
            catalogue.chmod(0o600)
            result = cli()
            assert result.returncode == 0 and result.stderr == ""
            assert json.loads(result.stdout) == json.loads(read(url + "/v1/projects", token=token,
                                                               instance=instance_id)[1])
        catalogue.write_text(json.dumps({"source": "LOCAL", "observed_at": stamp,
                                         "projects": [], "peer_status": "QUALIFIED"}))
        result = cli()
        assert result.returncode == 2 and result.stdout == "" and token not in result.stderr
        assert read(url + "/v1/projects", token=token, instance=instance_id)[0] == 503
    finally:
        catalogue.write_text(original)
        catalogue.chmod(0o600)


def verify_installed_capabilities(server_exe, instance_root, cwd, env, url,
                                  instance_id, other_instance_id, token, other_token):
    """Check protected operation inventory and its local CLI projection."""
    assert read(url + "/v1/status")[0] == 401
    assert read(url + "/v1/status", token=other_token, instance=instance_id)[0] == 401
    assert read(url + "/v1/status", token=token, instance=other_instance_id)[0] == 409
    assert read(url + "/v1/capabilities")[0] == 401
    assert read(url + "/v1/capabilities", token=token, instance=other_instance_id)[0] == 409
    capabilities = json.loads(read(url + "/v1/capabilities", token=token, instance=instance_id)[1])
    assert capabilities["instance_id"] == instance_id and capabilities["peer_operations_qualified"] is False
    command = [str(server_exe), "--root", str(instance_root), "capabilities"]
    cli_capabilities = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
    assert cli_capabilities.returncode == 0 and cli_capabilities.stderr == ""
    assert json.loads(cli_capabilities.stdout) == capabilities
    assert token not in cli_capabilities.stdout
    assert read(url + "/v1/openapi.json")[0] == 401
    assert read(url + "/v1/openapi.json", token=token, instance=other_instance_id)[0] == 409
    api = json.loads(read(url + "/v1/openapi.json", token=token, instance=instance_id)[1])
    openapi_command = [str(server_exe), "--root", str(instance_root), "openapi"]
    cli_api = subprocess.run(openapi_command, cwd=cwd, env=env, capture_output=True, text=True)
    assert cli_api.returncode == 0 and cli_api.stderr == "" and json.loads(cli_api.stdout) == api
    assert token not in cli_api.stdout
    identity_path = instance_root / "instance.json"
    identity_path.chmod(0o644)
    try:
        denied = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
        assert denied.returncode == 2 and denied.stdout == "" and token not in denied.stderr
        denied_api = subprocess.run(openapi_command, cwd=cwd, env=env, capture_output=True, text=True)
        assert denied_api.returncode == 2 and denied_api.stdout == "" and token not in denied_api.stderr
    finally:
        identity_path.chmod(0o600)
    assert json.loads(read(url + "/v1/capabilities", token=token,
                           instance=instance_id)[1]) == capabilities
    inventory = {item["id"]: item for item in capabilities["operations"]}
    assert inventory["capabilities.read"]["path"] == "/v1/capabilities"
    assert inventory["capabilities.read"]["local_cli"] == "capabilities"
    assert inventory["openapi.read"]["local_cli"] == "openapi"
    assert inventory["instance.init"]["exposure"] == "LOCAL_ONLY_ADMIN"
    assert "path" not in inventory["instance.init"]


def verify_browser_project_error_semantics(page, instance_root):
    """Preserve a visible row across each injected project-read failure and recovery."""
    catalogue = instance_root / "projects.json"
    catalogue.write_text(json.dumps({"source": "LOCAL",
                                     "observed_at": datetime.now(timezone.utc).isoformat(),
                                     "projects": [{"id": "before-error", "name": "Before error"}]}))
    catalogue.chmod(0o600)
    page.locator("#connect").click()
    page.get_by_text("Before error (before-error)").wait_for()
    for code, label in ((401, "UNAUTHORIZED"), (409, "WRONG INSTANCE"),
                        (400, "UNAVAILABLE")):
        def handler(route):
            route.fulfill(status=code, body="{}")
        page.route("**/v1/projects", handler)
        page.locator("#connect").click()
        page.get_by_role("status").get_by_text(label).wait_for()
        assert page.locator("#projects li").count() == 0
        assert page.locator("#capabilities li").count() == 0
        page.unroute("**/v1/projects", handler)
        page.locator("#connect").click()
        page.get_by_text("Before error (before-error)").wait_for()
    catalogue.unlink()
    page.locator("#connect").click()
    page.locator("#project-state").get_by_text("UNCONFIGURED").wait_for()


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
            verify_installed_capabilities(server_exe, first, root, env, first_url,
                                          first_id, second_id, token, other_token)
            assert json.loads(read(first_url + "/v1/projects", token=token, instance=first_id)[1])["state"] == "UNCONFIGURED"
            assert b"/client.js" in read(first_url + "/")[1]
            assert b"fetch('/v1/projects'" in read(first_url + "/client.js")[1]
            assert b"fetch('/v1/capabilities'" in read(first_url + "/client.js")[1]
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
                page.locator("#capability-state").get_by_text("AVAILABLE").wait_for()
                assert page.locator("#peer-state").inner_text() == "Peer operations: UNQUALIFIED"
                listed = page.locator("#capabilities li").all_text_contents()
                assert "capabilities.read · HTTP_EXPOSED" in listed
                assert "instance.init · LOCAL_ONLY_ADMIN" in listed
                verify_browser_project_error_semantics(page, first)
                page.route("**/v1/capabilities", lambda route: route.fulfill(status=503, body="{}"))
                page.locator("#connect").click()
                page.locator("#project-state").get_by_text("UNCONFIGURED").wait_for()
                assert page.locator("#capability-state").inner_text() == "UNAVAILABLE"
                assert page.locator("#capabilities li").count() == 0
                page.unroute("**/v1/capabilities")
                page.evaluate("localStorage.setItem('workspace.instanceId', 'wrong')")
                page.locator("#connect").click()
                page.get_by_role("status").get_by_text("WRONG INSTANCE").wait_for()
                assert page.locator("#capabilities li").count() == 0
                page.locator("#forget").click()
                assert page.locator("#capabilities li").count() == 0
                assert page.locator("#token").input_value() == ""
                page.locator("#connect").click()
                page.get_by_role("status").get_by_text("UNAUTHORIZED").wait_for()
                page.locator("#token").fill(token)
                page.locator("#connect").click()
                page.locator("#project-state").get_by_text("UNCONFIGURED").wait_for()
                page.locator("#capability-state").get_by_text("AVAILABLE").wait_for()
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
                verify_installed_cli_projects(server_exe, first, root, env, first_url,
                                              first_id, token, catalogue)
                processes[0].send_signal(signal.SIGTERM)
                processes[0].wait(timeout=5)
                assert processes[0].returncode == -signal.SIGTERM
                page.locator("#connect").click()
                page.get_by_role("status").get_by_text("UNAVAILABLE").wait_for()
                assert page.locator("#capabilities li").count() == 0
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
                              "unique_auth_pin_headers": "PASS",
                              "local_projects_cli_parity": "PASS",
                              "local_capabilities_cli_parity": "PASS",
                              "local_openapi_cli_parity": "PASS",
                              "browser_capabilities_and_clear": "PASS",
                              "browser_project_error_semantics": "PASS",
                              "browser_forget_token": "PASS",
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
