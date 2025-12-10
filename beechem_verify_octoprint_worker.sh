#!/bin/bash
# ==========================================
# Script: beechem_verify_octoprint_worker.sh
# Purpose:
#   1) Sanity-check local Beechem config.
#   2) Dump worker source so you can paste it
#      into Cloudflare.
#   3) Remind you of the Cloudflare changes
#      needed to stop the 404.
# ==========================================

set -e

# 0. Load project host pointer
CONFIG_FILE="$HOME/.project_host_target"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Missing $CONFIG_FILE (project host pointer)."
  exit 1
fi

PROJECT_ROOT="$(head -n 1 "$CONFIG_FILE")"
if [ -z "$PROJECT_ROOT" ] || [ ! -d "$PROJECT_ROOT" ]; then
  echo "ERROR: PROJECT_ROOT '$PROJECT_ROOT' is invalid."
  exit 1
fi

SITE_DIR="$PROJECT_ROOT/Evan-Beechem"
HTML_FILE="$SITE_DIR/projects.html"
WORKER_FILE="$SITE_DIR/worker_config/octoprint_proxy_worker.js"

echo "=== PATHS ========================================================"
echo "PROJECT_ROOT : $PROJECT_ROOT"
echo "SITE_DIR     : $SITE_DIR"
echo "HTML_FILE    : $HTML_FILE"
echo "WORKER_FILE  : $WORKER_FILE"
echo "=================================================================="
echo

# 1) Basic checks
if [ ! -f "$HTML_FILE" ]; then
  echo "ERROR: $HTML_FILE not found."; exit 1
fi
if [ ! -f "$WORKER_FILE" ]; then
  echo "ERROR: $WORKER_FILE not found."; exit 1
fi

echo "=== CHECKING BEECH_OCTO_URL IN projects.html ====================="
grep -n "BEECH_OCTO_URL" "$HTML_FILE" || echo "(no BEECH_OCTO_URL line found)"
echo

echo "=== WORKER FILE PERMISSIONS & HEAD ==============================="
ls -l "$WORKER_FILE"
echo
echo "--- First 60 lines of worker (copy this into Cloudflare) ---------"
sed -n '1,60p' "$WORKER_FILE"
echo "------------------------------------------------------------------"
echo

echo "=== NEXT STEPS (MANUAL CLOUDFLARE CHANGES) ======================="
cat <<'EOF'
1) In Cloudflare DNS for beechem.site, set the CNAME "beechem.site"
   to PROXIED (orange cloud), not "DNS only".  Right now in your
   screenshot it's grey, so GitHub Pages is being hit directly and
   Workers never run.

2) In Cloudflare → Workers & Pages → Workers:
   - Open the OctoPrint worker.
   - Replace the code with the JS printed above.
   - Ensure secret:
       Name:  OCTO_API_KEY
       Value: (your OctoPrint API key)
     is set under Variables / Secrets.

3) In the same Worker under Triggers / Routes add:
       beechem.site/octoprint-api/*
   (no "https://", include the trailing "/*"), and attach it to this
   worker.

4) Test in a browser:
     https://beechem.site/octoprint-api/job
   You should now see JSON, not the GitHub 404 page.

5) Finally, hard-refresh:
     https://beechem.site/projects.html
   and watch /octoprint-api/job in DevTools → Network.
EOF
echo "=================================================================="
