"""Opt-in PC evidence for one provider-native live event; never a Roku test.

Read a private JSON profile: {"manifest": "...", "catalog": "...", "type": "tv",
"event_id": "original-provider-id", "source_index": 0}. Use only manifests generated through the
provider's normal authorized setup. No CAPTCHA, cookies, account, DRM or proxy
resolver is implemented. Reports omit configuration/media URLs and header values.
"""
import argparse
import datetime
import hashlib
import importlib.util
import io
import json
import time
import urllib.parse
from pathlib import Path

spec = importlib.util.spec_from_file_location("live_probe", Path(__file__).with_name("probe-live-providers.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


def fingerprint(value):
    return hashlib.sha256(value.encode()).hexdigest()


class StageFailure(Exception):
    def __init__(self, stage, detail):
        super().__init__(stage)  # never the original URL-bearing exception
        self.stage, self.detail = stage, detail


class Reader:
    def __init__(self):
        self.events = []

    def get(self, stage, url, limit=1048576, headers=None):
        started = time.monotonic()
        record = {"stage": stage, "origin": urllib.parse.urlsplit(url).hostname}
        self.events.append(record)
        try:
            body, final, mime = probe.request(url, limit, headers)
            record.update(status=200, bytes=len(body), mime=mime,
                          final_origin=urllib.parse.urlsplit(final).hostname,
                          seconds=round(time.monotonic()-started, 3))
            return body, final, mime
        except Exception as error:
            record.update(probe.failure(error), seconds=round(time.monotonic()-started, 3))
            raise StageFailure(stage, probe.failure(error)) from None

    def json(self, stage, url):
        body, _, _ = self.get(stage, url)
        try:
            value = json.loads(body)
            if not isinstance(value, dict):
                raise ValueError()
            return value
        except (ValueError, TypeError):
            raise StageFailure(stage, {"error": "InvalidJSON"}) from None


def endpoint(base, resource, kind, identity):
    parsed = urllib.parse.urlsplit(base)
    path = parsed.path.rstrip("/") + "/" + resource + "/" + urllib.parse.quote(kind, safe="") + "/" + urllib.parse.quote(identity, safe="") + ".json"
    return urllib.parse.urlunsplit((parsed.scheme,parsed.netloc,path,parsed.query,""))


def manifest_base(url):
    parsed = urllib.parse.urlsplit(url)
    if not parsed.path.endswith("/manifest.json"):
        raise StageFailure("configuration",{"error":"ManifestPathRequired"})
    return urllib.parse.urlunsplit((parsed.scheme,parsed.netloc,parsed.path[:-14],parsed.query,""))


def resolve(reader, base, item):
    data = reader.json("addon-stream", endpoint(base, "stream", item["type"], item["id"]))
    streams = data.get("streams")
    if not isinstance(streams, list):
        raise StageFailure("addon-stream", {"error": "InvalidStreams"})
    if len(streams) > 500:
        raise StageFailure("addon-stream", {"error": "SourceBudget"})
    return streams


def playlist(reader, stream, selected=None):
    url = stream.get("url")
    if not isinstance(url, str):
        raise StageFailure("source", {"error": "BrowserOnly" if stream.get("externalUrl") else "NoDirectURL"})
    headers = stream_headers(stream)
    stage = "entry-playlist"
    if selected and selected.get("url"):
        url, stage = selected["url"], "variant-playlist"
    body, base, _ = reader.get(stage, url, 262144, headers)
    text = body.decode("utf8", "replace").strip()
    if not text.startswith("#EXTM3U"):
        kind = "DASHNotTested" if "<MPD" in text[:2048] else "NotHLS"
        raise StageFailure(stage, {"error": kind})
    if "#EXT-X-STREAM-INF:" in text:
        variants = [s for s in text.splitlines() if s and not s.startswith("#")]
        if not variants:
            raise StageFailure("variant-playlist", {"error": "EmptyMaster"})
        body, base, _ = reader.get("variant-playlist", urllib.parse.urljoin(base, variants[0]), 262144, headers)
        if selected is not None:
            # A native HLS client polls its selected media playlist, not a
            # newly routed master on every tick. Fresh rounds resolve anew.
            selected["url"] = base
        text = body.decode("utf8", "replace").strip()
    if not text.startswith("#EXTM3U"):
        raise StageFailure("variant-playlist", {"error": "NotHLS"})
    if "#EXT-X-KEY:" in text:
        raise StageFailure("playlist-policy", {"error": "EncryptedPlaylistNotTested"})
    if "#EXT-X-MAP:" in text or "#EXT-X-BYTERANGE:" in text:
        raise StageFailure("playlist-policy", {"error": "FragmentedOrByteRangeNotTested"})
    lines = text.splitlines()
    try:
        sequence = int(next((s.split(":",1)[1] for s in lines if s.startswith("#EXT-X-MEDIA-SEQUENCE:")), "0"))
        target = float(next((s.split(":",1)[1] for s in lines if s.startswith("#EXT-X-TARGETDURATION:")), "6"))
    except ValueError:
        raise StageFailure("variant-playlist", {"error": "InvalidSequence"}) from None
    segments = [(sequence+i, urllib.parse.urljoin(base, s)) for i,s in enumerate(s for s in lines if s and not s.startswith("#"))]
    return segments, headers, sequence, max(2, min(target/2, 8)), "#EXT-X-ENDLIST" not in text


def stream_headers(stream):
    try:
        return probe.request_headers(stream)
    except (ValueError, TypeError, AttributeError):
        raise StageFailure("source", {"error": "InvalidHeaders"}) from None


def decode_bytes(data):
    import av  # optional research-only dependency; never shipped with the app
    counts, spans, tracks = {}, {}, []
    with av.open(io.BytesIO(data)) as container:
        for track in container.streams:
            tracks.append({"type": track.type, "codec": track.codec_context.name,
                           "width": getattr(track.codec_context,"width",None),
                           "height": getattr(track.codec_context,"height",None),
                           "language": track.metadata.get("language")})
        for packet in container.demux():
            for frame in packet.decode():
                key = packet.stream.type
                counts[key] = counts.get(key, 0)+1
                if frame.pts is not None and frame.time_base is not None:
                    stamp = float(frame.pts*frame.time_base)
                    spans.setdefault(key, [stamp, stamp])
                    spans[key] = [min(stamp,spans[key][0]),max(stamp,spans[key][1])]
    return {"frames": counts, "pts": spans, "tracks": tracks, "decoder": "PyAV "+av.__version__}


def sample(reader, stream, seconds, decode=False, sleep=time.sleep, clock=time.monotonic):
    if not isinstance(stream, dict) or not isinstance(stream.get("url", ""), str):
        raise StageFailure("source", {"error": "InvalidSource"})
    started = clock()
    report = {"requested_seconds": seconds, "polls": 0, "unique_segments": 0, "segment_bytes": 0,
              "sequences": [], "frames": {}, "decode_failures": 0, "tracks": [],
              "media_url_sha256": fingerprint(stream.get("url","")),
              "header_names": list(stream_headers(stream))}
    report["event_content_verified"] = False  # decoding can succeed on a holding card
    seen = set()
    selected = {}
    while True:
        try:
            segments, headers, sequence, pause, live = playlist(reader,stream,selected)
            if selected.get("url"):
                report["variant_url_sha256"] = fingerprint(selected["url"])
            report["polls"] += 1
            report["live_playlist"] = live
            report["sequences"].append(sequence)
            unseen = [(n,u) for n,u in segments if fingerprint(u) not in seen]
            if report["polls"] == 1:
                unseen = unseen[-3:]
            if len(unseen) > 10:
                raise StageFailure("segment", {"error": "BehindLiveWindowBudget"})
            combined = bytearray()
            for number,url in unseen:
                body,_,_ = reader.get("segment",url,8388608,headers)
                if len(combined)+len(body) > 33554432 or report["segment_bytes"]+len(body) > 268435456:
                    raise StageFailure("segment", {"error": "MediaByteBudget"})
                seen.add(fingerprint(url))
                report["segment_bytes"] += len(body)
                report["unique_segments"] += 1
                combined.extend(body)
            if decode and combined:
                try:
                    decoded = decode_bytes(combined)
                    report["tracks"] = decoded["tracks"]
                    report["decoder"] = decoded["decoder"]
                    for kind,count in decoded["frames"].items():
                        report["frames"][kind] = report["frames"].get(kind,0)+count
                    for kind,span in decoded["pts"].items():
                        report.setdefault("pts",{}).setdefault(kind,span[:])
                        report["pts"][kind] = [min(span[0],report["pts"][kind][0]),max(span[1],report["pts"][kind][1])]
                except Exception as error:
                    report["decode_failures"] += 1
                    report["decode_error"] = type(error).__name__
            if clock()-started >= seconds or not live or seconds == 0:
                break
            sleep(min(pause,max(0,seconds-(clock()-started))))
        except StageFailure as error:
            report["failure"] = {"stage": error.stage, **error.detail}
            break
    report["elapsed_seconds"] = round(clock()-started,2)
    report["playlist_advanced"] = len(set(report["sequences"])) > 1
    return report


def run(profile, seconds=120, rounds=2, decode=False):
    reader = Reader()
    report = {"checked_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "scope": "PC requests/decoding; not physical Roku or audible language",
              "provider_origin": urllib.parse.urlsplit(profile["manifest"]).hostname,
              "rounds": [], "requests": reader.events}
    try:
        manifest = reader.json("manifest",profile["manifest"])
        base = manifest_base(profile["manifest"])
        catalogs = manifest.get("catalogs", [])
        if not isinstance(catalogs, list):
            raise StageFailure("manifest", {"error": "InvalidCatalogs"})
        catalog = next((c for c in catalogs if isinstance(c,dict) and c.get("id")==profile["catalog"] and c.get("type")==profile["type"]),None)
        if not catalog:
            raise StageFailure("catalog",{"error":"CatalogNotAdvertised"})
        url = endpoint(base,"catalog",profile["type"],profile["catalog"])
        parsed = urllib.parse.urlsplit(url)
        # Match the existing Crimson first-page route; retain configured query.
        url = urllib.parse.urlunsplit((parsed.scheme,parsed.netloc,parsed.path[:-5]+"/skip=0.json",parsed.query,""))
        metas = reader.json("catalog",url).get("metas",[])
        if not isinstance(metas, list):
            raise StageFailure("catalog", {"error": "InvalidMetas"})
        item = next((x for x in metas if isinstance(x,dict) and x.get("id")==profile["event_id"]),None)
        if item is None:
            raise StageFailure("catalog",{"error":"SelectedEventNotInCatalog"})
        if not isinstance(item.get("id"),str) or not isinstance(item.get("type"),str):
            raise StageFailure("catalog",{"error":"InvalidEvent"})
        report["event"] = {"name":item.get("name","")[:180],"id_sha256":fingerprint(item["id"]),
                           "type":item["type"],"catalog":profile["catalog"]}
        for number in range(rounds):
            entry = {"round":number+1}
            report["rounds"].append(entry)
            try:
                streams = resolve(reader,base,item)
                entry["source_count"] = len(streams)
                if "source_name" in profile:
                    candidates = [s for s in streams if isinstance(s,dict) and s.get("name")==profile["source_name"]]
                    if len(candidates) != 1:
                        raise StageFailure("source",{"error":"SelectedSourceMissingOrAmbiguous"})
                    source = candidates[0]
                else:
                    source = streams[profile.get("source_index",0)]
                entry["source_index"] = streams.index(source)
                entry["sample"] = sample(reader,source,seconds,decode)
            except StageFailure as error:
                entry["failure"] = {"stage":error.stage,**error.detail}
            except (IndexError,KeyError,TypeError):
                entry["failure"] = {"stage":"source","error":"MissingSelectedSource"}
            if number+1 < rounds:
                time.sleep(5)
    except StageFailure as error:
        report["failure"] = {"stage":error.stage,**error.detail}
    except (IndexError,KeyError,TypeError,ValueError):
        report["failure"] = {"stage":"configuration","error":"InvalidProfileOrCatalog"}
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile-file",type=Path,required=True)
    parser.add_argument("--seconds",type=int,default=120,choices=range(0,301),metavar="0..300")
    parser.add_argument("--rounds",type=int,default=2,choices=range(1,4))
    parser.add_argument("--decode",action="store_true")
    parser.add_argument("--output",type=Path,required=True)
    args = parser.parse_args()
    try:
        profile = json.loads(args.profile_file.read_text(encoding="utf8"))
        if not isinstance(profile,dict) or not isinstance(profile.get("manifest"),str):
            raise ValueError()
    except (OSError,ValueError):
        parser.exit(2,"Cannot read a valid private profile; no profile values printed.\n")
    report = run(profile,args.seconds,args.rounds,args.decode)
    args.output.write_text(json.dumps(report,indent=2,ensure_ascii=True)+"\n",encoding="utf8")
    print(json.dumps({"report":str(args.output),"event":report.get("event"),"rounds":report["rounds"],"failure":report.get("failure")}))
