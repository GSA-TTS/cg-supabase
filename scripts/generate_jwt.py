#!/usr/bin/env python3
"""Generate a Supabase JWT (HS256) for use as anon_key or service_role_key.

Called by Terraform's data "external" resource.
Reads JSON from stdin: {"secret": "...", "role": "anon|service_role"}
Writes JSON to stdout: {"jwt": "eyJ..."}

Uses only Python standard library — no pip dependencies.
"""
import base64
import hashlib
import hmac
import json
import sys


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def main():
    input_data = json.load(sys.stdin)
    secret = input_data["secret"]
    role = input_data["role"]
    iss = input_data.get("iss", "supabase")
    iat = int(input_data.get("iat", "1729900800"))   # 2024-10-26
    exp = int(input_data.get("exp", "1893456000"))    # 2030-01-01

    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64url(json.dumps(
        {"role": role, "iss": iss, "iat": iat, "exp": exp},
        separators=(",", ":"),
    ).encode())

    signing_input = f"{header}.{payload}"
    sig = hmac.new(secret.encode(), signing_input.encode(), hashlib.sha256).digest()

    json.dump({"jwt": f"{signing_input}.{b64url(sig)}"}, sys.stdout)


if __name__ == "__main__":
    main()
