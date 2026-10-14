' Protocol regressions for a standalone native HTTP addon client.
sub Test_NativeAddons_All()
    Test_NativeAddons_ConfiguredUrls()
    Test_NativeAddons_CatalogPagination()
    Test_NativeAddons_OpaqueEpisodes()
    Test_NativeAddons_SetupOrigins()
    Test_NativeAddons_Diagnostics()
    Test_NativeAddons_ManifestFailures()
    Test_NativeAddons_MalformedRows()
    Test_NativeAddons_EmptyJson()
    Test_NativeAddons_MalformedEpisodes()
end sub

sub Test_NativeAddons_MalformedEpisodes()
    Harness_Suite("Native series metadata filters malformed episodes before typed UI fields")
    meta = { id: "provider:series", type: "series", name: "Series", videos: [
        invalid
        "not an episode"
        { season: "unknown", episode: 1 }
        { season: 1.5, episode: 1 }
        { season: -1, episode: 1 }
        { season: 1 }
        { season: 1, episode: "2147483648" }
        { id: "opaque/first", season: 1.0, episode: 1.0, title: "Pilot", description: "First synopsis" }
        { season: "02", episode: "2", title: "Second", description: 42 }
        { id: "opaque/special", season: 0, episode: 1, title: "Special" }
    ] }
    store = EpisodesStore(ScriptedTransport([{ ok: true, status: 200, json: { meta: meta }, error: "" }]))
    answer = store.GetMeta("https://addon.example", "series", meta.id)
    Harness_Ok(answer.ok, "valid episodes survive alongside malformed entries")
    Harness_Equal(answer.meta.videos.Count(), 3, "null, wrong types, fractions, negatives and overflow removed")
    first = store.FirstEpisode(answer.meta)
    Harness_Equal(first.id, "opaque/first", "opaque provider ID preserved")
    Harness_Equal(first.name, "Pilot", "standard title preserved")
    Harness_Equal(first.overview, "First synopsis", "standard description preserved")
    Harness_Equal(first.season, 1, "whole float season becomes integer")
    Harness_Ok(Type(first.season) <> "Float" and Type(first.season) <> "roFloat" and Type(first.season) <> "Double", "ordinal no longer carries floating field type")
    second = store.EpisodesForSeason(answer.meta, 2)[0]
    Harness_Equal(second.episode, 2, "digit-string episode becomes integer")
    Harness_Equal(second.id, "provider:series:2:2", "absent provider ID gets the standard fallback")
    Harness_Equal(second.overview, "", "non-text synopsis cannot reach a text field")
    Harness_Equal(store.ResolveVideoId(meta.id, 1, 1, answer.meta), "opaque/first", "stream discovery retains opaque normalized episode ID")
    none = EpisodesStore(ScriptedTransport([{ ok: true, status: 200, json: { meta: { videos: [invalid, "bad", { season: 1.2, episode: 1 }] } }, error: "" }])).GetMeta("https://addon.example", "series", "s")
    Harness_Ok(not none.ok, "a series with no usable episodes fails before UI rendering")
    Harness_Equal(none.error, "series meta missing usable videos", "empty normalized series has a readable failure")
    raw = { videos: [invalid, "bad", { season: "2", episode: "3" }] }
    Harness_Equal(store.Seasons(raw).Count(), 1, "pure season helper also tolerates malformed cached metadata")
    Harness_Equal(store.EpisodesForSeason(raw, 2).Count(), 1, "pure episode helper also tolerates malformed cached metadata")
end sub

sub Test_NativeAddons_ManifestFailures()
    Harness_Suite("Native addon installer rejects unusable payloads before persistence")
    broken = [
        ["not a manifest object"]
        { id: 7, name: "Wrong identity type" }
        { id: "missing.resources", name: "Missing", types: ["movie"] }
        { id: "invalid.types", name: "Invalid", types: "movie", resources: ["stream"] }
        { id: "invalid.resources", name: "Invalid", types: ["movie"], resources: [{ name: 42 }] }
        { id: "invalid.catalogs", name: "Invalid", types: ["movie"], resources: ["stream"], catalogs: "catalogs" }
    ]
    for each manifest in broken
        registry = MockRegistry()
        addons = AddonsStore(ScriptedTransport([{ ok: true, status: 200, json: manifest, error: "" }]), registry)
        answer = addons.Install("https://addon.example/configured/manifest.json")
        Harness_Ok(not answer.ok and answer.error <> "", "invalid shape gives a readable install failure")
        Harness_Equal(registry.values["addons"], invalid, "invalid shape is never persisted")
    end for
    empty = AddonsStore(ScriptedTransport([{ ok: true, status: 200, json: invalid, error: "" }])).Install("https://addon.example/manifest.json")
    Harness_Equal(empty.error, "manifest response was empty", "empty successful response has a specific failure")
    onlyStreams = { id: "streams.only", name: "Private stream source", types: ["movie", "series"], resources: ["stream"], idPrefixes: ["tt"] }
    addons = AddonsStore(ScriptedTransport([{ ok: true, status: 200, json: onlyStreams, error: "" }]))
    answer = addons.Install("https://addon.example/opaque/manifest.json")
    Harness_Ok(answer.ok, "stream-only manifest does not need catalogs")
    record = addons.Get("streams.only")
    Harness_Equal(record.catalogs.Count(), 0, "absent stream-source catalogs become an empty list")
    Harness_Ok(addons.SupportsResource(record.resources, record.types, record.idPrefixes, "stream", "movie", "tt0000001"), "stream-only manifest participates in IMDb discovery")
    Harness_Ok(addons.SupportsResource(record.resources, record.types, record.idPrefixes, "stream", "series", "tt0000002:1:3"), "same manifest participates in episode discovery")
    catalog = CatalogStore(ScriptedTransport([{ ok: true, status: 200, json: ["not a manifest"], error: "" }]))
    Harness_Ok(not catalog.Manifest("https://addon.example").ok, "catalog manifest loader handles arrays without crashing")
end sub

sub Test_NativeAddons_MalformedRows()
    Harness_Suite("Native addon catalogs skip malformed rows without losing valid titles")
    malformedCatalogs = [invalid, 42, { id: "bad.type", type: 3 }, { type: "movie" }, { id: "top", type: "movie", extra: [invalid, { name: 3 }, "search"] }]
    addons = AddonsStore(ScriptedTransport([]))
    normalized = addons.NormalizeCatalogNames(malformedCatalogs, "Provider")
    Harness_Equal(normalized.Count(), 1, "only usable catalog descriptor remains")
    Harness_Equal(normalized[0].name, "Provider", "catalog name has a readable fallback")
    Harness_Equal(normalized[0].extra.Count(), 1, "malformed extras removed")
    Harness_Ok(addons.CatalogCapabilities(normalized[0]).search, "bare legacy search extra still works after normalization")
    catalog = CatalogStore(ScriptedTransport([{ ok: true, status: 200, json: { metas: [invalid, 4, { id: "bad" }, { id: 3, name: "Bad" }, { id: "tt0000001", name: "Valid" }] }, error: "" }]))
    answer = catalog.Search("https://addon.example", "movie", "one & two/three")
    Harness_Ok(answer.ok, "one bad row does not fail the whole search")
    Harness_Equal(answer.metas.Count(), 1, "only valid title returned")
    Harness_Equal(answer.metas[0].type, "movie", "missing title type inherits requested type")
    Harness_Equal(catalog.transport.log[0].url, "https://addon.example/catalog/movie/top/search=one%20%26%20two%2Fthree.json", "remote query characters remain one encoded value")
end sub

sub Test_NativeAddons_EmptyJson()
    Harness_Suite("Native addon JSON transport rejects an empty success but preserves HEAD")
    client = ScriptedHttpClient([
        { method: "GET", ok: true, status: 200, body: "", error: "" }
        { method: "HEAD", ok: true, status: 200, body: "", error: "" }
    ], [])
    transport = Transport(client)
    answer = transport.Get("https://addon.example/manifest.json")
    Harness_Ok(not answer.ok, "empty JSON GET fails")
    Harness_Equal(answer.error, "empty JSON response", "empty GET has a readable failure")
    answer = transport.Head("https://cdn.example/file.mkv")
    Harness_Ok(answer.ok, "successful HEAD needs no JSON body")
end sub

sub Test_NativeAddons_ConfiguredUrls()
    Harness_Suite("Native addon configured URL parsing")
    store = AddonsStore(ScriptedTransport([]))
    configured = "https://addon.example:8443/config:opaque/manifest.json?option=a%3Ab"
    Harness_Equal(store.SanitizeUrl(configured), configured, "port and configured colon path accepted")
    Harness_Equal(SetupValidateManifestUrl(configured), configured, "LAN form uses the same validator")
    Harness_Equal(store.BaseFromManifestUrl(configured), "https://addon.example:8443/config:opaque?option=a%3Ab", "configured path/query preserved")
    Harness_Equal(store.BaseFromManifestUrl("https://addon.example/manifest.json/config/manifest.json"), "https://addon.example/manifest.json/config", "only the final manifest filename removed")
    rejected = [
        "https://addon.example/manifest.json/extra"
        "https://addon.example/manifest.jsonx"
        "https://addon.example:0/manifest.json"
        "https://addon.example:65536/manifest.json"
        "https://addon.example:no/manifest.json"
        "https://user:password@addon.example/manifest.json"
        "https:///manifest.json"
        "https://addon.example/manifest.json#fragment"
        "https://addon.example/manifest.json" + Chr(10) + "suffix"
    ]
    for each url in rejected
        Harness_Equal(store.SanitizeUrl(url), "", "malformed manifest rejected")
    end for
    descriptor = store.InstallFromDescriptor("https://addon.example/stremio/v1", { id: "test.legacy", name: "Legacy" })
    Harness_Ok(not descriptor.ok, "legacy transport cannot masquerade as modern HTTP")
end sub

sub Test_NativeAddons_CatalogPagination()
    Harness_Suite("Native addon standard catalogs paginate and escape opaque catalog ids")
    metas = []
    for i = 0 to 99
        metas.Push({ id: "item:" + i.ToStr(), type: "movie", name: "Item" })
    end for
    address = "https://addon.example/config:opaque?option=1"
    transport = ScriptedTransport([
        { method: "GET", url: address.Left(address.InStr("?")) + "/catalog/movie/my%2Fcatalog/skip=0.json?option=1", ok: true, status: 200, json: { metas: metas }, error: "" }
        { method: "GET", url: "https://addon.example/catalog/movie/top.json", ok: true, status: 200, json: { metas: [] }, error: "" }
        { method: "GET", url: "https://addon.example/catalog/movie/empty/skip=0.json", ok: true, status: 200, json: invalid, error: "" }
    ])
    store = CatalogStore(transport)
    answer = store.Catalog(address, "movie", "my/catalog")
    Harness_Ok(answer.ok and answer.hasMore, "100-item standard page has another page without custom hasMore")
    answer = store.Catalog("https://addon.example", "movie", "top", "")
    Harness_Ok(answer.ok and not answer.hasMore, "no-extra request uses the standard endpoint")
    answer = store.Catalog("https://addon.example", "movie", "empty")
    Harness_Ok(not answer.ok, "empty 2xx body becomes a readable catalog failure")
end sub

sub Test_NativeAddons_OpaqueEpisodes()
    Harness_Suite("Native addon episodes retain provider ids and standard title fields")
    address = "https://addon.example/config?option=1"
    meta = {
        id: "provider:series/one", type: "series", name: "Example series"
        videos: [
            { id: "provider:episode/b", season: 2, episode: 2, title: "Second", description: "Second synopsis" }
            { id: "provider:episode/a", season: 2, episode: 1, title: "First", description: "First synopsis" }
            { id: "provider:special", season: 0, episode: 1, title: "Special" }
        ]
    }
    transport = ScriptedTransport([
        { method: "GET", url: "https://addon.example/config/meta/series/provider%3Aseries%2Fone.json?option=1", ok: true, status: 200, json: { meta: meta }, error: "" }
    ])
    store = EpisodesStore(transport)
    answer = store.GetMeta(address, "series", meta.id)
    Harness_Ok(answer.ok, "opaque metadata id is percent encoded")
    first = store.FirstEpisode(answer.meta)
    Harness_Equal(first.id, "provider:episode/a", "first real episode chosen even without season 1")
    Harness_Equal(first.name, "First", "standard title displayed")
    Harness_Equal(first.overview, "First synopsis", "description fallback displayed")
    Harness_Equal(store.ResolveVideoId(meta.id, 2, 1, meta), "provider:episode/a", "stream lookup keeps provider-supplied video id")
    ids = store.OrderedVideoIds(meta.id, meta)
    Harness_Equal(ids.Count(), 2, "specials excluded from regular watched order")
    Harness_Equal(ids[0], "provider:episode/a", "watched order shares actual playback ids")
    Harness_Equal(ids[1], "provider:episode/b", "episodes sorted by number")
    library = LibraryStore()
    library.MarkEpisodeWatched(meta.id, first.id)
    mark = library.EpisodeMark(meta.id, 2, first, ids, "2026-10-13T00:00:00Z")
    Harness_Ok(mark.watched, "watched badge uses the provider video id")
    Harness_Ok(store.NeedsMetaFetch({ id: "s", type: "series", name: "S", description: "d", releaseInfo: "2026", imdbRating: "8", background: "b", poster: "p" }), "series without episode ids requests full metadata")
    captions = SubtitlesStore(ScriptedTransport([
        { method: "GET", url: "https://addon.example/config/subtitles/series/provider%3Aepisode%2Fa.json?option=1", ok: true, status: 200, json: { subtitles: [] }, error: "" }
    ]))
    captionResult = captions.Subtitles(address, "series", first.id)
    Harness_Ok(captionResult.ok, "opaque episode id also reaches subtitle endpoint")
    Harness_Equal(captions.transport.log[0].url, "https://addon.example/config/subtitles/series/provider%3Aepisode%2Fa.json?option=1", "subtitle id is one path segment with config query intact")
end sub

sub Test_NativeAddons_SetupOrigins()
    Harness_Suite("Native addon LAN setup boundary")
    address = "http://192.168.1.5:8744"
    host = "POST / HTTP/1.1" + CrLf() + "Host: 192.168.1.5:8744" + CrLf()
    local = host + "Origin: " + address + CrLf() + CrLf()
    Harness_Ok(SetupSameOrigin(local, address), "form from the displayed local page accepted")
    Harness_Ok(SetupSameOrigin(host + CrLf(), address), "direct local setup client accepted")
    Harness_Ok(not SetupSameOrigin(host + "Origin: https://foreign.example" + CrLf() + CrLf(), address), "cross-origin browser POST rejected")
    Harness_Ok(not SetupSameOrigin("GET / HTTP/1.1" + CrLf() + "Host: foreign.example:8744" + CrLf() + CrLf(), address), "foreign rebinding host rejected")
    Harness_Ok(not SetupSameOrigin(host + "Sec-Fetch-Site: cross-site" + CrLf() + CrLf(), address), "cross-site browser request rejected")
    Harness_Ok(SetupIsLanIp("172.16.2.1"), "private 172 range accepted")
    Harness_Ok(not SetupIsLanIp("172.32.2.1"), "public 172 range rejected")
    Harness_Ok(not SetupIsLanIp("8.8.8.8"), "public interface not used for setup binding")
    Harness_Ok(not SetupIsLanIp("192.168.999.1"), "malformed IPv4 rejected")
    Harness_Equal(SetupStatusText("403"), "403 Forbidden", "rejected setup has correct HTTP status")
end sub

sub Test_NativeAddons_Diagnostics()
    Harness_Suite("Native addon URL diagnostics hide configured paths and queries")
    Harness_Equal(TransportLogOrigin("https://addon.example/configuration-secret/stream/movie/item.json?key=secret"), "https://addon.example", "only origin retained")
    Harness_Equal(TransportLogOrigin("https://user:password@addon.example:8443/private"), "https://addon.example:8443", "userinfo redacted")
    Harness_Equal(TransportLogOrigin("invalid-secret"), "[endpoint]", "invalid endpoint text never logged")
    Harness_Equal(RedactUrl("https://addon.example/private-key/subtitle.srt?token=fixture#secret"), "https://addon.example/[redacted]", "subtitle diagnostics hide path, query and fragment")
    Harness_Equal(RedactUrl("https://user:fixture@addon.example:8443/private"), "https://addon.example:8443/[redacted]", "subtitle diagnostics hide userinfo")
    Harness_Equal(RedactUrl("credential-without-url"), "[endpoint]", "malformed subtitle endpoints are never printed")
end sub
