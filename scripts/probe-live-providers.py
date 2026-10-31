"""Opt-in, bounded checks of public sports add-on responses.

No account, cookies, browser-challenge solver, DRM, proxy or installation.
Only public HTTPS destinations; resolved media URLs and header values are
never printed or saved. Optional PyAV decodes in-memory segments on the PC;
this is NOT a Roku decoder or an audible-language test.
"""
import argparse
import concurrent.futures
import datetime
import hashlib
import io
import ipaddress
import json
import re
import socket
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# Identify this client truthfully. urllib's implicit Python user agent caused
# Cloudflare 1010 responses for otherwise available, authorized add-on APIs.
# This is not a browser/Roku identity and does not carry browser cookies.
RESEARCH_USER_AGENT = "CrimsonCinema-Research/0.6 (+https://github.com/kaiuribess/rokumio-4k-personal; PC compatibility test)"


MANIFESTS = {
    "nuvio": "https://nuviosports.xyz/manifest.json",
    "stremverse": "https://stremverse1.alwaysdata.net/manifest.json",
}


def public_url(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("public HTTPS required")
    if parsed.port not in (None, 443) or len(url) > 8192:
        raise ValueError("URL budget")
    addresses = socket.getaddrinfo(parsed.hostname, 443, type=socket.SOCK_STREAM)
    if not addresses or any(not ipaddress.ip_address(a[4][0]).is_global for a in addresses):
        raise ValueError("non-public destination")
    return parsed


class PublicRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        target = public_url(new_url)
        result = super().redirect_request(request, fp, code, message, headers, new_url)
        # A provider's per-item authorization must not leak through a redirect
        # to an unrelated host. Cross-origin cookie/token cases need native QA.
        if result and target.hostname != urllib.parse.urlsplit(request.full_url).hostname:
            for name in list(result.headers):
                if name.lower() not in ("user-agent", "accept", "accept-encoding"):
                    result.remove_header(name)
        return result


def request(url, limit=1048576, headers=None):
    public_url(url)
    opener = urllib.request.build_opener(PublicRedirect())
    request_headers = dict(headers or {})
    if not any(name.lower() == "user-agent" for name in request_headers):
        request_headers["User-Agent"] = RESEARCH_USER_AGENT
    with opener.open(urllib.request.Request(url, headers=request_headers), timeout=10) as response:
        body = response.read(limit + 1)
        if len(body) > limit:
            raise ValueError("response budget")
        return body, response.geturl(), response.headers.get_content_type()


def failure(error):
    if isinstance(error, urllib.error.HTTPError):
        return {"status": error.code}
    return {"error": type(error).__name__}  # exception strings can contain URLs


def inventory(item):
    name, url = item
    out = {"provider": name, "manifest": url}
    try:
        body, _, _ = request(url, 262144)
        data = json.loads(body)
        out.update(status=200, id=data.get("id"), version=data.get("version"),
                   types=data.get("types"), resources=data.get("resources"),
                   catalogs=[{k: c.get(k) for k in ("id", "type", "name", "extra")}
                             for c in data.get("catalogs", [])[:40]])
    except Exception as error:
        out.update(failure(error))
    return out


def request_headers(stream):
    values = stream.get("behaviorHints", {}).get("proxyHeaders", {}).get("request", {})
    if not isinstance(values, dict) or len(values) > 16:
        raise ValueError("header budget")
    result = {}
    for name, value in values.items():
        if name.lower() in ("host", "connection", "range", "content-length"):
            continue
        if not re.fullmatch(r"[A-Za-z0-9!#$%&'*+.^_`|~-]{1,128}", name):
            raise ValueError("header name")
        if not isinstance(value, str) or len(value) > 2048 or any(ord(c) < 32 or ord(c) == 127 for c in value):
            raise ValueError("header value")
        result[name] = value
    return result


def media(stream, decode=False):
    url = stream.get("url")
    if not url:
        return {"kind": "browser-only" if stream.get("externalUrl") else "no-direct-url"}
    parsed = urllib.parse.urlsplit(url)
    out = {"origin": parsed.hostname, "scheme": parsed.scheme,
           "query_present": bool(parsed.query), "header_names": []}
    try:
        headers = request_headers(stream)
        out["header_names"] = list(headers)
        body, base, mime = request(url, 262144, headers)
        out.update(status=200, mime=mime)
        text = body.decode("utf8", "replace")
        if not text.startswith("#EXTM3U"):
            out["kind"] = "DASH-unprobed" if re.search(r"<MPD[ >]", text[:1024]) else "not-HLS"
            return out
        out["kind"] = "HLS"
        out["advertised_resolutions"] = re.findall(r"RESOLUTION=([0-9]+x[0-9]+)", text)
        if "#EXT-X-STREAM-INF:" in text:
            variants = [line for line in text.splitlines() if line and not line.startswith("#")]
            body, base, _ = request(urllib.parse.urljoin(base, variants[0]), 262144, headers)
            text = body.decode("utf8", "replace")
        if not text.startswith("#EXTM3U"):
            raise ValueError("variant is not HLS")
        out["live_playlist"] = "#EXT-X-ENDLIST" not in text
        out["key_present"] = "#EXT-X-KEY:" in text
        out["sequence"] = re.findall(r"#EXT-X-MEDIA-SEQUENCE:([0-9]+)", text)[:1]
        if out["key_present"]:
            out["segment_check"] = "not attempted: encrypted playlist"
            return out
        segments = [line for line in text.splitlines() if line and not line.startswith("#")]
        combined = bytearray()
        out["segment_bytes"] = []
        for line in segments[-3:]:
            data, _, _ = request(urllib.parse.urljoin(base, line), 8388608, headers)
            combined.extend(data)
            out["segment_bytes"].append(len(data))
        out["ts_sync"] = len(combined) >= 377 and all(combined[i] == 71 for i in (0, 188, 376))
        if decode:
            import av  # optional research-only environment, never a Roku dependency
            out["decoder"] = "PyAV " + av.__version__
            container = av.open(io.BytesIO(combined))
            out["tracks"] = [{"type": t.type, "codec": t.codec_context.name,
                              "width": getattr(t.codec_context, "width", None),
                              "height": getattr(t.codec_context, "height", None),
                              "language": t.metadata.get("language")}
                             for t in container.streams]
            counts = {}
            started = time.monotonic()
            for packet in container.demux():
                for _ in packet.decode():
                    counts[packet.stream.type] = counts.get(packet.stream.type, 0) + 1
                if time.monotonic() - started > 20:
                    break
            out["decoded_frames"] = counts
            container.close()
    except Exception as error:
        out.update(failure(error))
    return out


def stremverse(indices, decode=False):
    base = MANIFESTS["stremverse"].removesuffix("/manifest.json")
    out = {"catalog": "stremverse_live_events", "type": "tv", "events": []}
    try:
        # Exact route used by Crimson, not just the provider's home page.
        data = json.loads(request(base + "/catalog/tv/stremverse_live_events/skip=0.json")[0])
        metas = data["metas"]
        out["catalog_count"] = len(metas)
        for index in indices[:4]:
            if index < 0 or index >= len(metas):
                continue
            item = metas[index]
            event = {"index": index, "name": item["name"][:180], "id_length": len(item["id"]),
                     "id_sha256": hashlib.sha256(item["id"].encode()).hexdigest(), "sources": []}
            out["events"].append(event)
            endpoint = base + "/stream/" + urllib.parse.quote(item["type"], safe="") + "/" + urllib.parse.quote(item["id"], safe="") + ".json"
            try:
                sources = json.loads(request(endpoint)[0])["streams"]
                event["source_count"] = len(sources)
                for stream in sources[:6]:
                    event["sources"].append(media(stream, decode))
            except Exception as error:
                event.update(failure(error))
    except Exception as error:
        out.update(failure(error))
    return out


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event-index", type=int, action="append", default=[])
    parser.add_argument("--decode", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        manifests = list(pool.map(inventory, MANIFESTS.items()))
    report = {"checked_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "verification": "PC network/decode only; no Roku or audible-language test",
              "highfly": {"state": "Needs normal human-verified configuration; bare manifest URLs are not a service-health test",
                          "configure": ["https://sportsfree.highfly.dev/configure", "https://sportsfree-us2.highfly.dev/configure"]},
              "manifests": manifests, "stremverse": stremverse(args.event_index or [0, 1, 2, 3], args.decode)}
    rendered = json.dumps(report, indent=2, ensure_ascii=True) + "\n"
    if args.output:
        args.output.write_bytes(rendered.encode("utf8"))
    print(rendered)
