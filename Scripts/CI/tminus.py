#!/usr/bin/env python3
"""Release notes for TestFlight builds, from T-Minus (https://t-min.sams.works).

Used by .github/workflows/testflight.yml. Merged PRs queue up their "For testers" bullets in T-Minus
as pending notes. This script reads them before the build, so they ship inside the app
(Shared/Resources/CouchfinWhatsNew.json, shown in "What's new") and as TestFlight's "What to Test",
then cuts the release in T-Minus once the upload worked, which takes the pending notes.

Every command is best effort: without TMINUS_KEY (or when T-Minus or App Store Connect can't be
reached) it prints a warning and exits 0, so the build never fails because of release notes.

  tminus.py next --out FILE --text-out FILE --version V --build B   pending notes -> the app's JSON
  tminus.py cut --version "V (B)" --commit SHA --url URL             record the release, take the notes
  tminus.py what-to-test --notes FILE --bundle-id ID --version V --build B

Env: TMINUS_KEY (the project's full ingest key), TMINUS_URL (optional),
     KEY_ID / ISSUER_ID / KEY_CONTENTS (App Store Connect API key, for what-to-test).
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

TMINUS_URL = (os.environ.get("TMINUS_URL") or "https://t-min.sams.works").rstrip("/")
TMINUS_KEY = os.environ.get("TMINUS_KEY", "").strip()
ASC_URL = "https://api.appstoreconnect.apple.com"
# TestFlight allows 4000 characters per locale.
WHAT_TO_TEST_LIMIT = 4000


def warn(title, message):
    print(f"::warning title={title}::{message}")


def summary(text):
    print(text)
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(text + "\n")


def describe(err):
    detail = err.read().decode(errors="replace") if isinstance(err, urllib.error.HTTPError) else ""
    return f"{err} {detail}".strip()


def request(method, url, headers=None, body=None, timeout=30):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=timeout) as res:
        raw = res.read()
        return json.loads(raw) if raw else None


def render(notes):
    """The same plain text T-Minus renders: "New" and "Please try" blocks."""
    blocks = []
    for title, kind in (("New", "new"), ("Please try", "test")):
        lines = [f"- {n['text']}" for n in notes if n.get("kind") == kind]
        if lines:
            blocks.append("\n".join([title, *lines]))
    return "\n\n".join(blocks)


def fit(text, limit=WHAT_TO_TEST_LIMIT):
    """Cuts at a line break so a bullet isn't left half-written."""
    text = text.strip()
    if len(text) <= limit:
        return text
    cut = text[: limit - 2]
    last_break = cut.rfind("\n")
    return (cut[:last_break] if last_break > 0 else cut) + "\n…"


# MARK: - next


def cmd_next(args):
    notes = []
    if not TMINUS_KEY:
        print("TMINUS_KEY is not set: building without release notes.")
    else:
        try:
            pending = request("GET", f"{TMINUS_URL}/ingest/v1/releases/next", {"Authorization": f"Bearer {TMINUS_KEY}"})
            notes = [
                {"kind": "test" if n.get("kind") == "test" else "new", "text": n["text"].strip()}
                for n in pending.get("notes", [])
                if (n.get("text") or "").strip()
            ]
        except Exception as err:  # never fail the build over notes
            warn("T-Minus unreachable", f"Building without release notes. {describe(err)}")

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump({"version": args.version, "build": args.build, "notes": notes}, f, indent=2, ensure_ascii=False)
        f.write("\n")

    text = render(notes)
    if args.text_out:
        with open(args.text_out, "w", encoding="utf-8") as f:
            f.write(fit(text))

    summary(f"### What's new in {args.version} ({args.build})")
    summary(f"\n```\n{text}\n```\n" if text else "\nNo pending notes for testers.\n")


# MARK: - cut


def cmd_cut(args):
    if not TMINUS_KEY:
        print("TMINUS_KEY is not set: no release recorded in T-Minus.")
        return

    body = {"version": args.version, "commit": args.commit, "includePending": True}
    if args.url:
        body["url"] = args.url
    try:
        request("POST", f"{TMINUS_URL}/ingest/v1/releases", {"Authorization": f"Bearer {TMINUS_KEY}"}, body)
        summary(f"Recorded release `{args.version}` in T-Minus.")
    except Exception as err:
        warn("T-Minus release not recorded", describe(err))


# MARK: - what-to-test (App Store Connect API)


def der_to_raw(der):
    """ECDSA signature from openssl (DER) to the JOSE form: r || s, 32 bytes each."""

    def read_int(buf, i):
        if buf[i] != 0x02:
            raise ValueError("Unexpected signature format")
        length = buf[i + 1]
        value = buf[i + 2 : i + 2 + length]
        return value.lstrip(b"\x00").rjust(32, b"\x00"), i + 2 + length

    i = 2 if der[1] < 0x80 else 3
    r, i = read_int(der, i)
    s, _ = read_int(der, i)
    return r + s


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def asc_token(key_id, issuer_id, key_path):
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    payload = b64url(
        json.dumps({"iss": issuer_id, "iat": now, "exp": now + 1150, "aud": "appstoreconnect-v1"}).encode()
    )
    signing_input = f"{header}.{payload}".encode()
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input,
        capture_output=True,
        check=True,
    ).stdout
    return f"{header}.{payload}.{b64url(der_to_raw(der))}"


def write_key(contents, directory):
    """The .p8 as-is or base64-encoded, like the archive step accepts it."""
    path = os.path.join(directory, "AuthKey.p8")
    if "BEGIN PRIVATE KEY" in contents:
        data = contents.strip().encode() + b"\n"
    else:
        data = base64.b64decode("".join(contents.split()))
    with open(path, "wb") as f:
        f.write(data)
    return path


def cmd_what_to_test(args):
    try:
        with open(args.notes, encoding="utf-8") as f:
            text = fit(f.read())
    except OSError:
        text = ""
    if not text:
        print("No notes: leaving What to Test empty.")
        return

    key_id = "".join(os.environ.get("KEY_ID", "").split())
    issuer_id = "".join(os.environ.get("ISSUER_ID", "").split())
    contents = os.environ.get("KEY_CONTENTS", "")
    if not (key_id and issuer_id and contents.strip()):
        summary(
            "\nSetting What to Test needs the APP_STORE_* secrets (App Store Connect API key). "
            "Paste the notes above into TestFlight by hand."
        )
        return

    with tempfile.TemporaryDirectory() as tmp:
        try:
            key_path = write_key(contents, tmp)
            set_what_to_test(text, args, lambda: asc_token(key_id, issuer_id, key_path))
        except Exception as err:
            warn("What to Test not set", describe(err))


def set_what_to_test(text, args, token):
    def asc(method, path, body=None):
        return request(method, f"{ASC_URL}{path}", {"Authorization": f"Bearer {token()}"}, body)

    apps = asc("GET", "/v1/apps?" + urllib.parse.urlencode({"filter[bundleId]": args.bundle_id}))["data"]
    if not apps:
        raise RuntimeError(f"No App Store Connect app for {args.bundle_id}")

    query = urllib.parse.urlencode(
        {
            "filter[app]": apps[0]["id"],
            "filter[version]": args.build,
            "filter[preReleaseVersion.version]": args.version,
            "limit": "10",
        }
    )

    # Uploaded builds show up after a few minutes and finish processing a while later.
    deadline = time.time() + args.timeout * 60
    while True:
        builds = asc("GET", f"/v1/builds?{query}")["data"]
        processing = [b for b in builds if b["attributes"].get("processingState") == "PROCESSING"]
        if len(builds) >= args.expected and not processing:
            break
        if time.time() > deadline:
            if not builds:
                raise RuntimeError(f"{args.version} ({args.build}) didn't show up in App Store Connect in time")
            break
        time.sleep(30)

    for build in builds:
        localizations = asc("GET", f"/v1/builds/{build['id']}/betaBuildLocalizations")["data"]
        existing = next((loc for loc in localizations if loc["attributes"].get("locale") == "en-US"), None)
        if existing:
            asc(
                "PATCH",
                f"/v1/betaBuildLocalizations/{existing['id']}",
                {"data": {"type": "betaBuildLocalizations", "id": existing["id"], "attributes": {"whatsNew": text}}},
            )
        else:
            asc(
                "POST",
                "/v1/betaBuildLocalizations",
                {
                    "data": {
                        "type": "betaBuildLocalizations",
                        "attributes": {"locale": "en-US", "whatsNew": text},
                        "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}},
                    }
                },
            )

    summary(f"Set What to Test on {len(builds)} build(s) of {args.version} ({args.build}).")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("next")
    p.add_argument("--out", required=True)
    p.add_argument("--text-out")
    p.add_argument("--version", required=True)
    p.add_argument("--build", required=True)
    p.set_defaults(func=cmd_next)

    p = sub.add_parser("cut")
    p.add_argument("--version", required=True)
    p.add_argument("--commit", required=True)
    p.add_argument("--url")
    p.set_defaults(func=cmd_cut)

    p = sub.add_parser("what-to-test")
    p.add_argument("--notes", required=True)
    p.add_argument("--bundle-id", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--build", required=True)
    p.add_argument("--expected", type=int, default=1, help="builds to wait for (one per platform)")
    p.add_argument("--timeout", type=int, default=30, help="minutes to wait for processing")
    p.set_defaults(func=cmd_what_to_test)

    args = parser.parse_args()
    args.func(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
