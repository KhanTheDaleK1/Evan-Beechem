import subprocess
import json
import time
import requests
import ssl
import socket
from datetime import datetime
from selenium import webdriver
from selenium.webdriver.chrome.options import Options

# CONFIG
OUTPUT_FILE = "network_health.json"
HISTORY_FILE = "latency_history.json"
MY_LOC = [31.3113, -92.4451]

# 1. NETWORK TARGETS
NET_TARGETS = [
    {"name": "Google DNS", "ip": "8.8.8.8", "coords": [37.40, -122.07]},
    {"name": "AWS Virginia", "ip": "52.94.76.1", "coords": [38.03, -78.50]},
    {"name": "Azure East", "ip": "13.107.21.200", "coords": [36.66, -78.39]},
    {"name": "London Core", "ip": "151.101.192.81", "coords": [51.50, -0.12]},
    {"name": "Tokyo Core", "ip": "172.217.25.14", "coords": [35.67, 139.76]}
]

# 2. SERVICE TARGETS
SVC_TARGETS = [
    {"name": "MY DASHBOARD", "url": "https://beechem.site"},
    {"name": "GITHUB API", "url": "https://api.github.com"}
]

# 3. SYNTHETIC TRANSACTIONS (Complex User Flows)
SYNTH_TARGETS = [
    {"name": "GOOGLE SEARCH", "url": "https://www.google.com", "check": "title", "expect": "Google"},
    {"name": "GITHUB STATUS", "url": "https://www.githubstatus.com", "check": "text", "expect": "All Systems Operational"}
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
    except: return 0, 0

def check_ssl_days(url):
    try:
        hostname = url.split("//")[1].split("/")[0]
        context = ssl.create_default_context()
        with socket.create_connection((hostname, 443)) as sock:
            with context.wrap_socket(sock, server_hostname=hostname) as ssock:
                cert = ssock.getpeercert()
                expiry = datetime.strptime(cert['notAfter'], "%b %d %H:%M:%S %Y %Z")
                return (expiry - datetime.now()).days
    except: return 0

def check_synthetic(target):
    # Headless Browser Test
    try:
        start_time = time.time()
        
        chrome_options = Options()
        chrome_options.add_argument("--headless") 
        chrome_options.add_argument("--no-sandbox")
        chrome_options.add_argument("--disable-dev-shm-usage")
        
        driver = webdriver.Chrome(options=chrome_options)
        driver.set_page_load_timeout(15)
        
        driver.get(target['url'])
        
        status = "FAIL"
        if target['check'] == "title":
            if target['expect'] in driver.title: status = "PASS"
        elif target['check'] == "text":
            if target['expect'] in driver.page_source: status = "PASS"
            
        load_time = int((time.time() - start_time) * 1000)
        driver.quit()
        return status, load_time
        
    except Exception as e:
        print(f"Synth Error: {e}")
        return "ERROR", 0

def load_history():
    try:
        with open(HISTORY_FILE, 'r') as f: return json.load(f)
    except: return {}

def save_history(hist):
    with open(HISTORY_FILE, 'w') as f: json.dump(hist, f)

def run_sentinel():
    print("--- SENTINEL SCAN STARTED ---")
    
    # NET
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
        net_results.append({ "type": "NET", "name": t['name'], "origin": MY_LOC, "dest": t['coords'], "status": status, "latency": latency, "jitter": jitter, "history": history[t['name']], "ip": t['ip'] })
    save_history(history)

    # SVC
    svc_results = []
    for s in SVC_TARGETS:
        code, lat = check_http(s['url'])
        ssl_days = check_ssl_days(s['url'])
        status = "ONLINE" if code == 200 else "CRITICAL"
        print(f"SVC: {s['name']:<15} | HTTP {code}")
        svc_results.append({ "type": "SVC", "name": s['name'], "url": s['url'], "status": status, "code": code, "latency": lat, "ssl": ssl_days })

    # SYNTH
    synth_results = []
    for syn in SYNTH_TARGETS:
        stat, lat = check_synthetic(syn)
        print(f"SYN: {syn['name']:<15} | {stat} | {lat}ms")
        synth_results.append({ "name": syn['name'], "status": stat, "latency": lat, "url": syn['url'] })

    full_report = { "network": net_results, "services": svc_results, "synthetic": synth_results, "updated": datetime.now().isoformat() }
    with open(OUTPUT_FILE, "w") as f: json.dump(full_report, f, indent=2)

if __name__ == "__main__":
    run_sentinel()
