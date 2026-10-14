' Transport unit tests.
'
' A fake client stands in for roUrlTransfer: it records every call and answers
' from a small script of { ok, status, body, error } rows, keyed by method and
' optional URL. Transport's own job — forwarding method/url/headers/body to the
' client and normalizing raw results into parsed JSON — is what we lock down
' here. The real client is a thin roUrlTransfer wrapper and is never exercised
' in the interpreter.

function ScriptedHttpClient(script as object, log as object) as object
    client = { _script: script, _log: log }
    client.request = function(method as string, url as string, headers = invalid as dynamic, body = invalid as dynamic, timeoutMs = invalid as dynamic) as object
        m._log.Push({ method: method, url: url, headers: headers, body: body, timeoutMs: timeoutMs })
        for each entry in m._script
            if entry.method = method and (entry.url = invalid or entry.url = url)
                return { ok: entry.ok, status: entry.status, body: entry.body, error: entry.error }
            end if
        end for
        return { ok: false, status: 0, body: "", error: "no scripted response" }
    end function
    client.requestLong = function(method as string, url as string, headers = invalid as dynamic, body = invalid as dynamic) as object
        return m.request(method, url, headers, body)
    end function
    return client
end function

' BrightScript strings cannot embed a literal double-quote, so JSON bodies for
' the fake client are assembled with Chr(34). The raw string is what Transport
' hands to ParseJson, which is exactly the code path under test.
function QuoteString(value as string) as string
    return Chr(34) + value + Chr(34)
end function

sub Test_Transport_Get_ParsesJson()
    Harness_Suite("Transport.Get parses JSON and forwards to the client")
    log = []
    body = "{" + QuoteString("ok") + ":true," + QuoteString("n") + ":3}"
    script = [
        { method: "GET", url: "http://host/health", ok: true, status: 200, body: body, error: "" }
    ]
    transport = Transport(ScriptedHttpClient(script, log))
    result = transport.Get("http://host/health", { "Accept": "application/json" })

    Harness_Ok(result.ok, "ok=true for 200 with JSON")
    Harness_Equal(result.status, 200, "status surfaced")
    Harness_Equal(result.json.ok, true, "json bool parsed")
    Harness_Equal(result.json.n, 3, "json number parsed")
    Harness_Equal(log.Count(), 1, "client called once")
    Harness_Equal(log[0].method, "GET", "method forwarded")
    Harness_Equal(log[0].url, "http://host/health", "url forwarded")
    Harness_Equal(log[0].headers.Accept, "application/json", "headers forwarded")
    Harness_Equal(log[0].timeoutMs, 15000, "ordinary JSON GET retains its 15-second deadline")
end sub

sub Test_Transport_Get_ForwardsTimeout()
    Harness_Suite("JSON GET forwards a dedicated deadline alongside headers and parsing")
    log = []
    body = "{" + QuoteString("streams") + ":[]}"
    transport = Transport(ScriptedHttpClient([{ method: "GET", ok: true, status: 200, body: body, error: "" }], log))
    answer = transport.Get("https://addon.example/stream/movie/tt0000001.json", { "Accept": "application/json" }, 45000)
    Harness_Ok(answer.ok, "extended JSON request is normalized normally")
    Harness_Equal(answer.json.streams.Count(), 0, "JSON parsing still returns the stream array")
    Harness_Equal(log[0].timeoutMs, 45000, "requested stream deadline reaches the HTTP client")
    Harness_Equal(log[0].headers.Accept, "application/json", "headers survive the extra argument")
    Harness_Equal(log[0].body, invalid, "GET does not acquire a request body")
end sub

sub Test_Transport_RejectsBadJson()
    Harness_Suite("Transport flags a 2xx with a non-JSON body as a failure")
    script = [
        { method: "GET", ok: true, status: 200, body: "not-json", error: "" }
    ]
    result = Transport(ScriptedHttpClient(script, [])).Get("http://host/x")

    Harness_Ok(not result.ok, "ok=false when the body is not JSON")
    Harness_Equal(result.error, "invalid JSON response", "error names the problem")
end sub

sub Test_Transport_SkipsParseOnHtmlBody()
    Harness_Suite("Transport names an HTML 2xx the same failure without feeding it to ParseJson")
    ' The dead subtitle endpoint answers its stremio/v1 path with the add-on's
    ' HTML landing page. Result must not hand markup to ParseJson (the Roku
    ' runtime prints a BRIGHTSCRIPT ParseJSON error for every malformed body),
    ' and must still fail with the same error downstream code already keys on.
    scripts = [
        {
            body: "<!DOCTYPE html><html><body>open subtitles</body></html>"
            note: "doctype-first HTML is caught"
        }
        {
            body: "  <html><body>gateway page</body></html>"
            note: "HTML behind leading whitespace is caught too"
        }
    ]
    for each script in scripts
        result = Transport(ScriptedHttpClient([
            { method: "GET", ok: true, status: 200, body: script.body, error: "" }
        ], [])).Get("http://host/x")

        Harness_Ok(not result.ok, "ok=false when a 200 body is HTML (" + script.note + ")")
        Harness_Equal(result.error, "invalid JSON response", "HTML answer names the same failure (" + script.note + ")")
        Harness_Equal(result.json, invalid, "no json is manufactured from markup (" + script.note + ")")
    end for
end sub

sub Test_Transport_HttpError()
    Harness_Suite("Transport surfaces HTTP errors")
    script = [
        { method: "GET", ok: false, status: 500, body: "{}", error: "HTTP 500" }
    ]
    result = Transport(ScriptedHttpClient(script, [])).Get("http://host/x")

    Harness_Ok(not result.ok, "ok=false for a 500")
    Harness_Equal(result.status, 500, "status surfaced")
    Harness_Equal(result.error, "HTTP 500", "error surfaced")
end sub

sub Test_Transport_Post_ForwardsBody()
    Harness_Suite("Transport.Post passes method, url and body to the client")
    log = []
    body = "{" + QuoteString("authKey") + ":" + QuoteString("k1") + "}"
    script = [
        { method: "POST", ok: true, status: 200, body: body, error: "" }
    ]
    result = Transport(ScriptedHttpClient(script, log)).Post("http://host/login", { type: "guest" })

    Harness_Ok(result.ok, "post ok")
    Harness_Equal(result.json.authKey, "k1", "json parsed")
    Harness_Equal(log[0].method, "POST", "method forwarded")
    Harness_Equal(log[0].url, "http://host/login", "url forwarded")
    Harness_Equal(log[0].body.type, "guest", "body forwarded to the client")
end sub

sub Test_Transport_PostLong_RoutesLongRequest()
    Harness_Suite("Transport.PostLong rides the long-window client request")
    log = []
    body = "{" + QuoteString("collection") + ":7}"
    script = [
        { method: "POST", ok: true, status: 200, body: body, error: "" }
    ]
    result = Transport(ScriptedHttpClient(script, log)).PostLong("http://host/abc/collection", { collection: 7 })

    Harness_Ok(result.ok, "postLong ok")
    Harness_Equal(result.json.collection, 7, "json parsed")
    Harness_Equal(log[0].method, "POST", "method forwarded")
    Harness_Equal(log[0].url, "http://host/abc/collection", "url forwarded")
    Harness_Equal(log[0].body.collection, 7, "body forwarded to the client")
end sub

sub Test_Transport_RetryPolicy()
    Harness_Suite("Transport retries transport-level failures and nothing else")
    ' A negative status is the transfer never completing (refused connect -7,
    ' DNS -6, TLS). Those are the measured concurrency collisions, so they retry.
    Harness_Ok(TransportFailureIsRetryable(-7), "-7 (refused connect) is retryable")
    Harness_Ok(TransportFailureIsRetryable(-6), "-6 (DNS failure) is retryable")
    Harness_Ok(TransportFailureIsRetryable(-35), "-35 (TLS connect) is retryable")
    ' Everything else is an answer or a wait that must not be multiplied.
    Harness_Ok(not TransportFailureIsRetryable(0), "status 0 (timeout) is NOT retryable")
    Harness_Ok(not TransportFailureIsRetryable(200), "200 is NOT retryable")
    Harness_Ok(not TransportFailureIsRetryable(404), "404 is NOT retryable")
    Harness_Ok(not TransportFailureIsRetryable(500), "500 is NOT retryable")
end sub

sub Test_Transport_RetryBudget()
    Harness_Suite("Transport's retry backoff grows linearly")
    ' The attempt cap (MAX_TRANSPORT_ATTEMPTS) is a file-scope const, which the
    ' interpreter does not expose to this scope; tests/run.js pins it instead.
    Harness_Equal(TransportRetryBackoffMs(1), 250, "the first retry waits one base unit")
    Harness_Equal(TransportRetryBackoffMs(2), 500, "the second retry waits two base units")
    Harness_Equal(TransportRetryBackoffMs(3), 750, "the third retry waits three base units")
end sub

sub Test_Transport_GetRaw_ReturnsBodyUnparsed()
    Harness_Suite("Transport.GetRaw returns the body verbatim instead of parsing it as JSON")
    log = []
    manifest = "#EXTM3U" + Chr(10) + "#EXT-X-VERSION:3" + Chr(10) + "#EXTINF:9.0," + Chr(10) + "seg1.ts"
    script = [
        { method: "GET", url: "http://host/abc/hls.m3u8", ok: true, status: 200, body: manifest, error: "" }
    ]
    result = Transport(ScriptedHttpClient(script, log)).GetRaw("http://host/abc/hls.m3u8")

    Harness_Ok(result.ok, "ok for a 200 whose body is not JSON at all")
    Harness_Equal(result.status, 200, "status surfaced")
    Harness_Equal(result.body, manifest, "manifest returned verbatim, newlines and all")
    Harness_Equal(log[0].method, "GET", "method forwarded")
    ' The same bytes through Get, which is the whole reason GetRaw exists. If
    ' this ever stops failing, GetRaw has been folded into Get and the readiness
    ' probe is reading "invalid JSON response" instead of the server's answer.
    jsonResult = Transport(ScriptedHttpClient(script, log)).Get("http://host/abc/hls.m3u8")
    Harness_Ok(not jsonResult.ok, "Get rejects this very body as unparseable JSON - which is the bug GetRaw exists to route around")
end sub

sub Test_Transport_GetRaw_ForwardsTimeout()
    Harness_Suite("Transport.GetRaw forwards a caller-supplied timeout and otherwise keeps the default")
    log = []
    script = [
        { method: "GET", ok: true, status: 200, body: "#EXTM3U", error: "" }
    ]
    transport = Transport(ScriptedHttpClient(script, log))
    transport.GetRaw("http://host/abc/hls.m3u8", 4000)
    transport.GetRaw("http://host/abc/hls.m3u8")

    ' The probe's own timeout has to actually arrive. The wait is bounded by
    ' attempts x (timeout + interval) and there is no clock in the loop, so a
    ' default that quietly won would hold the player for over a minute across
    ' four attempts — the exact stall the probe exists to prevent.
    Harness_Equal(log[0].timeoutMs, 4000, "the probe's short timeout reaches the client")
    Harness_Equal(log[1].timeoutMs, 15000, "no timeout given keeps the 15s default, so every other caller's behaviour is unchanged")
    ' ...and no headers given means none sent, so adding the parameter did not
    ' start attaching something to the sixteen callers that never asked for it.
    Harness_Ok(log[1].headers = invalid, "no headers given still sends none")
end sub

' The forced-metadata read in WarmEngine is a ranged GET on the streaming
' server's torrent route, which serves a feature-sized body. A Range header is
' the only thing standing between that readiness check and a request to buffer
' an entire film into a string, so the header has to survive the trip down
' through GetRaw and out to the client.
sub Test_Transport_GetRaw_ForwardsHeaders()
    Harness_Suite("Transport.GetRaw forwards a Range header to the client")
    log = []
    script = [
        { method: "GET", url: "http://host/abc/0", ok: true, status: 206, body: "", error: "" }
    ]
    transport = Transport(ScriptedHttpClient(script, log))
    result = transport.GetRaw("http://host/abc/0", 8000, { "Range": "bytes=0-65535" })

    Harness_Ok(result.ok, "a 206 partial response counts as ok")
    Harness_Equal(log[0].headers.Range, "bytes=0-65535", "the Range header reaches the client, which is what keeps this from reading the whole feature")
    Harness_Equal(log[0].timeoutMs, 8000, "and the timeout reaches it alongside")
end sub

sub Test_Transport_Head_SendsHeadAndStaysRaw()
    Harness_Suite("Transport.Head asks for headers only and leaves the empty body unparsed")
    log = []
    script = [
        { method: "HEAD", url: "http://host/abc/4", ok: true, status: 200, body: "", error: "" }
    ]
    transport = Transport(ScriptedHttpClient(script, log))

    result = transport.Head("http://host/abc/4")

    Harness_Ok(result.ok, "ok on a 200")
    Harness_Equal(result.status, 200, "status surfaced")
    ' Raw, like GetRaw. A HEAD has no body, so Result()'s JSON parse would
    ' report "invalid JSON response" for a request that succeeded — which is how
    ' a working warm-up gets reported as a broken one.
    Harness_Equal(result.error, "", "no error invented from an empty body")
    Harness_Equal(log[0].method, "HEAD", "the method reaches the client as HEAD")
    Harness_Ok(result.json = invalid, "and the result is raw-shaped, not parsed")
end sub

sub Test_Transport_Head_ForwardsTimeout()
    Harness_Suite("Transport.Head forwards a caller-supplied timeout and otherwise keeps the default")
    log = []
    script = [
        { method: "HEAD", ok: true, status: 200, body: "", error: "" }
    ]
    transport = Transport(ScriptedHttpClient(script, log))
    transport.Head("http://host/abc/4", 8000)
    transport.Head("http://host/abc/4")

    ' The warm-up's ceiling has to arrive, or a cold engine eats the 15s default
    ' on top of the probe loop that is already waiting behind it.
    Harness_Equal(log[0].timeoutMs, 8000, "the warm-up's timeout reaches the client")
    Harness_Equal(log[1].timeoutMs, 15000, "no timeout given keeps the 15s default, so every other caller is unchanged")
end sub

sub Test_Transport_EndpointUrl()
    Harness_Suite("Transport.EndpointUrl inserts the endpoint path before the query string")
    transport = Transport(ScriptedHttpClient([], []))

    Harness_Equal(transport.EndpointUrl("https://host", "/catalog/movie/top/skip=0.json"), "https://host/catalog/movie/top/skip=0.json", "no query: plain append")
    Harness_Equal(transport.EndpointUrl("https://host?provider=yts,ezrv", "/stream/movie/tt1.json"), "https://host/stream/movie/tt1.json?provider=yts,ezrv", "query preserved after the endpoint path")
    Harness_Equal(transport.EndpointUrl("https://host/path?provider=yts&quality=1080p", "/manifest.json"), "https://host/path/manifest.json?provider=yts&quality=1080p", "multi-arg query preserved")
end sub
