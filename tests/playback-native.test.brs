sub Test_PlaybackOpaqueEpisodePath()
    Harness_Suite("Opaque episode IDs remain one stream endpoint path segment")
    address = "https://addon.example/provider?config=fixture"
    expected = "https://addon.example/provider/stream/series%2Fcustom/show%2Fepisode%3F%3A1%3A2%23tag%26x%3D%2520.json?config=fixture"
    script = [{ method: "GET", url: expected, ok: true, status: 200, json: { streams: [{ url: "https://media.example/episode.mkv" }] }, error: "" }]
    transport = ScriptedTransport(script)
    store = PlaybackStore(transport)
    result = store.Streams(address, "series/custom", "show/episode?:1:2#tag&x=%20")
    Harness_Ok(result.ok, "provider receives the intended encoded endpoint")
    Harness_Equal(transport.log[0].url, expected, "reserved ID characters cannot change path or query")
    Harness_Equal(result.streams[0].url, "https://media.example/episode.mkv", "correct episode streams are returned")

    ordinaryExpected = "https://addon.example/stream/movie/tt0133093.json"
    ordinaryHttp = ScriptedTransport([{ method: "GET", url: ordinaryExpected, ok: true, status: 200, json: { streams: [] }, error: "" }])
    ordinary = PlaybackStore(ordinaryHttp).Streams("https://addon.example", "movie", "tt0133093")
    Harness_Ok(ordinary.ok, "ordinary IMDb movie identifiers retain their URL")
    Harness_Equal(ordinaryHttp.log[0].url, ordinaryExpected, "ordinary URL is unchanged")
end sub

' A deterministic HTTP boundary: it returns the provider payload only when the
' caller's real forwarded deadline can accommodate the simulated response delay.
' No wall-clock sleep, paid account or resolver request is involved.
function AvailabilityDeadlineClient(responseDelayMs as integer, log as object) as object
    client = { responseDelayMs: responseDelayMs, log: log }
    client.request = function(method as string, url as string, headers = invalid as dynamic, body = invalid as dynamic, timeoutMs = 15000 as integer) as object
        m.log.Push({ method: method, url: url, timeoutMs: timeoutMs, headers: headers, body: body })
        if timeoutMs < m.responseDelayMs
            return { ok: false, status: 0, body: "", error: "request timed out" }
        end if
        payload = { streams: [{ name: "[TB+] Torrentio 4k", url: "https://media.example/original.mkv", behaviorHints: { filename: "Example.2160p.HEVC.DDP5.1.mkv" } }] }
        return { ok: true, status: 200, body: FormatJson(payload), error: "" }
    end function
    return client
end function

sub Test_PlaybackAvailabilityDeadline()
    Harness_Suite("Provider discovery accommodates a 30-second response without extending metadata waits")
    log = []
    http = Transport(AvailabilityDeadlineClient(30000, log))
    ordinary = http.Get("https://addon.example/manifest.json")
    Harness_Ok(not ordinary.ok, "ordinary metadata deadline still rejects a 30-second response")
    Harness_Equal(log[0].timeoutMs, 15000, "metadata GET keeps the ordinary deadline")

    answer = PlaybackStore(http).Streams("https://addon.example/configured?fixture=1", "movie", "tt0000001")
    Harness_Ok(answer.ok, "real stream store and transport accept a response within the provider budget")
    Harness_Equal(answer.streams.Count(), 1, "JSON response is parsed into one stream")
    Harness_Equal(answer.streams[0].url, "https://media.example/original.mkv", "direct original URL is preserved")
    Harness_Equal(log[1].timeoutMs, 45000, "only source lookup receives the 45-second budget")
    Harness_Equal(log[1].url, "https://addon.example/configured/stream/movie/tt0000001.json?fixture=1", "source endpoint retains its configuration")
    Harness_Equal(log[1].headers, invalid, "timeout override adds no provider credentials")
    Harness_Equal(log[1].body, invalid, "source discovery remains a GET without a body")

    delayedLog = []
    delayed = PlaybackStore(Transport(AvailabilityDeadlineClient(45001, delayedLog))).Streams("https://addon.example", "movie", "tt0000001")
    Harness_Ok(not delayed.ok, "a source that exceeds the new ceiling still fails")
    Harness_Equal(delayed.error, "request timed out", "deadline failure is surfaced rather than treated as an empty success")
    Harness_Equal(delayedLog.Count(), 1, "transport wrapper issues the source request once")
end sub

sub Test_NativePlayback()
    Harness_Suite("Direct native playback needs no streaming server")
    store = PlaybackStore(ScriptedTransport([]))
    url = "https://media.example/object?filename=Movie.2160p.HEVC.mkv&signature=sample"
    direct = store.ResolvePlayback("", { url: url, infoHash: "also-a-hash" })
    Harness_Ok(direct.ok, "HTTPS source resolves without a server")
    Harness_Equal(direct.url, url, "signed URL is preserved exactly")
    Harness_Equal(direct.mode, "direct", "direct mode is explicit")
    Harness_Equal(direct.streamFormat, "mkv", "query filename resolves MKV")
    Harness_Equal(store.transport.log.Count(), 0, "no server or transcode request")
    Harness_Equal(direct.headers.Count(), 0, "no headers from a prior source")
    Harness_Ok(not store.IsTorrent({ url: url, infoHash: "also-a-hash" }), "direct URL takes precedence")
    Harness_Equal(store.StreamFormat({ behaviorHints: { filename: "Original.mkv" } }, "https://media.example/converted.mp4"), "mp4", "actual delivery extension overrides an original filename")
    Harness_Equal(store.StreamFormat({ behaviorHints: { filename: "Movie.mkv" } }, "https://media.example/object?token=fixture.mpd"), "mkv", "signed token cannot turn a movie into DASH")
    Harness_Equal(store.StreamFormat(invalid, "https://media.example/object?filename=Movie%2Emkv"), "mkv", "encoded filename extension is recognized")
    Harness_Equal(store.StreamFormat(invalid, "https://media.example/movie.mp4#unused.mpd"), "mp4", "fragment is not a delivered media format")

    bad = store.ResolvePlayback("", { url: "magnet:?xt=urn:btih:sample" })
    Harness_Ok(not bad.ok, "magnet is not handed to native Video")
    Harness_Equal(bad.error, "unsupported stream URL scheme", "unsupported URL has a specific cause")
    malformed = store.ResolvePlayback("", { url: 123 })
    Harness_Ok(not malformed.ok, "malformed URL does not crash")

    torrent = store.ResolvePlayback("", { infoHash: "sample" })
    Harness_Ok(not torrent.ok, "torrent-only source cannot silently use a server")
    Harness_Equal(torrent.error, "no streaming server address", "server requirement is explicit")
end sub

sub Test_NativePlaybackHeaders()
    Harness_Suite("Per-source headers reject injection and transport overrides")
    store = PlaybackStore(ScriptedTransport([]))
    request = { "User-Agent": "Stremio", "Authorization": "Bearer fixture", "Host": "other.example", "Range": "bytes=0-", "Connection": "close", "Content-Length": "999", "X-Invalid": "one" + Chr(13) + Chr(10) + "Injected:yes", "Bad Header": "bad", "Numeric": 5 }
    source = { url: "https://media.example/file.mp4", behaviorHints: { proxyHeaders: { request: request } } }
    result = store.ResolvePlayback("", source)
    Harness_Equal(result.headers.Count(), 2, "only valid application headers remain")
    foundAgent = false
    foundAuth = false
    for each header in result.headers
        if LCase(header) = "user-agent:stremio" then foundAgent = true
        if LCase(header) = "authorization:bearer fixture" then foundAuth = true
    end for
    Harness_Ok(foundAgent, "documented user agent is forwarded")
    Harness_Ok(foundAuth, "per-source provider authorization is forwarded")
    nextSource = store.ResolvePlayback("", { url: "https://other.example/file.mp4" })
    Harness_Equal(nextSource.headers.Count(), 0, "headers are not retained between sources")
end sub

sub Test_PlaybackFacts()
    Harness_Suite("Playback facts distinguish labels from measured video")
    Harness_Equal(PlaybackInfo_SourceLabel({ title: "Movie.2160p.HEVC.mkv" }), "2160p / UHD (source label)", "2160p title is explicitly only a label")
    Harness_Equal(PlaybackInfo_SourceLabel({ title: 2160 }), "Unspecified", "malformed labels are harmless")
    Harness_Equal(PlaybackInfo_SourceLabel({ title: "Movie.1080p.AAC.384kbps" }), "1080p (source label)", "audio bitrate substring cannot claim 4K")
    Harness_Equal(PlaybackInfo_ResumeOffset("900"), 0, "untyped resume values are rejected")
    Harness_Equal(PlaybackInfo_ResumeOffset(-1), 0, "negative resume values cannot alter live behavior")
    Harness_Equal(PlaybackInfo_ResumeOffset(900.5), 900.5, "numeric fractional resume values are preserved")
    Harness_Equal(PlaybackInfo_Segment({ width: 3840, height: 2160, hdrModeStr: "hdr10" }), "Playing segment: 3840 x 2160 | HDR10", "actual segment dimensions and HDR are displayed")
    Harness_Equal(PlaybackInfo_Segment({ width: 1920, height: 1080, hdrModeStr: "none" }), "Playing segment: 1920 x 1080 | SDR", "1080 playback remains visibly 1080")
    Harness_Equal(PlaybackInfo_Segment(invalid), "Playing resolution: not reported by Roku for this source.", "progressive file resolution is never inferred from HDMI")
    Harness_Equal(PlaybackInfo_Segment({ width: "3840", height: "2160" }), "Playing resolution: not reported by Roku for this source.", "untyped dimensions are not measurements")
    Harness_Equal(PlaybackInfo_Codec("hevc_b"), "HEVC / H.265", "live HEVC codec is mapped")
    Harness_Equal(PlaybackInfo_Codec("eac3", true), "Dolby Digital Plus (E-AC3)", "live DD+ codec is mapped without claiming channels")
    Harness_Equal(PlaybackInfo_Codec("https://secret.example/key"), "Other reported codec", "arbitrary diagnostic text is never displayed")
    Harness_Ok(PlaybackInfo_ErrorMessage(-5, "", true).InStr("HEVC") >= 0, "unsupported source suggests compatible video")
    Harness_Ok(PlaybackInfo_ErrorMessage(-2, "http", false).InStr("timed out") >= 0, "network failures have actionable wording")
end sub

sub Test_PlaybackDeviceFacts()
    Harness_Suite("HDMI output and device capability do not prove source resolution")
    fourK = PlaybackInfo_DeviceFacts({ outputMode: "2160p60", hevcSupported: true, hdr10Supported: true })
    Harness_Ok(fourK.InStr("2160p60 (signal only)") >= 0, "4K output is explicitly labelled a signal")
    Harness_Ok(fourK.InStr("HEVC yes | HDR10 yes") >= 0, "reported capabilities are visible")
    hdr = PlaybackInfo_DeviceFacts({ outputMode: "2160p60b10", hevcSupported: true, hdr10Supported: true })
    Harness_Ok(hdr.InStr("2160p60b10 (signal only)") >= 0, "documented 4K HDR output is still labelled a signal")
    Harness_Equal(PlaybackInfo_OutputMode("2160p30Dv"), "2160p30dv", "documented Dolby Vision mode is safely normalized")
    hd = PlaybackInfo_DeviceFacts({ outputMode: "1080p", hevcSupported: true, hdr10Supported: false })
    Harness_Ok(hd.InStr("1080p (signal only)") >= 0, "1080 output stays 1080 despite HEVC support")
    Harness_Ok(hd.InStr("HEVC yes | HDR10 no") >= 0, "separate HDR capability is respected")
    unknown = PlaybackInfo_DeviceFacts({ outputMode: "https://secret.example/token", hevcSupported: "true", hdr10Supported: 1 })
    Harness_Ok(unknown.InStr("secret") < 0, "unexpected output strings cannot expose arbitrary content")
    Harness_Ok(unknown.InStr("HEVC not reported | HDR10 not reported") >= 0, "non-boolean capabilities are not claimed")
    Harness_Ok(PlaybackInfo_DeviceFacts(invalid).InStr("not reported") >= 0, "missing device data is harmless")
end sub

Test_PlaybackOpaqueEpisodePath()
Test_PlaybackAvailabilityDeadline()
Test_NativePlayback()
Test_NativePlaybackHeaders()
Test_PlaybackFacts()
Test_PlaybackDeviceFacts()
Test_PlayerNativeHandoff()
Test_PlayerEnglishOnlyAudio()
Test_PlayerPendingTaskNotifications()
Test_PlayerExplicitFourKPolicy()
Test_PlayerLateSubtitleChoice()
Test_PlayerPreplayCaptionPreference()
Test_PlayerResolutionAndFormatError()
Test_PlayerQueuedPreviousMovie()
Test_PlayerLoadingFeedback()
Test_AutomaticPlayback()
Test_AudioTrackContinuity()
Test_SourceProofMemory()
Harness_Finish()
if m.failed > 0
    failed = invalid
    ignored = failed.assertion
end if
