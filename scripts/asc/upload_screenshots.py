#!/usr/bin/env python3
"""App Store のスクリーンショットセットを、ローカルの PNG で丸ごと差し替える。

asc-mcp の screenshots_upload_batch が予約の応答を読めず「AWAITING_UPLOAD」の空枠を残すことがあるため、
ASC API を直接叩く（予約 → uploadOperations に PUT → md5 を付けて確定）。

使い方: python3 scripts/asc/upload_screenshots.py <screenshot_set_id> <png...>
鍵は asc-mcp と同じ App Manager キー（env の ASC_KEY_ID / ASC_ISSUER_ID で上書き可）と
~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8。
セット内の既存スクショ（空枠を含む）は先に消す。
"""
import hashlib, json, os, sys, time, urllib.request, pathlib
import jwt

ROOT = pathlib.Path(__file__).resolve().parents[2]
API = "https://api.appstoreconnect.apple.com/v1"

def token():
    # メタデータ操作には App Manager 権限が要る（asc-mcp と同じキー。~/.claude/docs/accounts.md 参照）。
    key_id = os.environ.get("ASC_KEY_ID", "L7Z92ZDTQP")
    issuer = os.environ.get("ASC_ISSUER_ID", "ee0ccd93-0a59-4104-95ee-a4989d09fb5a")
    key = (pathlib.Path.home() / f".appstoreconnect/private_keys/AuthKey_{key_id}.p8").read_text()
    now = int(time.time())
    return jwt.encode({"iss": issuer, "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})

def call(method, url, body=None, tok=None, headers=None, raw=None):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method)
    if tok:
        req.add_header("Authorization", f"Bearer {tok}")
        req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    with urllib.request.urlopen(req) as res:
        text = res.read()
        return json.loads(text) if text else None

def main():
    set_id, files = sys.argv[1], sys.argv[2:]
    tok = token()
    existing = call("GET", f"{API}/appScreenshotSets/{set_id}/appScreenshots?limit=200", tok=tok)["data"]
    for shot in existing:
        call("DELETE", f"{API}/appScreenshots/{shot['id']}", tok=tok)
    print(f"deleted {len(existing)}")
    for path in files:
        blob = pathlib.Path(path).read_bytes()
        name = os.path.basename(path)
        res = call("POST", f"{API}/appScreenshots", tok=tok, body={"data": {
            "type": "appScreenshots",
            "attributes": {"fileName": name, "fileSize": len(blob)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
        }})
        shot = res["data"]
        for op in shot["attributes"]["uploadOperations"]:
            part = blob[op["offset"]:op["offset"] + op["length"]]
            headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            call(op["method"], op["url"], raw=part, headers=headers)
        call("PATCH", f"{API}/appScreenshots/{shot['id']}", tok=tok, body={"data": {
            "type": "appScreenshots", "id": shot["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(blob).hexdigest()},
        }})
        print(f"uploaded {name}")

if __name__ == "__main__":
    main()
