import subprocess
import json
import time
import requests
import ssl
import socket
from datetime import datetime

# CONFIG
OUTPUT_FILE = "network_health.json"
HISTORY_FILE = "latency_history.json"
MY_LOC = [31.3113, -92.4451]

# 1. NETWORK TARGETS (Global Backbone)
NET_TARGETS = [
    {"name": "Google DNS (US)", "ip": "8.8.8.8", "coords": [37.40, -122.07]},
    {"name": "AWS Virginia", "ip": "52.94.76.1", "coords": [38.03, -78.50]},
    {"name": "Azure East", "ip": "13.107.21.200", "coords": [36.66, -78.39]},
    {"name": "London Core", "ip": "151.101.192.81", "coords": [51.50, -0.12]},
    {"name": "Tokyo Core", "ip": "172.217.25.14", "coords": [35.67, 139.76]}
]

# 2. SERVICE TARGETS (Infrastructure Only)
# CLEANED: Removed Flight APIs. Only monitoring core web infra.
SVC_TARGETS = [
    {"name": "MY DASHBOARD", "url": "https://beechem.site"},
    {"name": "GITHUB API", "url": "https://api.github.com"}
]

def ping_target(ip):
    try:
        res = subprocess.run(["ping", "-c", "3", "-W", "2", ip], stdout=subprocess.PIPE, text=True)
        if res.returncode == 0:
            stats = res.stdout.splitlines()[-1]
            if "rtt" in stats:
                avg = stats.split('=')[1].split('/')[1]
                return float(avg), "ONLINE"
    except: pass
    return 0, "OFFLINE"

def check_http(url):
    try:
        t_start = time.time()
        res = requests.get(url, timeout=5)
        latency = int((time.time() - t_start) * 1000)
        return res.status_code, latency
    except:
        return 0, 0

def check_ssl_days(url):
    try:
        hostname = url.split("//")[1].split("/")[0]
        context = ssl.create_default_context()
        with socket.create_connection((hostname, 443)) as sock:
            with context.wrap_socket(sock, server_hostname=hostname) as ssock:
                cert = ssock.getpeercert()
                expiry = datetime.strptime(cert['notAfter'], "%b %d %H:%M:%S %Y %Z")
                days_left = (expiry - datetime.now()).days
                return days_left
    except:
        return 0

def load_history():
    try:
        with open(HISTORY_FILE, 'r') as f: return json.load(f)
    except: return {}

def save_history(hist):
    with open(HISTORY_FILE, 'w') as f: json.dump(hist, f)

def run_sentinel():
    print("--- SENTINEL SCAN STARTED ---")
    
    net_results = []
    history = load_history()
    
    for t in NET_TARGETS:
        latency, status = ping_target(t['ip'])
        
        if t['name'] not in history: history[t['name']] = []
        history[t['name']].append(latency)
        if len(history[t['name']]) > 10: history[t['name']].pop(0)
        
        jitter = 0
        if len(history[t['name']]) > 1:
            vals = history[t['name']]
            jitter = sum(abs(vals[i] - vals[i-1]) for i in range(1, len(vals))) / (len(vals)-1)

        print(f"NET: {t['name']:<15} | {status} | {latency}ms")
        
        net_results.append({
            "type": "NET",
            "name": t['name'],
            "origin": MY_LOC,
            "dest": t['coords'],
            "status": status,
            "latency": latency,
            "jitter": jitter,
            "history": history[t['name']],
            "ip": t['ip']
        })
    
    save_history(history)

    svc_results = []
    for s in SVC_TARGETS:
        code, lat = check_http(s['url'])
        ssl_days = check_ssl_days(s['url'])
        status = "ONLINE" if code == 200 else "CRITICAL"
        
        print(f"SVC: {s['name']:<15} | HTTP {code}")
        
        svc_results.append({
            "type": "SVC",
            "name": s['name'],
            "url": s['url'],
            "status": status,
            "code": code,
            "latency": lat,
            "ssl": ssl_days
        })

    full_report = {"network": net_results, "services": svc_results, "updated": datetime.now().isoformat()}
    with open(OUTPUT_FILE, "w") as f:
        json.dump(full_report, f, indent=2)

if __name__ == "__main__":
    run_sentinel()
