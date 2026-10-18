#!/usr/bin/env python3
"""Fail Release builds with missing client config or a server credential."""
import base64
import json
import os
import sys
from urllib.parse import urlparse

if os.environ.get("CONFIGURATION") != "Release":
    sys.exit(0)

url = urlparse(os.environ.get("SUPABASE_URL", ""))
key = os.environ.get("SUPABASE_ANON_KEY", "")
valid = url.scheme == "https" and bool(url.hostname) and not url.username and not url.password
public = key.startswith("sb_publishable_")
if key.count(".") == 2:
    try:
        part = key.split(".")[1]
        claims = json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))
        public = claims.get("role") == "anon"
    except (ValueError, TypeError):
        public = False
if not valid or not public:
    print("error: FreshVision Release needs the approved HTTPS backend URL and public client key in Config/Secrets.xcconfig. Provider and service keys must stay server-side.")
    sys.exit(1)
