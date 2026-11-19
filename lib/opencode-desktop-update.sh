#!/usr/bin/env bash
# Update OpenCode Desktop from opencode.ai (Fedora/RPM path).
# Used by fedorapi (installed to /usr/local/bin/opencode-desktop-update) and
# by Topgrade as a custom command. The in-app updater is broken on Fedora.
set -euo pipefail

API_URL="https://opencode.ai/update/api/latest/desktop/opencode/"
RPM_NAME="opencode-desktop-linux-x86_64.rpm"
TMPDIR="/tmp/opencode-desktop-update"
mkdir -p "$TMPDIR"

read -r LATEST_URL LATEST_SHA LATEST_VER < <(python3 - "$API_URL" "$RPM_NAME" <<'PY'
import json, sys, urllib.request
api, rpm_name = sys.argv[1], sys.argv[2]
req = urllib.request.Request(api, headers={"User-Agent": "opencode-desktop-update/1"})
with urllib.request.urlopen(req) as r:
    data = json.load(r)
version = data["version"]
files = data["metadata"]["files"]
url = files[rpm_name]["url"]
sha = files[rpm_name]["sha256"]
print(url, sha, version)
PY
)

echo "Latest OpenCode Desktop: $LATEST_VER"
echo "RPM URL: $LATEST_URL"

INSTALLED=""
if rpm -q opencode >/dev/null 2>&1; then
    INSTALLED="$(rpm -q --qf '%{VERSION}' opencode)"
fi
echo "Installed: ${INSTALLED:-none}"

if [[ -n "$INSTALLED" && "$INSTALLED" == "$LATEST_VER" ]]; then
    echo "Already up to date."
    exit 0
fi

RPM_FILE="$TMPDIR/${RPM_NAME%.rpm}-$LATEST_VER.rpm"

if [[ ! -f "$RPM_FILE" ]]; then
    echo "Downloading $RPM_FILE ..."
    curl -fL -o "$RPM_FILE" "$LATEST_URL"
fi

ACTUAL_SHA="$(sha256sum "$RPM_FILE" | awk '{print $1}')"
if [[ "$ACTUAL_SHA" != "$LATEST_SHA" ]]; then
    echo "Checksum mismatch: expected $LATEST_SHA, got $ACTUAL_SHA" >&2
    rm -f "$RPM_FILE"
    exit 1
fi

echo "Installing $RPM_FILE ..."
if [ "$(id -u)" -eq 0 ]; then
    dnf install -y "$RPM_FILE"
else
    sudo dnf install -y "$RPM_FILE"
fi

echo "OpenCode Desktop updated to $LATEST_VER."