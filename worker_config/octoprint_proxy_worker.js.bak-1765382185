// worker_config/octoprint_proxy_worker.js

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.pathname !== "/octoprint-api/job") {
      return new Response("Not found", { status: 404 });
    }

    const targetUrl = "https://octoprint.beechem.site/api/job";

    const upstreamResp = await fetch(targetUrl, {
      headers: {
        "X-Api-Key": env.OCTO_API_KEY,
        "User-Agent": "Beechem-Octoprint-Worker",
      },
    });

    const resp = new Response(upstreamResp.body, upstreamResp);

    resp.headers.set("Access-Control-Allow-Origin", "https://beechem.site");
    resp.headers.set("Access-Control-Allow-Methods", "GET, OPTIONS");
    resp.headers.set("Access-Control-Allow-Headers", "X-Requested-With, Content-Type");
    resp.headers.set("Vary", "Origin");

    if (!resp.headers.get("Content-Type")) {
      resp.headers.set("Content-Type", "application/json");
    }

    return resp;
  },
};
