#!/bin/bash
# ==========================================
# Script: beechem_rewrite_octoprint_proxy.sh
# Purpose:
#   1) Force projects.html to use /octoprint-api/job
#   2) Rewrite Cloudflare worker source to a clean,
#      known-good OctoPrint proxy with proper CORS.
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
WORKER_DIR="$SITE_DIR/worker_config"
WORKER_FILE="$WORKER_DIR/octoprint_proxy_worker.js"

echo "=== PATHS ========================================================"
echo "PROJECT_ROOT : $PROJECT_ROOT"
echo "SITE_DIR     : $SITE_DIR"
echo "HTML_FILE    : $HTML_FILE"
echo "WORKER_FILE  : $WORKER_FILE"
echo "=================================================================="
echo

# 1) Validate files exist
if [ ! -f "$HTML_FILE" ]; then
  echo "ERROR: $HTML_FILE not found."
  exit 1
fi

mkdir -p "$WORKER_DIR"

if [ ! -f "$WORKER_FILE" ]; then
  echo "NOTE: $WORKER_FILE did not exist; it will be created fresh."
fi

# 2) Backups
TS="$(date +%s)"
cp "$HTML_FILE" "$HTML_FILE.bak-worker-$TS"
echo "[✔] Backup -> $HTML_FILE.bak-worker-$TS"

if [ -f "$WORKER_FILE" ]; then
  cp "$WORKER_FILE" "$WORKER_FILE.bak-$TS"
  echo "[✔] Backup -> $WORKER_FILE.bak-$TS"
fi
echo

# 3) Force BEECH_OCTO_URL to /octoprint-api/job in projects.html
echo "=== PATCHING projects.html ======================================"
python3 - "$HTML_FILE" << 'PY'
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])
html = path.read_text()

# Replace any existing BEECH_OCTO_URL assignment
new_html, n = re.subn(
    r'const\s+BEECH_OCTO_URL\s*=\s*["\'][^"\
]*["\'];',
    'const BEECH_OCTO_URL = "/octoprint-api/job";',
    html,
    count=1,
    flags=re.I,
)

if n == 0:
    # If not present, inject a sane default near beechemUpdateOctoprint
    lower = html.lower()
    idx = lower.find("beechemupdateoctoprint")
    if idx != -1:
        insert_at = html.rfind("\n", 0, idx)
        if insert_at == -1:
            insert_at = idx
        html = (
            html[:insert_at]
            + '\nconst BEECH_OCTO_URL = "/octoprint-api/job";\n'
            + html[insert_at:]
        )
        print("[PY] Inserted BEECH_OCTO_URL definition near beechemUpdateOctoprint().")
    else:
        # As a last resort, prepend to the file
        html = 'const BEECH_OCTO_URL = "/octoprint-api/job";\n' + html
        print("[PY] Prepended BEECH_OCTO_URL definition to file.")
else:
    html = new_html
    print("[PY] Updated existing BEECH_OCTO_URL definition.")

path.write_text(html)
print("[PY] projects.html write-back complete.")
PY
echo

# 4) Rewrite worker source to a known-good proxy
echo "=== REWRITING Cloudflare Worker SOURCE =========================="
cat > "$WORKER_FILE" << 'JS'
// worker_config/octoprint_proxy_worker.js
// Universal Proxy: OctoPrint, Webcam, Flight Data, FlightAware
// Format: Service Worker (Legacy/Universal)

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request));
});

async function handleRequest(request) {
  const url = new URL(request.url);
  
  // 1. CORS Configuration
  const corsHeaders = {
    "Access-Control-Allow-Origin": "https://beechem.site",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "X-Requested-With, Content-Type, X-Api-Key",
    "Vary": "Origin"
  };

  // 2. Handle Preflight (OPTIONS)
  if (request.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // 3. Environment Variables (Global variables in Legacy format)
  // Ensure OCTO_API_KEY and FLIGHTAWARE_API_KEY are set in Settings -> Variables
  const OCTO_KEY = typeof OCTO_API_KEY !== 'undefined' ? OCTO_API_KEY : "";
  const FLIGHT_KEY = typeof FLIGHTAWARE_API_KEY !== 'undefined' ? FLIGHTAWARE_API_KEY : "";

  let targetUrl = "";
  const baseOcto = "https://octoprint.beechem.site";
  
  // Default Headers
  let headers = {
    "X-Api-Key": OCTO_KEY,
    "User-Agent": "Beechem-Octoprint-Worker"
  };

  // --- ROUTING LOGIC ---

  // 1. OctoPrint Job Status
  if (url.pathname === "/octoprint-api/job") {
    targetUrl = baseOcto + "/api/job";
  } 
  // 2. OctoPrint Settings
  else if (url.pathname === "/octoprint-api/settings") {
    targetUrl = baseOcto + "/api/settings";
  }
  // 3. OctoPrint Webcam
  else if (url.pathname === "/octoprint-api/webcam") {
    const queryString = url.search || "?action=stream";
    targetUrl = baseOcto + "/webcam/" + queryString;
  }
  // 4. Local Flight Data (tar1090)
  else if (url.pathname === "/octoprint-api/flight-data") {
    targetUrl = "https://ops.beechem.site/tar1090/data/aircraft.json";
  }
  // 5. FlightAware API (Remote)
  else if (url.pathname === "/octoprint-api/flightaware/kaex") {
    targetUrl = "https://aeroapi.flightaware.com/aeroapi/airports/KAEX/flights";
    headers = {
      "x-apikey": FLIGHT_KEY, 
      "User-Agent": "Beechem-Worker"
    };
  }
  // 6. 404 Not Found
  else {
    return new Response("Proxy Route Not Found: " + url.pathname, { status: 404, headers: corsHeaders });
  }

  // --- FETCH & RESPONSE ---
  try {
    const upstreamResp = await fetch(targetUrl, { headers: headers });

    // Clone response
    const resp = new Response(upstreamResp.body, upstreamResp);

    // Apply CORS
    Object.keys(corsHeaders).forEach(key => {
      resp.headers.set(key, corsHeaders[key]);
    });

    // Preserve Content-Type
    if (!resp.headers.has("Content-Type") && upstreamResp.headers.has("Content-Type")) {
      resp.headers.set("Content-Type", upstreamResp.headers.get("Content-Type"));
    }

    return resp;
  } catch (err) {
    return new Response("Worker Upstream Error: " + err.message, { status: 502, headers: corsHeaders });
  }
}
JS

echo "[✔] Worker source rewritten -> $WORKER_FILE"
echo

# 5) Verification hints
echo "=== VERIFICATION COMMANDS ======================================"
echo "1) Check URL constant in projects.html:"
echo "     grep -n 'BEECH_OCTO_URL' '$HTML_FILE'"
echo ""

echo "2) Check worker source on disk:"
echo "     sed -n '1,80p' '$WORKER_FILE'"
echo ""

echo "3) Then in Cloudflare Worker UI:"
echo "   - Paste the contents of:"
echo "       $WORKER_FILE"
echo "     into the Worker code editor."
echo "   - Ensure secret OCTO_API_KEY is set."
echo "   - Ensure route:"
echo "       https://beechem.site/octoprint-api/*"
echo "     points to this Worker."
echo "=================================================================="
