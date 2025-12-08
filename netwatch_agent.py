import feedparser
from geopy.geocoders import Nominatim
import json
import time
import os
import re
from datetime import datetime

# CONFIG
OUTPUT_FILE = "live_outages.json"
RSS_FEEDS = [
    "https://news.google.com/rss/search?q=internet+outage+when:1d&hl=en-US&gl=US&ceid=US:en",
    "https://news.google.com/rss/search?q=fiber+cut+when:1d&hl=en-US&gl=US&ceid=US:en",
    "https://news.google.com/rss/search?q=isp+down+when:1d&hl=en-US&gl=US&ceid=US:en"
]

# ISP KEYWORDS (To tag reports)
ISPS = ["Comcast", "Xfinity", "AT&T", "Verizon", "Spectrum", "Charter", "Cox", "CenturyLink", "Lumen", "T-Mobile", "Optimum", "Starlink", "AWS", "Google Cloud", "Azure"]

# INIT GEOCODER
geolocator = Nominatim(user_agent="NetwatchGlobal/1.0")
location_cache = {}

def extract_location(text):
    # Simple heuristic: Look for " in [City], [State]" patterns
    # Real NLP is heavier, this is a fast hack.
    # We look for "in City" or "near City"
    match = re.search(r"\b(in|near|at) ([A-Z][a-z]+(?: [A-Z][a-z]+)*)(?:, ([A-Z]{2}|[A-Z][a-z]+))?", text)
    if match:
        city = match.group(2)
        state = match.group(3) if match.group(3) else ""
        return f"{city} {state}".strip()
    return None

def extract_isp(text):
    for isp in ISPS:
        if isp.lower() in text.lower():
            return isp
    return "Unknown Provider"

def scan_feeds():
    print("--- SCANNING GLOBAL FEEDS ---")
    outages = []
    seen_titles = set()

    for feed_url in RSS_FEEDS:
        try:
            feed = feedparser.parse(feed_url)
            for entry in feed.entries:
                if entry.title in seen_titles: continue
                seen_titles.add(entry.title)

                # 1. Analyze Text
                loc_name = extract_location(entry.title)
                isp_name = extract_isp(entry.title)
                
                if not loc_name: continue # Skip if no location found

                # 2. Geocode
                coords = None
                if loc_name in location_cache:
                    coords = location_cache[loc_name]
                else:
                    try:
                        loc = geolocator.geocode(loc_name, timeout=2)
                        if loc:
                            coords = [loc.latitude, loc.longitude]
                            location_cache[loc_name] = coords
                            time.sleep(1) # Polite rate limit
                    except: pass
                
                if coords:
                    print(f"Found: {isp_name} in {loc_name}")
                    outages.append({
                        "isp": isp_name,
                        "loc": loc_name,
                        "coords": coords,
                        "title": entry.title,
                        "link": entry.link,
                        "time": entry.published
                    })

        except Exception as e:
            print(f"Feed Error: {e}")

    # SAVE JSON
    with open(OUTPUT_FILE, "w") as f:
        json.dump(outages, f, indent=2)
    print(f"Database Updated: {len(outages)} active incidents.")

if __name__ == "__main__":
    scan_feeds()
