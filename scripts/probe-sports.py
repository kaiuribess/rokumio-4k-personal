"""Read-only, bounded probes of public schedule/playlist endpoints.

No cookies, accounts, custom Referer or resolver bypass. Media probe is opt-in,
research only, not permission to redistribute or proof of Roku decoding.
"""
import argparse
import concurrent.futures
import datetime
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

LEAGUES = [
    "football/nfl", "basketball/nba", "baseball/mlb", "hockey/nhl", "mma/ufc",
    "football/college-football", "basketball/mens-college-basketball",
    "basketball/womens-college-basketball", "basketball/wnba", "soccer/eng.1",
    "soccer/usa.1", "soccer/esp.1", "soccer/uefa.champions", "boxing/boxing",
]

def get(url, maximum=1048576):
    with urllib.request.urlopen(url, timeout=8) as response:
        body = response.read(maximum + 1)
        if len(body) > maximum:
            raise ValueError("response exceeds budget")
        return response.status, response.headers.get_content_type(), body

def scoreboard(league):
    start = time.monotonic()
    url = "https://site.api.espn.com/apis/site/v2/sports/" + league + "/scoreboard"
    url += "?dates=" + datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d") + "&limit=100"
    result = {"league": league, "url": url}
    try:
        status, mime, body = get(url)
        data = json.loads(body)
        events = data.get("events")
        result.update(status=status, mime=mime, bytes=len(body), valid_events=isinstance(events, list))
        if isinstance(events, list):
            result["events"] = len(events)
            result["states"] = sorted({e.get("status", {}).get("type", {}).get("state", "unknown") for e in events if isinstance(e, dict)})
    except urllib.error.HTTPError as error:
        result["status"] = error.code
    except Exception as error:
        result["error"] = type(error).__name__
    result["seconds"] = round(time.monotonic() - start, 3)
    return result

def media():
    master = "https://rbmn-live.akamaized.net/hls/live/590964/BoRB-AT/master.m3u8"
    result = {"master": master, "kind": "research-only; rights and hardware unverified"}
    try:
        status, mime, data = get(master, 65536)
        text = data.decode("utf-8")
        result.update(status=status, mime=mime, hls=text.startswith("#EXTM3U"))
        result["resolutions"] = re.findall(r"RESOLUTION=([0-9]+x[0-9]+)", text)
        result["codecs"] = sorted(set(re.findall(r'CODECS="([^"]+)"', text)))
        variants = [line for line in text.splitlines() if line and not line.startswith("#")]
        variant = urllib.parse.urljoin(master, variants[0])
        if urllib.parse.urlparse(variant).hostname != "rbmn-live.akamaized.net":
            raise ValueError("unexpected CDN host")
        _, _, data = get(variant, 65536)
        playlist = data.decode("utf-8")
        result["variant_is_live"] = "#EXT-X-ENDLIST" not in playlist
        result["encrypted"] = "#EXT-X-KEY:" in playlist
        segments = [line for line in playlist.splitlines() if line and not line.startswith("#")]
        segment = urllib.parse.urljoin(variant, segments[-2] if len(segments)>1 else segments[0])
        if urllib.parse.urlparse(segment).hostname != "rbmn-live.akamaized.net":
            raise ValueError("unexpected segment host")
        # Read a bounded prefix, then close: no feature-sized download.
        with urllib.request.urlopen(segment, timeout=8) as response:
            prefix = response.read(65536)
            result["segment_status"] = response.status
            result["segment_bytes_read"] = len(prefix)
            result["mpeg_ts_sync"] = len(prefix) >= 377 and all(prefix[i] == 0x47 for i in [0,188,376])
    except Exception as error:
        result["error"] = type(error).__name__
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--media", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(scoreboard, LEAGUES))
    report = {"checked_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "scoreboards": results}
    if args.media:
        report["media"] = media()
    rendered = json.dumps(report, indent=2)
    if args.output:
        args.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
