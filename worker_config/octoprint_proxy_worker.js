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
