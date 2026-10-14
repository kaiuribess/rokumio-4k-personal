' Setup page unit tests — the pure half of source/util/SetupPage.brs, which
' carries every decision the socket code makes but swaps no bytes itself. The
' roStreamSocket lifecycle is deliberately untouched here: the interpreter has
' no network stack, so the rig that keeps THAT honest is the structural
' contract in tests/run.js instead.
'
' Method-form string indexing is zero-based (the global Mid(s, i, n) is
' one-based — the two live side by side in BrightScript), so every expected
' value below is written against the method convention the file uses.

sub Test_Setup_RequestStateFraming()
    Harness_Suite("Setup page request framing")

    ' GET with and without further headers.
    Harness_Equal(SetupRequestState("GET / HTTP/1.1" + CrLf() + CrLf()), "ready", "bare GET is ready")
    Harness_Equal(
        SetupRequestState("GET /manifest.json HTTP/1.1" + CrLf() + "Host: x" + CrLf() + CrLf()),
        "ready",
        "GET with a Host header is ready")
    Harness_Equal(SetupRequestState("GET /q?? HTTP/1.1" + CrLf() + CrLf()), "ready", "query string is irrelevant")

    ' Partial arrivals are incomplete, however they happen to be sliced.
    Harness_Equal(SetupRequestState(""), "incomplete", "empty buffer is incomplete")
    Harness_Equal(SetupRequestState("GET / HT"), "incomplete", "no terminator yet is incomplete")
    Harness_Equal(SetupRequestState("GET / HTTP/1.1" + CrLf() + "Host: x" + CrLf()), "incomplete", "headers still open is incomplete")

    ' A single pair of \r\n is not the end of the headers.
    Harness_Equal(SetupRequestState("GET / HTTP/1.1" + CrLf()), "incomplete", "one CRLF is not a full header block")

    ' Method policing.
    Harness_Equal(SetupRequestState("PUT / HTTP/1.1" + CrLf() + CrLf()), "405", "PUT is 405")
    Harness_Equal(SetupRequestState("POST / HTTP/1.1" + CrLf() + CrLf()), "411", "POST with no Content-Length is 411")

    ' POST framing by Content-Length.
    body = "manifest=https%3A%2F%2Fx.example%2Fmanifest.json"
    post = "POST / HTTP/1.1" + CrLf() + "Host: x" + CrLf()
    post = post + "Content-Length: " + Len(body).ToStr() + CrLf() + CrLf() + body
    Harness_Equal(SetupRequestState(post), "ready", "a framed POST body is ready")
    Harness_Equal(SetupRequestState(post.Left(post.Len() - 6)), "incomplete", "a short body is incomplete")
    Harness_Equal(SetupRequestState(post + "extra"), "ready", "extra bytes after a framed body still read as ready")

    ' Malformed and oversized.
    Harness_Equal(SetupRequestState("NOT A REQUEST" + CrLf() + CrLf()), "400", "unparseable request line is 400")
    Harness_Equal(
        SetupRequestState("POST / HTTP/1.1" + CrLf() + "Content-Length: 999999999" + CrLf() + CrLf()),
        "400",
        "an oversized declared body is 400")
    Harness_Equal(
        SetupRequestState("POST / HTTP/1.1" + CrLf() + "Content-Length: 4x2" + CrLf() + CrLf()),
        "411",
        "a non-digit Content-Length is 411")
end sub

sub Test_Setup_RequestMethodAndBody()
    Harness_Suite("Setup page request method and body split")

    get = "GET /?x=1 HTTP/1.1" + CrLf() + "Host: a" + CrLf() + CrLf()
    Harness_Equal(SetupRequestMethod(get), "GET", "method of a GET is GET")
    Harness_Equal(SetupBody(get), "", "a GET has no body")

    body = "manifest=x&y=2"
    clip = "GET /oops HTTP/1.1"
    Harness_Equal(SetupRequestMethod(clip), "GET", "method reads off a partial request")

    post = "POST / HTTP/1.1" + CrLf() + "Host: a" + CrLf() + CrLf() + body
    Harness_Equal(SetupRequestMethod(post), "POST", "method of a POST is POST")
    Harness_Equal(SetupBody(post), body, "body is the bytes after the blank line")
end sub

sub Test_Setup_HeaderParsing()
    Harness_Suite("Setup page header parsing")

    headers = "GET / HTTP/1.1" + CrLf()
    headers = headers + "Host: local" + CrLf()
    headers = headers + "Content-Length: 12" + CrLf()
    headers = headers + "X-Mixed-Case:  Yes "

    Harness_Equal(SetupHeaderValue(headers, "content-length"), "12", "lookup is case-insensitive on the name")
    Harness_Equal(SetupHeaderValue(headers, "HOST"), "local", "value is returned trimmed")
    Harness_Equal(SetupHeaderValue(headers, "x-mixed-case"), "Yes", "mixed-case header white space is trimmed")
    Harness_Equal(SetupHeaderValue(headers, "absent"), "", "an absent header is empty")
    Harness_Equal(SetupContentLength(headers), 12, "the Content-Length parses")
    Harness_Equal(SetupContentLength("GET / HTTP/1.1" + CrLf() + "Host: x" + CrLf()), -1, "no Content-Length is -1")

    ' A colon inside the request line (a port, a query) must not be read as a
    ' header, and a header name with no value is not a match.
    tricky = "GET http://h:9/ HTTP/1.1" + CrLf() + "Host: h" + CrLf()
    Harness_Equal(SetupHeaderValue(tricky, "http://h"), "", "a colon in the request line is not a header")
    Harness_Equal(SetupHeaderValue(tricky, "host"), "h", "the real Host header still reads back")
end sub

sub Test_Setup_FormDecoding()
    Harness_Suite("Setup page form decoding")

    Harness_Equal(SetupFormDecode("a%2Fb"), "a/b", "percent escapes decode to text")
    Harness_Equal(SetupFormDecode("a+b"), "a b", "a plus becomes a space")
    Harness_Equal(SetupFormDecode("hello+world%21"), "hello world!", "plus and escapes mix")
    Harness_Equal(SetupFormDecode("100%25"), "100%", "a literal percent round-trips")
    Harness_Equal(SetupFormDecode(""), "", "an empty value stays empty")
    Harness_Equal(SetupFormDecode("%2F%2F"), "//", "escaped slashes decode")

    ' A UTF-8 lead byte is left verbatim rather than guessed at — the store has
    ' to be able to name what it rejects.
    Harness_Equal(SetupPercentDecodeAscii("%C3%A9"), "%C3%A9", "UTF-8 escapes are kept verbatim by the ASCII decoder")
    Harness_Equal(SetupPercentDecodeAscii("a%2Fb%20c"), "a/b c", "the ASCII decoder covers the charset actually used")

    Harness_Equal(SetupHexByte("2F"), 47, "hex pair parses")
    Harness_Equal(SetupHexByte("2f"), 47, "hex pair is case-insensitive")
    Harness_Equal(SetupHexByte("zz"), -1, "a non-hex pair is -1")
    Harness_Equal(SetupHexByte("F"), -1, "a short pair is -1")

    Harness_Equal(SetupReplaceChar("a+b+c", "+", " "), "a b c", "every occurrence is replaced")
    Harness_Equal(SetupReplaceChar("abc", "+", " "), "abc", "no occurrence leaves the text alone")
    Harness_Equal(SetupReplaceChar("abc", "", "x"), "abc", "an empty target is a no-op")
end sub

sub Test_Setup_FormValueExtraction()
    Harness_Suite("Setup page form value extraction")

    payload = "manifest=https%3A%2F%2Fa.example%2Fmanifest.json&ref=1"
    Harness_Equal(SetupFormValue(payload, "manifest"), "https://a.example/manifest.json", "the named field decodes and extracts")
    Harness_Equal(SetupFormValue("manifest=https://a.example/manifest.json", "manifest"), "https://a.example/manifest.json", "an already-plain value passes through")
    Harness_Equal(SetupFormValue("manifest=one&manifest=two", "manifest"), "one", "the first value wins")
    Harness_Equal(SetupFormValue("other=https://a.example/m.json", "manifest"), "", "a missing key is empty")
    Harness_Equal(SetupFormValue("", "manifest"), "", "an empty body is empty")
    Harness_Equal(SetupFormValue("manifest=", "manifest"), "", "a key with no value is empty")
end sub

sub Test_Setup_ManifestUrlValidation()
    Harness_Suite("Setup page manifest URL validation")

    okList = [
        "https://a.example/manifest.json"
        "http://a.example/manifest.json"
        "https://a.example/with/path/manifest.json"
        "https://a.example/manifest.json?token=abc"
        "https://a.example:8443/manifest.json"
        "http://a.example:8080/manifest.json"
        "https://a.example/config:with:colons/manifest.json"
    ]
    for each url in okList
        Harness_Equal(SetupValidateManifestUrl(url), url, "valid: " + url)
    end for

    ' Malformed authorities and a filename other than manifest.json are refused.
    bad = [
        ""
        "http://a.example/manifest.json extra"
        "https://a.example"
        "https://a.example/other.json"
        "ftp://a.example/manifest.json"
        "a.example/manifest.json"
        "https:///manifest.json"
        "https://a.example:bad/manifest.json"
        "https://a.example/manifest.json/extra"
    ]
    for each url in bad
        Harness_Equal(SetupValidateManifestUrl(url), "", "invalid: " + "'" + url + "'")
    end for

    trimmed = "  https://a.example/manifest.json  "
    Harness_Equal(SetupValidateManifestUrl(trimmed), "https://a.example/manifest.json", "surrounding space is trimmed")
    Harness_Equal(SetupValidateManifestUrl(bad), "", "a non-string value is rejected")
end sub

sub Test_Setup_MatchesTheStore()
    Harness_Suite("Setup page and AddonsStore agree on URLs")

    ' The page's fast reject must never bless a URL the store then refuses.
    ' Both run over the same corpus so the two validation layers can only
    ' diverge by editing this test. The page MAY be stricter than the store —
    ' refusing to install is a frustration, promising then refusing is a lie —
    ' so a page-reject/store-accept verdict is named and allowed, not a failure.
    store = AddonsStore(ScriptedTransport([]), invalid, "stremio")
    corpus = [
        "https://a.example/manifest.json"
        "http://a.example/manifest.json"
        "https://a.example/manifest.json?token=abc"
        "https://a.example"
        "https://a.example/other.json"
        "ftp://a.example/manifest.json"
        "https://:8443/manifest.json"
        "http://a.example:8080/manifest.json"
        "https:///manifest.json"
        "http://a.example/manifest.json extra"
        "https://a.example/manifest.json  "
    ]
    for each url in corpus
        page = SetupValidateManifestUrl(url)
        storeOk = store.SanitizeUrl(url) <> ""
        storeHasManifest = store.BaseFromManifestUrl(url) <> ""
        if page <> ""
            if storeOk and storeHasManifest
                Harness_Ok(true, "agreed valid: " + url)
            else
                Harness_Ok(false, "page blessed a URL the store refuses (" + url + "): sanitize=" + store.SanitizeUrl(url) + " base=" + store.BaseFromManifestUrl(url))
            end if
        else if storeOk and storeHasManifest
            Harness_Ok(true, "page is stricter than the store (allowed): " + url)
        else
            Harness_Ok(true, "agreed rejected: " + url)
        end if
    end for
end sub

sub Test_Setup_LanAddress()
    Harness_Suite("Setup page LAN address selection")

    Harness_Equal(SetupLanAddress({}), "", "no interfaces means no address")
    Harness_Equal(SetupLanAddress(invalid), "", "invalid input means no address")
    Harness_Equal(SetupLanAddress({ "wifi": "192.168.1.5" }), "192.168.1.5", "a single wifi address wins")
    Harness_Equal(SetupLanAddress({ "loop": "127.0.0.1" }), "", "loopback is skipped")
    Harness_Equal(SetupLanAddress({ "v6": "fe80::1" }), "", "IPv6 is skipped")
    Harness_Equal(SetupLanAddress({ "loop": "127.0.0.1", "wifi": "10.0.0.7", "v6": "fe80::1" }), "10.0.0.7", "the first usable address wins")
    Harness_Equal(SetupLanAddress({ "a": "" }), "", "an empty address is skipped")

    Harness_Ok(SetupIsLanIp("192.168.1.5"), "a private IPv4 is a LAN address")
    Harness_Ok(not SetupIsLanIp("127.0.0.1"), "loopback is not")
    Harness_Ok(not SetupIsLanIp("fe80::1"), "IPv6 is not")
    Harness_Ok(not SetupIsLanIp(""), "empty is not")
    Harness_Ok(not SetupIsLanIp(invalid), "invalid is not")

    Harness_Equal(SetupAddressText("192.168.1.5"), "http://192.168.1.5:8744", "the address embeds the port")
    Harness_Equal(SetupAddressText(""), "", "no IP means no address text")
    Harness_Equal(SetupServerPort(), 8744, "the documented port is the one served")
end sub

sub Test_Setup_HttpResponse()
    Harness_Suite("Setup page HTTP response shape")

    body = SetupHtmlPage()
    response = SetupHttpResponse("200 OK", body)

    Harness_Ok(response.Left(8) = "HTTP/1.1", "the status line leads the response")
    Harness_Ok(response.InStr(CrLf() + CrLf()) > 0 and response.InStr(CrLf() + CrLf()) < response.Len(), "headers are separated from the body")
    Harness_Ok(response.InStr("Content-Length: " + Len(body).ToStr()) >= 0, "Content-Length matches the body exactly")
    Harness_Ok(response.InStr("Connection: close") >= 0, "the connection is closed after the response")
    Harness_Ok(response.InStr("Cache-Control: no-store") >= 0, "the response is not cached")
    Harness_Ok(response.InStr("Content-Type: text/html; charset=utf-8") >= 0, "the content type is declared")
    Harness_Equal(response.InStr(body), response.Len() - Len(body), "the body is exactly the trailing portion")

    ' Everything the page ships must be ASCII: the response's Content-Length is
    ' Len(body), and a non-ASCII character would make the byte count one short.
    CheckSetupPageAsciiOnly("the form page", SetupHtmlPage())
    CheckSetupPageAsciiOnly("the sent page", SetupHtmlSent())
    CheckSetupPageAsciiOnly("the busy page", SetupHtmlBusy())
    CheckSetupPageAsciiOnly("the error page", SetupHtmlStatus("400"))

    Harness_Equal(SetupStatusText("409"), "409 Conflict", "the busy status line is the busy page's")
end sub

sub Test_Setup_HtmlPages()
    Harness_Suite("Setup page HTML content")

    page = SetupHtmlPage()
    Harness_Ok(page.InStr("name='manifest'") >= 0, "the form field is named manifest")
    Harness_Ok(page.InStr("method='POST'") >= 0, "the form posts")
    Harness_Ok(page.InStr("action='/'") >= 0, "the form posts to the root")

    sent = SetupHtmlSent()
    Harness_Ok(sent.InStr("Install another") >= 0, "a sent page offers to install another")

    busy = SetupHtmlBusy()
    Harness_Ok(busy.InStr("already running") >= 0, "a busy page tells the truth")

    badStatus = SetupHtmlStatus("400")
    Harness_Ok(badStatus.InStr("Bad request") >= 0, "the 400 page names the problem")
    Harness_Equal(SetupHtmlStatus("200"), SetupHtmlStatus("400"), "unknown codes fall back to the generic page")
end sub

' ASCII check over the exact byte streams the server will send. Done as a
' separate step rather than inline so the suite reads as one claim: every
' SetupHtml* output stays single-byte.
sub CheckSetupPageAsciiOnly(what as string, text as string)
    ok = true
    for i = 0 to text.Len() - 1
        if Asc(text.Mid(i, 1)) > 127 then ok = false
    end for
    Harness_Ok(ok, what + " is ASCII only")
end sub
