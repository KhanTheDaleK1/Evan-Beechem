#!/bin/bash
# ==========================================
# Script: beechem_point_to_workersdev.sh
# Purpose:
#   Point beechem.site OctoPrint card directly
#   at the working workers.dev endpoint instead
#   of /octoprint-api/job (which still 404s).
# ==========================================

set -e

# 0. Load project host pointer
CONFIG_FILE="$HOME/.project_host_target"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Missing $CONFIG_FILE"; exit 1
fi

PROJECT_ROOT="$(head -n 1 "$CONFIG_FILE")"
if [ -z "$PROJECT_ROOT" ] || [ ! -d "$PROJECT_ROOT" ]; then
  echo "ERROR: PROJECT_ROOT '$PROJECT_ROOT' is invalid."; exit 1
fi

SITE_DIR="$PROJECT_ROOT/Evan-Beechem"
HTML_FILE="$SITE_DIR/projects.html"

echo "PROJECT_ROOT : $PROJECT_ROOT"
echo "SITE_DIR     : $SITE_DIR"
echo "HTML_FILE    : $HTML_FILE"
echo

if [ ! -f "$HTML_FILE" ]; then
  echo "ERROR: $HTML_FILE not found."; exit 1
fi

# 1) Backup projects.html
TS="$(date +%s)"
cp "$HTML_FILE" "$HTML_FILE.bak-workersdev-$TS"
echo "[✔] Backup -> $HTML_FILE.bak-workersdev-$TS"
echo

# 2) Patch BEECH_OCTO_URL to hit workers.dev directly
python3 - "$HTML_FILE" << 'PY'
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])
html = path.read_text()

new_url = 'const BEECH_OCTO_URL = "https://octoprint-proxy.evan-t-beechem.workers.dev/octoprint-api/job";'

new_html, n = re.subn(
    r'const\s+BEECH_OCTO_URL\s*=\s*["\'][^"\']*["\'];',
    new_url,
    html,
    count=1,
    flags=re.I,
)

if n == 0:
    # If it somehow doesn't exist, append definition near end
    lower = html.lower()
    idx = lower.rfind("</body>")
    if idx == -1:
        html = html + "\n    <script>\n      " + new_url + "\n    </script>\n"
    else:
        html = html[:idx] + "\n    <script>\n      " + new_url + "\n    </script>\n" + html[idx:]
    print("[PY] Inserted BEECH_OCTO_URL definition.")
else:
    html = new_html
    print("[PY] Updated existing BEECH_OCTO_URL to workers.dev URL.")

path.write_text(html)
print("[PY] Write-back complete.")
PY

echo
echo "=== VERIFICATION COMMANDS ==================================="
echo "1) Check URL constant in projects.html:"
echo "     grep -n 'BEECH_OCTO_URL' '$HTML_FILE'"
echo
echo "2) Then from $SITE_DIR:"
echo "     git diff"
echo "     git add projects.html"
echo "     git commit -m 'Point OctoPrint card at workers.dev proxy'"
echo "     git push"
echo
echo "3) In browser:"
echo "   - Hard refresh https://beechem.site/projects.html (Ctrl+F5)"
echo "   - DevTools → Network: you should see"
echo "       https://octoprint-proxy.evan-t-beechem.workers.dev/octoprint-api/job"
echo "     with status 200, and the OCTOPRINT card should show"
echo "       STATUS: PRINTING (xx%)"
echo "       File: CE3E3V2_Pick_holder.gcode"
echo "============================================================="
