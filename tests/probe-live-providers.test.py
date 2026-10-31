"""Research tool safety checks; no outbound traffic or media dependencies."""
import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock
import urllib.request

spec = importlib.util.spec_from_file_location("sports_probe", Path(__file__).parents[1] / "scripts/probe-live-providers.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class ProbeTests(unittest.TestCase):
    def test_public_destination(self):
        with patch.object(probe.socket, "getaddrinfo", return_value=[(2, 1, 6, "", ("8.8.8.8", 443))]):
            self.assertEqual(probe.public_url("https://example.org/live?token=fixture").hostname, "example.org")
            for url in ("http://example.org/live", "https://user:secret@example.org/", "https://example.org:8443/"):
                with self.assertRaises(ValueError):
                    probe.public_url(url)
        with patch.object(probe.socket, "getaddrinfo", return_value=[(2, 1, 6, "", ("127.0.0.1", 443))]):
            with self.assertRaises(ValueError):
                probe.public_url("https://example.org/")

    def test_header_budget_and_injection(self):
        for headers in ({"X-Test": "value\r\nInjected: yes"}, {"Bad Name": "x"}, {"X-Test": "x" * 2049}):
            with self.assertRaises(ValueError):
                probe.request_headers({"behaviorHints": {"proxyHeaders": {"request": headers}}})
        stream = {"behaviorHints": {"proxyHeaders": {"request": {"Referer": "https://example.org/", "Range": "bytes=0-"}}}}
        self.assertEqual(probe.request_headers(stream), {"Referer": "https://example.org/"})

    def test_redirect_rechecks_public_destination_and_strips_secrets(self):
        request = urllib.request.Request("https://one.example/live", headers={"Authorization": "fixture", "Cookie": "fixture", "Referer": "https://one.example/", "User-Agent": "Probe"})
        with patch.object(probe, "public_url", return_value=probe.urllib.parse.urlsplit("https://two.example/live")) as check:
            redirect = probe.PublicRedirect().redirect_request(request, None, 302, "Found", {}, "https://two.example/live")
            check.assert_called_once()
            self.assertEqual(redirect.headers, {"User-agent": "Probe"})

    def test_nonmedia_never_becomes_video(self):
        self.assertEqual(probe.media({"externalUrl": "https://example.org/player"}), {"kind": "browser-only"})
        with patch.object(probe, "request", return_value=(b"<html>player</html>", "https://example.org/opaque", "text/html")):
            result = probe.media({"url": "https://example.org/opaque?token=never-print"})
            self.assertEqual(result["kind"], "not-HLS")
            self.assertNotIn("never-print", str(result))

    def test_request_identifies_research_client_without_browser_impersonation(self):
        response = MagicMock()
        response.__enter__.return_value = response
        response.read.return_value = b"{}"
        response.geturl.return_value = "https://example.org/manifest.json"
        response.headers.get_content_type.return_value = "application/json"
        opener = MagicMock()
        opener.open.return_value = response
        supplied = {"Referer": "https://example.org/"}
        with patch.object(probe, "public_url"), patch.object(probe.urllib.request, "build_opener", return_value=opener):
            probe.request("https://example.org/manifest.json", headers=supplied)
        request = opener.open.call_args.args[0]
        self.assertEqual(request.get_header("User-agent"), probe.RESEARCH_USER_AGENT)
        self.assertTrue(request.get_header("User-agent").startswith("CrimsonCinema-Research/"))
        self.assertNotIn("Cookie", request.headers)
        self.assertEqual(supplied, {"Referer": "https://example.org/"})
        response.read.assert_called_once_with(1048577)
        self.assertEqual(opener.open.call_args.kwargs["timeout"], 10)

    def test_provider_user_agent_overrides_default_case_insensitively(self):
        for key in ("User-Agent", "user-agent", "USER-AGENT"):
            response = MagicMock()
            response.__enter__.return_value = response
            response.read.return_value = b"#EXTM3U"
            opener = MagicMock()
            opener.open.return_value = response
            with patch.object(probe, "public_url"), patch.object(probe.urllib.request, "build_opener", return_value=opener):
                probe.request("https://example.org/live.m3u8", headers={key: "ProviderRequired/1"})
            self.assertEqual(opener.open.call_args.args[0].get_header("User-agent"), "ProviderRequired/1")

    def test_exception_strings_are_not_reports(self):
        self.assertEqual(probe.failure(ValueError("https://secret.example/token")), {"error": "ValueError"})


if __name__ == "__main__":
    unittest.main()
