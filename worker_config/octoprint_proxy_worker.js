// worker_config/octoprint_proxy_worker.js
// Universal Proxy: OctoPrint, Webcam, Flight Data, FlightAware
// Author: Evan Beechem (via Gemini)

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const corsHeaders = {
      "Access-Control-Allow-Origin": "https://beechem.site",
      "Access-Control-Allow-Methods": "GET, OPTIONS",
      "Access-Control-Allow-Headers": "X-Requested-With, Content-Type, X-Api-Key",
      "Vary": "Origin"
    };

    // Handle Preflight
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    let targetUrl = "";
    const baseOcto = "https://octoprint.beechem.site";
    
    // Default Headers (for OctoPrint routes)
    let headers = {
        "X-Api-Key": env.OCTO_API_KEY,
        "User-Agent": "Beechem-Octoprint-Worker"
    };

    // --- ROUTING LOGIC ---

    // 1. OctoPrint Job Status
    if (url.pathname === "/octoprint-api/job") {
      targetUrl = baseOcto + "/api/job";
    } 
    // 2. OctoPrint Settings (for Webcam config)
    else if (url.pathname === "/octoprint-api/settings") {
      targetUrl = baseOcto + "/api/settings";
    }
    // 3. OctoPrint Webcam (Stream or Snapshot)
    else if (url.pathname === "/octoprint-api/webcam") {
      // Forward 'action' param (e.g., ?action=snapshot)
      const queryString = url.search || "?action=stream";
      targetUrl = baseOcto + "/webcam/" + queryString;
    }
    // 4. Local Flight Data (tar1090)
    else if (url.pathname === "/octoprint-api/flight-data") {
        targetUrl = "https://ops.beechem.site/tar1090/data/aircraft.json";
        // No special headers needed for public endpoint, but keeping User-Agent is fine.
    }
    // 5. FlightAware API (Remote)
    else if (url.pathname === "/octoprint-api/flightaware/kaex") {
        targetUrl = "https://aeroapi.flightaware.com/aeroapi/airports/KAEX/flights";
        // Override headers for FlightAware
        headers = {
            "x-apikey": env.FLIGHTAWARE_API_KEY, 
            "User-Agent": "Beechem-Worker"
        };
    }
    // 6. 404 Not Found
    else {
      return new Response("Proxy Route Not Found", { status: 404, headers: corsHeaders });
    }

    // --- FETCH & RESPONSE ---
    try {
      const upstreamResp = await fetch(targetUrl, { headers: headers });

      // Create new response based on upstream
      const resp = new Response(upstreamResp.body, upstreamResp);

      // Apply CORS headers
      Object.keys(corsHeaders).forEach(key => {
        resp.headers.set(key, corsHeaders[key]);
      });

      // Preserve Content-Type (Critical for MJPEG and Images)
      if (!resp.headers.has("Content-Type") && upstreamResp.headers.has("Content-Type")) {
        resp.headers.set("Content-Type", upstreamResp.headers.get("Content-Type"));
      }

      return resp;
    } catch (err) {
      return new Response("Worker Upstream Error: " + err.message, { status: 502, headers: corsHeaders });
    }
  },
};