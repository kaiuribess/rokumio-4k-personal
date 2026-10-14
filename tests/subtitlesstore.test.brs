' SubtitlesStore unit tests.
'
' Subtitles() talks to an add-on through the scripted transport and asserts the
' requested endpoint; PickTrack/TrackLang are pure picking logic exercised with
' no transport at all.

function SubtitleTrack(id as string, url as string, lang as dynamic, langName = invalid as dynamic) as object
    track = { id: id, url: url }
    if lang <> invalid then track.lang = lang
    if langName <> invalid then track.langName = langName
    return track
end function

sub Test_Subtitles_FetchesList()
    Harness_Suite("SubtitlesStore.Subtitles fetches the add-on caption list")
    address = "https://opensubtitles-v3.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/subtitles/movie/tt0133093.json"
            ok: true
            status: 200
            json: {
                subtitles: [
                    { id: "1", url: "https://dl.addon/en.srt", lang: "en", langName: "English" }
                    { id: "2", url: "https://dl.addon/es.srt", lang: "es", langName: "Spanish" }
                ]
            }
            error: ""
        }
    ]
    store = SubtitlesStore(ScriptedTransport(script))
    result = store.Subtitles(address, "movie", "tt0133093")

    Harness_Ok(result.ok, "subtitles ok")
    Harness_Equal(result.subtitles.Count(), 2, "two tracks returned")
    Harness_Equal(result.subtitles[0].url, "https://dl.addon/en.srt", "sideload url intact")
    Harness_Equal(result.subtitles[1].lang, "es", "lang intact")
end sub

sub Test_Subtitles_Validates()
    Harness_Suite("SubtitlesStore.Subtitles rejects a missing subtitles array")
    script = [{ method: "GET", ok: true, status: 200, json: {}, error: "" }]
    store = SubtitlesStore(ScriptedTransport(script))
    result = store.Subtitles("https://addon.example.com", "movie", "tt0133093")

    Harness_Ok(not result.ok, "subtitles rejected")
    Harness_Equal(result.error, "subtitles response missing subtitles", "error names the missing array")
end sub

sub Test_Subtitles_NoAddress()
    Harness_Suite("SubtitlesStore.Subtitles refuses a blank addon address")
    store = SubtitlesStore(ScriptedTransport([]))
    result = store.Subtitles("", "movie", "tt0133093")
    Harness_Ok(not result.ok, "no address refused")
    Harness_Equal(result.error, "no addon address", "error names the missing address")
end sub

sub Test_Subtitles_TypeIdMissing()
    Harness_Suite("SubtitlesStore.Subtitles refuses a missing type or video id")
    store = SubtitlesStore(ScriptedTransport([]))
    result = store.Subtitles("https://addon.example.com", "", "tt0133093")
    Harness_Ok(not result.ok, "blank type refused")
    Harness_Equal(result.error, "type or video id missing", "error names the missing type")
end sub

sub Test_Subtitles_IssuedFlag()
    Harness_Suite("SubtitlesStore.Subtitles separates never-asked from asked-and-failed")
    ' `issued` exists because `status` cannot carry both questions. Transport reports
    ' a NEGATIVE status for every transport failure (its _execute reaches for
    ' GetFailureReason precisely when status < 0), so a -1 sentinel for the
    ' pre-request case was indistinguishable from a real one. These three pin the
    ' distinction: the flag has to be false when we never made the request, and true
    ' even when the transport came back with a negative code.
    store = SubtitlesStore(ScriptedTransport([]))
    result = store.Subtitles("", "movie", "tt0133093")
    Harness_Equal(result.issued, false, "blank address was never issued")

    store = SubtitlesStore(ScriptedTransport([]))
    result = store.Subtitles("https://addon.example.com", "", "tt0133093")
    Harness_Equal(result.issued, false, "blank type was never issued")

    script = [{
        method: "GET"
        url: "https://addon.example.com/subtitles/movie/tt0133093.json"
        ok: false
        status: -7
        json: invalid
        error: "Failed to connect to addon.example.com port 443: Could not connect to server"
    }]
    store = SubtitlesStore(ScriptedTransport(script))
    result = store.Subtitles("https://addon.example.com", "movie", "tt0133093")
    Harness_Equal(result.issued, true, "a refused connection WAS issued")
    Harness_Equal(result.status, -7, "the negative transport status is passed through, not normalised away")
end sub

sub Test_Subtitles_LocalePicksMatch()
    Harness_Suite("SubtitlesStore.PickTrack prefers the device locale language")
    store = SubtitlesStore(ScriptedTransport([]))
    tracks = [
        SubtitleTrack("1", "u1", "es", "Spanish")
        SubtitleTrack("2", "u2", "en", "English")
        SubtitleTrack("3", "u3", "it", "Italian")
    ]
    Harness_Equal(store.PickTrack(tracks, "en_US"), 1, "es_es locale picks the English track")
    Harness_Equal(store.PickTrack(tracks, "es_ES"), 0, "es_ES locale picks the Spanish track")
end sub

sub Test_Subtitles_EnglishFallback()
    Harness_Suite("SubtitlesStore.PickTrack falls back to English")
    store = SubtitlesStore(ScriptedTransport([]))
    tracks = [
        SubtitleTrack("1", "u1", "fr", "French")
        SubtitleTrack("2", "u2", "en", "English")
        SubtitleTrack("3", "u3", "it", "Italian")
    ]
    Harness_Equal(store.PickTrack(tracks, "de_DE"), 1, "unmatched locale falls back to English")
end sub

sub Test_Subtitles_FirstFallback()
    Harness_Suite("SubtitlesStore.PickTrack falls back to the first track")
    store = SubtitlesStore(ScriptedTransport([]))
    tracks = [
        SubtitleTrack("1", "u1", "fr", "French")
        SubtitleTrack("2", "u2", "it", "Italian")
    ]
    Harness_Equal(store.PickTrack(tracks, "de_DE"), 0, "no English falls back to the first track")
end sub

sub Test_Subtitles_PickEmpty()
    Harness_Suite("SubtitlesStore.PickTrack handles empty and invalid lists")
    store = SubtitlesStore(ScriptedTransport([]))
    Harness_Equal(store.PickTrack([], "en_US"), -1, "empty list picks nothing")
    Harness_Equal(store.PickTrack(invalid, "en_US"), -1, "invalid list picks nothing")
    tracks = [SubtitleTrack("1", "u1", "es", "Spanish")]
    Harness_Equal(store.PickTrack(tracks, ""), 0, "blank locale still returns a track")
end sub

sub Test_Subtitles_TrackLangMatchesLang()
    Harness_Suite("SubtitlesStore.TrackLang matches on lang, never langName")
    store = SubtitlesStore(ScriptedTransport([]))
    tracks = [
        SubtitleTrack("1", "u1", invalid, "English")
        SubtitleTrack("2", "u2", "en", "English")
    ]
    Harness_Equal(store.TrackLang(tracks[0]), "", "langName alone yields no code")
    Harness_Equal(store.TrackLang({ lang: "EN" }), "en", "lang lowercased from mixed case")
    Harness_Equal(store.PickTrack(tracks, "en_US"), 1, "English picked from lang, not langName")
end sub

sub Test_Subtitles_TrackLangMissing()
    Harness_Suite("SubtitlesStore.TrackLang returns empty without a lang code")
    store = SubtitlesStore(ScriptedTransport([]))
    Harness_Equal(store.TrackLang({}), "", "no lang")
    Harness_Equal(store.TrackLang(invalid), "", "invalid track")
end sub