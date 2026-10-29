"""Deterministic production probe flow; no outbound requests or PyAV required."""
import importlib.util
import json
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("reliability", Path(__file__).parents[1] / "scripts/probe-live-reliability.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class ReliabilityTests(unittest.TestCase):
    def setUp(self):
        self.profile = {"manifest": "https://provider.example/private-fixture/manifest.json?key=private-query",
                        "type": "sports", "catalog": "live", "event_id": "original:id/1",
                        "source_name": "Selected", "source_index": 999}
        self.metas = [{"id": "different", "type": "sports", "name": "Wrong game"},
                      {"id": "original:id/1", "type": "sports", "name": "Home vs Away"}]
        self.source = {"name": "Selected", "url": "https://media.example/live?signature=private-media",
                       "behaviorHints": {"proxyHeaders": {"request": {"Referer": "https://provider.example/private-ref"}}}}
        self.calls = []
        self.resolutions = 0

    def transport(self, url, limit=1048576, headers=None):
        self.calls.append((url, limit, headers))
        if "/manifest.json" in url:
            value = {"catalogs": [{"id": "live", "type": "sports"}]}
        elif "/catalog/" in url:
            value = {"metas": self.metas}
        elif "/stream/" in url:
            self.resolutions += 1
            value = {"streams": [{"externalUrl": "https://provider.example/donate"}, self.source]}
        elif "media.example/live" in url:
            return b"#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:7\n#EXTINF:4,\nsegment.ts?signature=private-segment\n", url, "application/vnd.apple.mpegurl"
        elif "segment.ts" in url:
            return b"fixture-ts", url, "video/mp2t"
        else:
            raise AssertionError("Unexpected request")
        return json.dumps(value).encode(), url, "application/json"

    def run_probe(self, transport=None, **kwargs):
        with patch.object(probe.probe, "request", side_effect=transport or self.transport), patch.object(probe.time, "sleep"):
            return probe.run(self.profile, seconds=0, rounds=2, **kwargs)

    def test_full_flow_pins_original_id_and_refreshes_twice(self):
        report = self.run_probe()
        self.assertEqual(self.resolutions, 2)
        self.assertEqual(report["event"]["name"], "Home vs Away")
        streams = [u for u, _, _ in self.calls if "/stream/" in u]
        self.assertEqual(streams, ["https://provider.example/private-fixture/stream/sports/original%3Aid%2F1.json?key=private-query"] * 2)
        self.assertIn("/catalog/sports/live/skip=0.json?key=private-query", self.calls[1][0])
        self.assertEqual([r["sample"]["unique_segments"] for r in report["rounds"]], [1, 1])
        self.assertTrue(all(h == {"Referer": "https://provider.example/private-ref"} for u, _, h in self.calls if "media.example" in u))

    def test_removed_event_never_selects_next_game(self):
        self.metas = self.metas[:1]
        result = self.run_probe()
        self.assertEqual(result["failure"]["error"], "SelectedEventNotInCatalog")
        self.assertEqual(self.resolutions, 0)

    def test_reordered_catalog_preserves_identity(self):
        self.metas.reverse()
        self.assertEqual(self.run_probe()["event"]["id_sha256"], probe.fingerprint(self.profile["event_id"]))

    def test_report_never_contains_config_media_or_header_secrets(self):
        report = json.dumps(self.run_probe())
        for secret in ("private-fixture", "private-query", "private-media", "private-segment", "private-ref", "original:id/1"):
            self.assertNotIn(secret, report)

    def test_playlist_403_is_not_addon_or_segment_failure(self):
        def transport(url, limit=1048576, headers=None):
            if "media.example/live" in url:
                raise urllib.error.HTTPError(url, 403, "Forbidden private-secret", {}, None)
            return self.transport(url, limit, headers)
        report = self.run_probe(transport)
        self.assertEqual(self.resolutions, 2)
        for entry in report["rounds"]:
            self.assertEqual(entry["sample"]["failure"], {"stage": "entry-playlist", "status": 403})
            self.assertEqual(entry["sample"]["unique_segments"], 0)
        self.assertNotIn("private-secret", json.dumps(report))

    def test_segment_failure_and_fresh_resolution_recovery(self):
        def transport(url, limit=1048576, headers=None):
            if "segment.ts" in url and self.resolutions == 1:
                raise urllib.error.HTTPError(url, 502, "Unavailable", {}, None)
            return self.transport(url, limit, headers)
        report = self.run_probe(transport)
        self.assertEqual(report["rounds"][0]["sample"]["failure"]["stage"], "segment")
        self.assertNotIn("failure", report["rounds"][1]["sample"])
        self.assertEqual(self.resolutions, 2)

    def test_decode_success_does_not_certify_event_picture_or_language(self):
        decoded = {"frames": {"video": 90, "audio": 140}, "pts": {"video": [0, 3]},
                   "tracks": [{"type": "audio", "language": None}], "decoder": "fixture"}
        with patch.object(probe, "decode_bytes", return_value=decoded):
            report = self.run_probe(decode=True)
        for entry in report["rounds"]:
            self.assertEqual(entry["sample"]["frames"]["video"], 90)
            self.assertFalse(entry["sample"]["event_content_verified"])
            self.assertIsNone(entry["sample"]["tracks"][0]["language"])

    def test_renamed_or_duplicate_source_is_not_replaced_silently(self):
        self.source["name"] = "Other source"
        report = self.run_probe()
        self.assertEqual(report["rounds"][0]["failure"]["error"], "SelectedSourceMissingOrAmbiguous")
        self.assertFalse(any("media.example" in u for u, _, _ in self.calls))
        def duplicate(url, limit=1048576, headers=None):
            if "/stream/" in url:
                return json.dumps({"streams": [{"name": "Selected"}] * 2}).encode(), url, "application/json"
            return self.transport(url, limit, headers)
        self.assertEqual(self.run_probe(duplicate)["rounds"][0]["failure"]["error"], "SelectedSourceMissingOrAmbiguous")

    def test_browser_only_and_invalid_headers_remain_source_errors(self):
        self.source = {"name": "Selected", "externalUrl": "https://provider.example/player"}
        self.assertEqual(self.run_probe()["rounds"][0]["sample"]["failure"]["error"], "BrowserOnly")
        self.source = {"name": "Selected", "url": "https://media.example/live", "behaviorHints": None}
        self.assertEqual(self.run_probe()["rounds"][0]["failure"], {"stage": "source", "error": "InvalidHeaders"})

    def test_html_dash_and_encrypted_media_are_not_decode_success(self):
        cases = [(b"<html>challenge</html>", "NotHLS"), (b"<MPD></MPD>", "DASHNotTested"),
                 (b'#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key"\nseg.ts', "EncryptedPlaylistNotTested")]
        for body, error in cases:
            def transport(url, limit=1048576, headers=None):
                if "media.example/live" in url:
                    return body, url, "text/plain"
                return self.transport(url, limit, headers)
            self.assertEqual(self.run_probe(transport)["rounds"][0]["sample"]["failure"]["error"], error)

    def test_bad_json_and_source_budget(self):
        def transport(url, limit=1048576, headers=None):
            if "/stream/" in url:
                return b"{", url, "application/json"
            return self.transport(url, limit, headers)
        self.assertEqual(self.run_probe(transport)["rounds"][0]["failure"], {"stage": "addon-stream", "error": "InvalidJSON"})
        def too_many(url, limit=1048576, headers=None):
            if "/stream/" in url:
                return json.dumps({"streams": [{}] * 501}).encode(), url, "application/json"
            return self.transport(url, limit, headers)
        self.assertEqual(self.run_probe(too_many)["rounds"][0]["failure"]["error"], "SourceBudget")

    def test_sustained_polling_counts_only_new_segments(self):
        now = [0]
        def sleep(seconds):
            now[0] += seconds
        with patch.object(probe.probe, "request", side_effect=self.transport):
            result = probe.sample(probe.Reader(), self.source, 4, sleep=sleep, clock=lambda: now[0])
        self.assertEqual(result["polls"], 3)
        self.assertEqual(result["unique_segments"], 1)
        self.assertFalse(result["playlist_advanced"])
        self.assertFalse(result["event_content_verified"])

    def test_selected_variant_is_polled_without_rerouting_master(self):
        now = [0]
        master_calls = []
        variants = []
        def transport(url, limit=1048576, headers=None):
            if "/master" in url:
                master_calls.append(url)
                return b"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nvariant?token=private-variant", url, "application/vnd.apple.mpegurl"
            if "/variant" in url:
                variants.append(url)
                body = "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:" + str(len(variants)) + "\n#EXTINF:4,\nsegment.ts\n"
                return body.encode(), url, "application/vnd.apple.mpegurl"
            return b"fixture-ts", url, "video/mp2t"
        def sleep(seconds):
            now[0] += seconds
        with patch.object(probe.probe, "request", side_effect=transport):
            report = probe.sample(probe.Reader(), {"url": "https://media.example/master"}, 4, sleep=sleep, clock=lambda: now[0])
        self.assertEqual(len(master_calls), 1)
        self.assertEqual(len(variants), 3)
        self.assertEqual(len(set(variants)), 1)
        self.assertTrue(report["playlist_advanced"])
        self.assertNotIn("private-variant", json.dumps(report))


if __name__ == "__main__":
    unittest.main()
