// worker_config/octoprint_proxy_worker.js
// Simplified Stable Proxy: OctoPrint & Local Flight Data
// Format: Service Worker (Legacy)

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request));
});

async function handleRequest(request) {
  const url = new URL(request.url);
  
  // CORS Headers
  const corsHeaders = {
    "Access-Control-Allow-Origin": "https://beechem.site",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "X-Requested-With, Content-Type, X-Api-Key",
    "Vary": "Origin"
  };

  if (request.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // ENV Variables (ensure OCTO_API_KEY is set in Cloudflare)
  const API_KEY = typeof OCTO_API_KEY !== 'undefined' ? OCTO_API_KEY : "";
  const BASE_OCTO = "https://octoprint.beechem.site";

  let targetUrl = "";
  let headers = {
    "X-Api-Key": API_KEY,
    "User-Agent": "Beechem-Worker-Stable"
  };

  // 1. OctoPrint Job (Fixes 'Disconnected' status)
  if (url.pathname === "/octoprint-api/job") {
    targetUrl = BASE_OCTO + "/api/job";
  } 
  // 2. OctoPrint Settings
  else if (url.pathname === "/octoprint-api/settings") {
    targetUrl = BASE_OCTO + "/api/settings";
  }
  // 3. Webcam
  else if (url.pathname === "/octoprint-api/webcam") {
    const qs = url.search || "?action=stream";
    targetUrl = BASE_OCTO + "/webcam/" + qs;
  }
  // 4. Flight Data (Keeps map stats working)
  else if (url.pathname === "/octoprint-api/flight-data") {
    targetUrl = "https://ops.beechem.site/tar1090/data/aircraft.json";
    // No API key needed for this public-ish endpoint
    headers = { "User-Agent": "Beechem-Worker-Stable" };
  }
  else {
    return new Response("Not Found", { status: 404, headers: corsHeaders });
  }

  try {
    const response = await fetch(targetUrl, { headers: headers });
    const newRes = new Response(response.body, response);
    
    // Add CORS
    Object.keys(corsHeaders).forEach(key => newRes.headers.set(key, corsHeaders[key]));
    
    return newRes;
  } catch (e) {
    return new Response("Proxy Error: " + e.message, { status: 502, headers: corsHeaders });
  }
}