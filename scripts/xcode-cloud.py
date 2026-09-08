#!/usr/bin/env python3
"""Xcode Cloud from the command line, through the App Store Connect API.

    scripts/xcode-cloud.py builds [N]                 last N build runs (default 10)
    scripts/xcode-cloud.py artifacts <build-number>   artifacts of every action in that build
    scripts/xcode-cloud.py download <build-number> [substring ...]
        downloads artifacts whose file name contains any substring (all when none given)
        into .build/xcode-cloud/<build-number>/ and unzips them
    scripts/xcode-cloud.py start <workflow-name> pr <number>|branch <name>
        starts a build of that workflow for a pull request or a branch

Credentials: an App Store Connect API key with the Developer role. The key file lives in
~/.appstoreconnect/private_keys/AuthKey_<KEY ID>.p8, where Apple's own tools look, and the ids
come from ASC_KEY_ID and ASC_ISSUER_ID, read from the environment or ~/.appstoreconnect/plusplus.env.
Nothing here is committed: the .p8 is the secret, and the ids live next to it.
"""
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.appstoreconnect.apple.com/v1"
ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = Path.home() / ".appstoreconnect" / "plusplus.env"


def credentials():
    env = dict(os.environ)
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text().splitlines():
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                env.setdefault(k.strip(), v.strip())
    try:
        key_id, issuer = env["ASC_KEY_ID"], env["ASC_ISSUER_ID"]
    except KeyError:
        sys.exit(f"set ASC_KEY_ID and ASC_ISSUER_ID in the environment or {ENV_FILE}")
    key_path = Path(env.get("ASC_KEY_PATH", Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{key_id}.p8"))
    if not key_path.exists():
        sys.exit(f"missing API key file {key_path}")
    return key_id, issuer, key_path


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """ECDSA signature: DER SEQUENCE { INTEGER r, INTEGER s } -> 64-byte r || s, which JWT wants."""
    assert der[0] == 0x30
    i = 2 if der[1] < 0x80 else 3
    out = b""
    for _ in range(2):
        assert der[i] == 0x02
        n = der[i + 1]
        val = der[i + 2 : i + 2 + n].lstrip(b"\x00")
        out += val.rjust(32, b"\x00")
        i += 2 + n
    return out


def token() -> str:
    key_id, issuer, key_path = credentials()
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    payload = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{header}.{payload}".encode()
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
        input=signing_input, capture_output=True, check=True,
    ).stdout
    return f"{header}.{payload}.{b64url(der_to_raw(der))}"


_token = None


def request(method: str, path: str, body=None, **params):
    global _token
    _token = _token or token()
    url = path if path.startswith("http") else f"{API}{path}"
    if params:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
    headers = {"Authorization": f"Bearer {_token}"}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {url}: HTTP {e.code}\n{e.read().decode()[:800]}")


def get(path: str, **params):
    return request("GET", path, **params)


def bundle_id() -> str:
    text = (ROOT / "Config" / "Base.xcconfig").read_text()
    return re.search(r"^PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(\S+)", text, re.M).group(1)


def product_id() -> str:
    apps = get("/apps", **{"filter[bundleId]": bundle_id(), "fields[apps]": "bundleId"})["data"]
    if not apps:
        sys.exit(f"no App Store Connect app with bundle id {bundle_id()}")
    return get(f"/apps/{apps[0]['id']}/ciProduct", **{"fields[ciProducts]": "name"})["data"]["id"]


def build_runs(limit: int):
    return get(
        f"/ciProducts/{product_id()}/buildRuns",
        sort="-number", limit=limit,
        **{"fields[ciBuildRuns]": "number,executionProgress,completionStatus,startReason,sourceCommit,createdDate,pullRequest"},
    )["data"]


def find_run(number: int):
    for run in build_runs(50):
        if run["attributes"]["number"] == number:
            return run
    sys.exit(f"no build run number {number} in the last 50")


def artifacts_for(run):
    actions = get(f"/ciBuildRuns/{run['id']}/actions", **{"fields[ciBuildActions]": "name,actionType"})["data"]
    for action in actions:
        for artifact in get(f"/ciBuildActions/{action['id']}/artifacts")["data"]:
            yield action["attributes"], artifact["attributes"]


def workflow_id(name: str) -> str:
    for w in get(f"/ciProducts/{product_id()}/workflows", **{"fields[ciWorkflows]": "name"})["data"]:
        if w["attributes"]["name"].lower() == name.lower():
            return w["id"]
    sys.exit(f"no workflow named {name}")


def cmd_start(argv):
    if len(argv) != 3 or argv[1] not in ("pr", "branch"):
        sys.exit("usage: start <workflow-name> pr <number>|branch <name>")
    name, kind, ref = argv
    repo = get(f"/ciProducts/{product_id()}/primaryRepositories")["data"][0]["id"]
    relationships = {"workflow": {"data": {"type": "ciWorkflows", "id": workflow_id(name)}}}
    if kind == "pr":
        pulls = get(f"/scmRepositories/{repo}/pullRequests", limit=50)["data"]
        match = [p for p in pulls if str(p["attributes"].get("number")) == ref]
        if not match:
            sys.exit(f"no open pull request #{ref} known to Xcode Cloud")
        relationships["pullRequest"] = {"data": {"type": "scmPullRequests", "id": match[0]["id"]}}
    else:
        refs = get(f"/scmRepositories/{repo}/gitReferences", limit=200)["data"]
        match = [r for r in refs if r["attributes"].get("name") == ref and r["attributes"].get("kind") == "BRANCH"]
        if not match:
            sys.exit(f"no branch named {ref} known to Xcode Cloud")
        relationships["sourceBranchOrTag"] = {"data": {"type": "scmGitReferences", "id": match[0]["id"]}}
    run = request("POST", "/ciBuildRuns", {"data": {"type": "ciBuildRuns", "relationships": relationships}})
    print(f"started build #{run['data']['attributes']['number']}")


def cmd_builds(argv):
    limit = int(argv[0]) if argv else 10
    for run in build_runs(limit):
        a = run["attributes"]
        commit = a.get("sourceCommit") or {}
        status = a.get("completionStatus") or a.get("executionProgress")
        print(f"#{a['number']:<4} {status:<10} {a['startReason']:<28} {commit.get('commitSha', '')[:7]}  {commit.get('message', '').splitlines()[0][:60] if commit.get('message') else ''}")


def cmd_artifacts(argv):
    run = find_run(int(argv[0]))
    for action, artifact in artifacts_for(run):
        print(f"{action['name']:<14} {artifact['fileSize'] / 1e6:6.1f} MB  {artifact['fileName']}")


def cmd_download(argv):
    number = int(argv[0])
    needles = [s.lower() for s in argv[1:]]
    run = find_run(number)
    out = ROOT / ".build" / "xcode-cloud" / str(number)
    out.mkdir(parents=True, exist_ok=True)
    for _, artifact in artifacts_for(run):
        name = artifact["fileName"]
        if needles and not any(n in name.lower() for n in needles):
            continue
        target = out / name
        with urllib.request.urlopen(artifact["downloadUrl"]) as r, open(target, "wb") as f:
            f.write(r.read())
        if target.suffix == ".zip":
            # The system unzip keeps the symlinks inside .xctestproducts; Python's zipfile drops them.
            subprocess.run(["unzip", "-qo", str(target), "-d", str(out)], check=True)
            target.unlink()
            print(out / target.stem)
        else:
            print(target)


if __name__ == "__main__":
    commands = {"builds": cmd_builds, "artifacts": cmd_artifacts, "download": cmd_download, "start": cmd_start}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        print(__doc__, file=sys.stderr)
        sys.exit(64)
    commands[sys.argv[1]](sys.argv[2:])
