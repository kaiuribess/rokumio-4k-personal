' AddonsStore unit tests.
'
' Cinemeta and OpenSubtitles v3 are built-in (Stremio official, protected).
' Everything else installs by fetching a full manifest URL through the scripted
' transport; installed records persist through the mock registry.

function ManifestFixture(id as string, name as string) as object
    return {
        id: id
        name: name
        version: "1.0.0"
        types: ["movie", "series"]
        catalogs: [
            { type: "movie", id: "top", name: "Top" }
            { type: "series", id: "top", name: "Top Series" }
        ]
        resources: ["catalog", "meta"]
    }
end function

sub Test_Addons_BuiltInsPresent()
    Harness_Suite("AddonsStore ships the official built-ins")
    addons = AddonsStore(ScriptedTransport([]), invalid)
    list = addons.GetAll()

    Harness_Equal(list.Count(), 2, "two built-in add-ons")
    Harness_Ok(addons.Get("com.linvo.cinemeta") <> invalid, "cinemeta present")
    Harness_Ok(addons.Get("org.stremio.opensubtitlesv3") <> invalid, "opensubtitles v3 present")
    Harness_Equal(addons.Get("com.linvo.cinemeta").builtin, true, "cinemeta marked builtin")
    Harness_Equal(addons.Get("org.stremio.opensubtitlesv3").address, "https://opensubtitles-v3.strem.io", "opensubtitles address seeded")
    Harness_Equal(addons.Get("com.example.addon"), invalid, "no third-party add-ons installed by default")
end sub

sub Test_Addons_BuiltInsRemovable()
    Harness_Suite("AddonsStore.Uninstall hides a shipped built-in")
    addons = AddonsStore(ScriptedTransport([]), invalid)

    Harness_Ok(addons.Uninstall("com.linvo.cinemeta", true), "cinemeta removed")
    Harness_Equal(addons.GetAll().Count(), 1, "cinemeta gone from the list")
    Harness_Ok(addons.Get("com.linvo.cinemeta") = invalid, "cinemeta no longer resolves")
    Harness_Ok(addons.Get("org.stremio.opensubtitlesv3") <> invalid, "opensubtitles still present")
    Harness_Ok(not addons.Uninstall("com.linvo.cinemeta", true), "second removal fails")
    Harness_Ok(not addons.Uninstall("com.linvo.cinemeta"), "installed-row form does not hide a built-in")
    Harness_Equal(addons.Get("com.linvo.cinemeta"), invalid, "still hidden after both forms")
end sub

sub Test_Addons_BuiltInRemovalPersists()
    Harness_Suite("AddonsStore built-in removal persists across reloads")
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport([]), registry)
    Harness_Ok(addons.Uninstall("com.linvo.cinemeta", true), "cinemeta removed")
    Harness_Equal(addons.GetAll().Count(), 1, "one built-in left")

    reopened = AddonsStore(ScriptedTransport([]), registry)
    Harness_Equal(reopened.GetAll().Count(), 1, "removal survived reload")
    Harness_Ok(reopened.Get("com.linvo.cinemeta") = invalid, "cinemeta still hidden after reload")
    Harness_Ok(reopened.Get("org.stremio.opensubtitlesv3") <> invalid, "opensubtitles still present")
end sub

sub Test_Addons_RemovesInstalledCloneOfBuiltin()
    Harness_Suite("AddonsStore removes a same-id clone independently of its built-in")
    manifestUrl = "https://addon.example.com/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.linvo.cinemeta", "Cinemeta ES"), error: "" }
    ]
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport(script), registry)
    Harness_Ok(addons.Install(manifestUrl).ok, "clone installed")
    Harness_Equal(addons.GetAll().Count(), 3, "shipped seed + clone + opensubtitles")

    Harness_Ok(addons.Uninstall("com.linvo.cinemeta"), "clone row removed")
    Harness_Equal(addons.GetAll().Count(), 2, "clone gone, shipped seeds remain")
    Harness_Equal(addons.Get("com.linvo.cinemeta").builtin, true, "shipped cinemeta still resolves")

    Harness_Ok(addons.Uninstall("com.linvo.cinemeta", true), "built-in row removed")
    Harness_Equal(addons.GetAll().Count(), 1, "only opensubtitles remains")
end sub

sub Test_Addons_ReinstallRemovedBuiltin()
    Harness_Suite("AddonsStore reinstalls a removed built-in by URL")
    manifestUrl = "https://v3-cinemeta.strem.io/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.linvo.cinemeta", "Cinemeta"), error: "" }
    ]
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport(script), registry)
    Harness_Ok(addons.Uninstall("com.linvo.cinemeta", true), "cinemeta removed")

    Harness_Ok(addons.Install(manifestUrl).ok, "official URL reinstalls")
    Harness_Equal(addons.GetAll().Count(), 2, "reinstalled copy + opensubtitles")
    Harness_Ok(addons.Get("com.linvo.cinemeta") <> invalid, "cinemeta present again")
    Harness_Equal(addons.Get("com.linvo.cinemeta").builtin, false, "reinstalled row is a normal add-on")
end sub

sub Test_Addons_EmptyFirstRun()
    Harness_Suite("AddonsStore first run installs no third-party add-ons")
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport([]), registry)

    Harness_Equal(addons.GetAll().Count(), 2, "built-ins only on first run")
    Harness_Ok(not addons.Uninstall("com.example.addon"), "nothing seeded to uninstall")

    reopened = AddonsStore(ScriptedTransport([]), registry)
    Harness_Equal(reopened.GetAll().Count(), 2, "built-ins only after reload")
end sub

sub Test_Addons_Install()
    Harness_Suite("AddonsStore.Install fetches the manifest and stores the add-on")
    manifestUrl = "https://addon.example.com/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    result = addons.Install(manifestUrl)

    Harness_Ok(result.ok, "install ok")
    Harness_Equal(result.id, "com.example.addon", "returns the manifest id")
    record = addons.Get("com.example.addon")
    Harness_Equal(record.name, "Example", "name stored")
    Harness_Equal(record.address, "https://addon.example.com", "stored address is the base (no manifest.json)")
    Harness_Equal(record.builtin, false, "installed add-on not builtin")
    Harness_Equal(addons.GetAll().Count(), 3, "built-ins plus the new one")
end sub

sub Test_Addons_InstallOnEmptyRegistry()
    Harness_Suite("AddonsStore.Install adds to an empty first-run registry")
    manifestUrl = "https://addon.example.com/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport(script), registry)

    Harness_Ok(addons.Install(manifestUrl).ok, "install ok")
    Harness_Equal(addons.Get("com.example.addon").builtin, false, "installed add-on is removable")
    Harness_Equal(addons.GetAll().Count(), 3, "built-ins + example")

    Harness_Ok(addons.Uninstall("com.example.addon"), "installed add-on can be removed")
    Harness_Equal(addons.GetAll().Count(), 2, "back to built-ins after removal")
end sub

sub Test_Addons_RejectsInvalidManifest()
    Harness_Suite("AddonsStore.Install rejects a manifest without id/name")
    script = [
        { method: "GET", ok: true, status: 200, json: { name: "Missing id" }, error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    result = addons.Install("https://addon.example.com/manifest.json")

    Harness_Ok(not result.ok, "install rejected")
    Harness_Equal(result.error, "manifest missing id or name", "error names the missing field")
    Harness_Equal(addons.GetAll().Count(), 2, "nothing installed")
end sub

sub Test_Addons_InstallWithQueryArgs()
    Harness_Suite("AddonsStore.Install handles manifest URLs with query args")
    manifestUrl = "https://addon.example.com/manifest.json?token=abc&v=2"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    result = addons.Install(manifestUrl)

    Harness_Ok(result.ok, "install ok")
    Harness_Equal(addons.transport.log.Count(), 1, "exactly one manifest fetch")
    Harness_Equal(addons.transport.log[0].url, manifestUrl, "fetches the exact URL including query args")
    record = addons.Get("com.example.addon")
    Harness_Equal(record.address, "https://addon.example.com?token=abc&v=2", "stored address keeps all query args")
end sub

sub Test_Addons_InstallSubPath()
    Harness_Suite("AddonsStore.Install handles a manifest in a sub-path")
    manifestUrl = "https://addon.example.com/path/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    result = addons.Install(manifestUrl)

    Harness_Ok(result.ok, "install ok")
    Harness_Equal(addons.transport.log[0].url, manifestUrl, "fetches the exact sub-path URL")
    Harness_Equal(addons.Get("com.example.addon").address, "https://addon.example.com/path", "stored address is the sub-path base")
end sub

sub Test_Addons_NormalizesObjectResources()
    Harness_Suite("AddonsStore.Install normalizes object resources to names")
    manifestUrl = "https://addon.example.com/manifest.json"
    manifest = ManifestFixture("com.example.addon", "Example")
    manifest.resources = [
        { name: "stream", types: ["movie", "series"], idPrefixes: ["tt", "kitsu"] }
        "meta"
    ]
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: manifest, error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    result = addons.Install(manifestUrl)

    Harness_Ok(result.ok, "install ok")
    resources = addons.Get("com.example.addon").resources
    Harness_Equal(resources.Count(), 2, "object + string resources kept")
    Harness_Equal(resources[0].name, "stream", "object resource keeps its name")
    Harness_Equal(resources[0].short, false, "object resource is full (not short)")
    Harness_Equal(resources[0].types[0], "movie", "object resource types preserved")
    Harness_Equal(resources[0].idPrefixes[1], "kitsu", "object resource idPrefixes preserved")
    Harness_Equal(resources[1].name, "meta", "string resource normalized to a descriptor")
    Harness_Equal(resources[1].short, true, "string resource is short")
end sub

sub Test_Addons_LoadNormalizesObjectResources()
    Harness_Suite("AddonsStore.Load normalizes persisted object resources")
    registry = MockRegistry()
    stale = {
        "com.example.addon": {
            id: "com.example.addon"
            name: "Example"
            version: "1.0.0"
            types: ["movie"]
            catalogs: []
            resources: [{ name: "stream" }]
            address: "https://addon.example.com"
            builtin: false
        }
    }
    registry.values["addons"] = FormatJson(stale)
    addons = AddonsStore(ScriptedTransport([]), registry)

    resources = addons.Get("com.example.addon").resources
    Harness_Equal(resources.Count(), 1, "one resource after load")
    Harness_Equal(resources[0].name, "stream", "object resource normalized to a descriptor")
    Harness_Equal(resources[0].short, false, "persisted object resources stay full")
end sub

sub Test_Addons_RejectsInvalidAddress()
    Harness_Suite("AddonsStore.Install rejects malformed addon addresses")
    cases = [
        ""
        "  "
        "addon.example.com"
        "not a url"
        "ftp://addon.example.com"
        "https://"
        "https://addon.example.com:abc"
        "https://:8080"
        "https://addon.example.com"
    ]
    addons = AddonsStore(ScriptedTransport([]), invalid)
    for each input in cases
        result = addons.Install(input)
        Harness_Ok(not result.ok, "rejected: " + input)
    end for
    Harness_Equal(addons.GetAll().Count(), 2, "nothing installed")
    Harness_Equal(addons.transport.log.Count(), 0, "no request dispatched for invalid input")
end sub

sub Test_Addons_RejectsDuplicate()
    Harness_Suite("AddonsStore.Install refuses an already-installed id")
    manifestUrl = "https://addon.example.com/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    Harness_Ok(addons.Install(manifestUrl).ok, "first install ok")

    result = addons.Install(manifestUrl)
    Harness_Ok(not result.ok, "duplicate install refused")
    Harness_Equal(result.error, "addon already installed", "error names the duplicate")
    Harness_Equal(addons.transport.log.Count(), 2, "manifest fetched both times, refused after")
    Harness_Equal(addons.GetAll().Count(), 3, "still just built-ins plus the first install")
end sub

sub Test_Addons_InstallNoAddress()
    Harness_Suite("AddonsStore.Install refuses without an address")
    addons = AddonsStore(ScriptedTransport([]), invalid)
    result = addons.Install("")

    Harness_Ok(not result.ok, "install rejected")
    Harness_Equal(result.error, "no addon address", "error names the missing address")
end sub

sub Test_Addons_Uninstall()
    Harness_Suite("AddonsStore.Uninstall removes an installed add-on")
    manifestUrl = "https://addon.example.com/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    addons.Install(manifestUrl)

    Harness_Ok(addons.Uninstall("com.example.addon"), "uninstall ok")
    Harness_Equal(addons.GetAll().Count(), 2, "back to built-ins")
    Harness_Ok(not addons.Uninstall("com.example.addon"), "second uninstall fails")
end sub

sub Test_Addons_PersistsViaRegistry()
    Harness_Suite("AddonsStore round-trips through the registry")
    manifestUrl = "https://addon.example.com/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport(script), registry)
    addons.Install(manifestUrl)

    reopened = AddonsStore(ScriptedTransport([]), registry)
    Harness_Ok(reopened.Get("com.example.addon") <> invalid, "installed add-on reloaded")
    Harness_Equal(reopened.Get("com.example.addon").address, "https://addon.example.com", "address reloaded")
end sub

sub Test_Addons_RegisterAdoptsRecord()
    Harness_Suite("AddonsStore.Register adopts an off-thread fetched record")
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport([]), registry)
    record = {
        id: "com.example.addon"
        name: "Example"
        version: "1.0.0"
        types: ["movie", "series"]
        catalogs: [
            { type: "movie", id: "top", name: "Top" }
            { type: "series", id: "top", name: "Top Series" }
        ]
        resources: ["catalog", "meta"]
        address: "https://addon.example.com"
        builtin: false
    }

    Harness_Ok(addons.Register(record), "register ok")
    Harness_Equal(addons.Get("com.example.addon").name, "Example", "record stored")
    Harness_Equal(addons.GetAll().Count(), 3, "built-ins plus the new one")

    Harness_Ok(not addons.Register(record), "duplicate register refused")
    reopened = AddonsStore(ScriptedTransport([]), registry)
    Harness_Ok(reopened.Get("com.example.addon") <> invalid, "registered record persisted")
end sub

sub Test_Addons_CatalogsFlatten()
    Harness_Suite("AddonsStore.Catalogs flattens advertised catalogs")
    manifestUrl = "https://addon.example.com/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    addons = AddonsStore(ScriptedTransport(script), invalid)
    addons.Install(manifestUrl)
    catalogs = addons.Catalogs()

    Harness_Equal(catalogs.Count(), 2, "two catalogs advertised")
    Harness_Equal(catalogs[0].addonId, "com.example.addon", "catalog carries the add-on id")
    Harness_Equal(catalogs[0].type, "movie", "catalog type propagated")
    Harness_Equal(catalogs[0].catalogId, "top", "catalog id propagated")
end sub

sub Test_Addons_HasResource()
    Harness_Suite("AddonsStore.HasResource spots a resource name in any entry shape")
    addons = AddonsStore(ScriptedTransport([]), invalid)

    Harness_Ok(addons.HasResource(["stream", "meta"], "stream"), "string resources matched")
    Harness_Ok(addons.HasResource([{ name: "subtitles" }], "subtitles"), "object resources matched")
    Harness_Ok(not addons.HasResource(["catalog"], "stream"), "absent name not matched")
    Harness_Ok(not addons.HasResource(invalid, "stream"), "invalid resources not matched")
    Harness_Ok(not addons.HasResource([], "stream"), "empty resources not matched")
end sub

sub Test_Addons_HasType()
    Harness_Suite("AddonsStore.HasType matches the media type against declared types")
    addons = AddonsStore(ScriptedTransport([]), invalid)

    Harness_Ok(addons.HasType(["movie", "series"], "movie"), "exact movie match")
    Harness_Ok(addons.HasType(["movie", "series"], "series"), "exact series match")
    Harness_Ok(not addons.HasType(["movie"], "series"), "movie-only add-on refused for series")
    Harness_Ok(not addons.HasType(["channel"], "movie"), "channel add-on refused for movie")
    Harness_Ok(not addons.HasType(["movie", "series"], "channel"), "movie/series add-on refused for channel")

    Harness_Ok(addons.HasType(["channel"], "tv"), "channel declared, tv wanted")
    Harness_Ok(addons.HasType(["tv"], "channel"), "tv declared, channel wanted")
    Harness_Ok(addons.HasType(["movie", "channel"], "tv"), "mixed add-on serves the channel family")

    Harness_Ok(not addons.HasType(invalid, "movie"), "invalid types refused (stremio-core parity)")
    Harness_Ok(not addons.HasType([], "movie"), "empty types refused (stremio-core parity)")
    Harness_Ok(addons.HasType(["channel"], ""), "blank wanted type is permissive")
end sub

sub Test_Addons_MatchesIdPrefixes()
    Harness_Suite("AddonsStore.MatchesIdPrefixes mirrors stremio-core prefix matching")
    addons = AddonsStore(ScriptedTransport([]), invalid)

    Harness_Ok(addons.MatchesIdPrefixes(invalid, "tt1254207"), "absent prefixes accept any id")
    Harness_Ok(addons.MatchesIdPrefixes(["tt", "kitsu"], "tt1254207"), "tt id matched")
    Harness_Ok(addons.MatchesIdPrefixes(["tt", "kitsu"], "kitsu:42"), "kitsu id matched")
    Harness_Ok(not addons.MatchesIdPrefixes(["tt", "kitsu"], "yt_id:abc"), "unlisted prefix refused")
    Harness_Ok(not addons.MatchesIdPrefixes(["tt"], ""), "empty id matches no prefix")
    Harness_Ok(not addons.MatchesIdPrefixes([], "tt1"), "present-empty prefixes match nothing")
    Harness_Ok(not addons.MatchesIdPrefixes([""], "tt1"), "blank prefix cannot match everything")
end sub

sub Test_Addons_SupportsResource()
    Harness_Suite("AddonsStore.SupportsResource mirrors stremio-core resource matching")
    addons = AddonsStore(ScriptedTransport([]), invalid)

    ' Torrentio-shaped: a full "stream" resource carrying its own types + idPrefixes.
    torrentio = [
        { name: "stream", short: false, types: ["movie", "series", "anime"], idPrefixes: ["tt", "kitsu"] }
    ]
    globalTypes = ["movie", "series", "anime", "other"]
    Harness_Ok(addons.SupportsResource(torrentio, globalTypes, invalid, "stream", "movie", "tt1254207"), "tt movie matched")
    Harness_Ok(addons.SupportsResource(torrentio, globalTypes, invalid, "stream", "series", "tt1234567:1:1"), "tt episode matched")
    Harness_Ok(addons.SupportsResource(torrentio, globalTypes, invalid, "stream", "movie", "kitsu:42"), "kitsu movie matched")
    Harness_Ok(not addons.SupportsResource(torrentio, globalTypes, invalid, "stream", "channel", "cnn1"), "channel never asked (types)")
    Harness_Ok(not addons.SupportsResource(torrentio, globalTypes, invalid, "stream", "movie", "yt_id:abc"), "foreign id prefix never asked")
    Harness_Ok(not addons.SupportsResource(torrentio, globalTypes, invalid, "meta", "movie", "tt1"), "other resource name never matched")

    ' Full resource with no idPrefixes: any id, but its own types still apply.
    anyId = [{ name: "stream", short: false, types: ["movie"], idPrefixes: invalid }]
    Harness_Ok(addons.SupportsResource(anyId, ["movie"], invalid, "stream", "movie", "whatever"), "absent resource idPrefixes accepts any id")
    Harness_Ok(not addons.SupportsResource(anyId, ["movie"], invalid, "stream", "series", "tt1"), "resource types override the manifest types")

    ' Full resource with no types: never queried (stremio-core is_some_and).
    noTypes = [{ name: "stream", short: false, types: invalid, idPrefixes: ["tt"] }]
    Harness_Ok(not addons.SupportsResource(noTypes, ["movie"], invalid, "stream", "movie", "tt1"), "typeless full resource never queried")

    ' Present-but-empty idPrefixes matches nothing (core any() over []).
    emptyIds = [{ name: "stream", short: false, types: ["movie"], idPrefixes: [] }]
    Harness_Ok(not addons.SupportsResource(emptyIds, ["movie"], invalid, "stream", "movie", "tt1"), "present-empty idPrefixes match nothing")

    ' A short resource inherits the manifest's types AND idPrefixes.
    shortStream = [{ name: "stream", short: true, types: invalid, idPrefixes: invalid }]
    Harness_Ok(addons.SupportsResource(shortStream, ["movie"], ["tt"], "stream", "movie", "tt9"), "short resource inherits global idPrefixes")
    Harness_Ok(not addons.SupportsResource(shortStream, ["movie"], ["tt"], "stream", "movie", "kitsu:9"), "short resource respects global idPrefixes")
    Harness_Ok(not addons.SupportsResource(shortStream, ["movie"], ["tt"], "stream", "series", "tt9"), "short resource respects global types")

    ' A raw manifest resource string behaves as a short resource.
    Harness_Ok(addons.SupportsResource(["stream"], ["movie"], ["tt"], "stream", "movie", "tt9"), "raw string resource treated as short")

    ' No types declared anywhere: never queried.
    Harness_Ok(not addons.SupportsResource(shortStream, invalid, invalid, "stream", "movie", "tt9"), "absent manifest types never queried")
    Harness_Ok(not addons.SupportsResource(invalid, globalTypes, invalid, "stream", "movie", "tt9"), "missing resources never matched")
end sub

sub Test_Addons_CatalogCapabilities()
    Harness_Suite("AddonsStore.CatalogCapabilities derives search/feed/genre from extras")
    addons = AddonsStore(ScriptedTransport([]), invalid)

    top = {
        type: "movie"
        id: "top"
        name: "Popular"
        extra: [
            { name: "search", isRequired: false }
            { name: "genre", isRequired: false, options: ["Action", "Comedy"] }
        ]
    }
    topCaps = addons.CatalogCapabilities(top)
    Harness_Ok(topCaps.search, "optional search declares search")
    Harness_Ok(topCaps.feed, "optional extras keep it feedable")
    Harness_Ok(topCaps.genre, "genre extra surfaces")
    Harness_Ok(not topCaps.genreRequired, "genre is optional")
    Harness_Equal(topCaps.genreOptions.Count(), 2, "genre options carried")

    year = {
        type: "movie"
        id: "year"
        extra: [
            { name: "genre", isRequired: true, options: ["2026", "2025"] }
            { name: "skip", isRequired: false }
        ]
    }
    yearCaps = addons.CatalogCapabilities(year)
    Harness_Ok(not yearCaps.search, "required genre blocks search")
    Harness_Ok(yearCaps.feed, "required genre is still feedable")
    Harness_Ok(yearCaps.genreRequired, "genre is required")

    searchOnly = { type: "movie", id: "search", extra: [{ name: "search", isRequired: true }] }
    searchCaps = addons.CatalogCapabilities(searchOnly)
    Harness_Ok(searchCaps.search, "search-only catalog is searchable")
    Harness_Ok(not searchCaps.feed, "search-only catalog is not feedable")

    lastVideos = { type: "movie", id: "last-videos", extra: [{ name: "lastVideosIds", isRequired: true, options: ["tt1"] }] }
    lastCaps = addons.CatalogCapabilities(lastVideos)
    Harness_Ok(not lastCaps.feed, "required custom extra blocks feeding")
    Harness_Ok(not lastCaps.search, "required custom extra blocks search")

    legacy = {
        type: "movie"
        id: "legacy"
        extraSupported: ["search", "genre"]
        extraRequired: ["genre"]
        genres: ["Drama", "Horror"]
    }
    legacyCaps = addons.CatalogCapabilities(legacy)
    Harness_Ok(legacyCaps.genre, "legacy extraSupported surfaces genre")
    Harness_Ok(legacyCaps.genreRequired, "legacy extraRequired marks genre required")
    Harness_Equal(legacyCaps.genreOptions.Count(), 2, "top-level genres used as options")
    Harness_Ok(not legacyCaps.search, "required legacy genre blocks search")
    Harness_Ok(legacyCaps.feed, "legacy required genre still feedable")

    bare = addons.CatalogCapabilities({ type: "movie", id: "bare" })
    Harness_Ok(bare.feed, "catalog with no extras is feedable")
    Harness_Ok(not bare.search, "catalog with no extras is not searchable")
    Harness_Ok(not bare.genre, "catalog with no extras has no genre")

    none = addons.CatalogCapabilities(invalid)
    Harness_Ok(not none.feed, "invalid catalog is not feedable")
    Harness_Ok(not none.search, "invalid catalog is not searchable")
end sub

sub Test_Addons_CatalogTitle()
    Harness_Suite("AddonsStore.CatalogTitle falls back name -> id -> addon -> Unknown")
    addons = AddonsStore(ScriptedTransport([]), invalid)

    Harness_Equal(addons.CatalogTitle({ name: "Popular", id: "top" }, "Addon"), "Popular", "catalog name wins")
    Harness_Equal(addons.CatalogTitle({ id: "top" }, "Addon"), "top", "id when name missing")
    Harness_Equal(addons.CatalogTitle({ id: "top" }, ""), "top", "id when addon blank")
    Harness_Equal(addons.CatalogTitle(invalid, "Addon"), "Addon", "addon name when catalog invalid")
    Harness_Equal(addons.CatalogTitle(invalid, invalid), "Unknown", "Unknown when nothing is available")
end sub

sub Test_Addons_StremioSessionHidesBuiltIns()
    Harness_Suite("AddonsStore stremio session hides the virtual built-in seeds")
    addons = AddonsStore(ScriptedTransport([]), invalid, "stremio")

    Harness_Equal(addons.GetAll().Count(), 0, "no built-in seeds in a stremio session")
    Harness_Ok(addons.Get("com.linvo.cinemeta") = invalid, "built-in does not resolve")
    Harness_Ok(addons.Get("org.stremio.opensubtitlesv3") = invalid, "opensubtitles seed does not resolve")
end sub

sub Test_Addons_SwitchSessionSeparatesData()
    Harness_Suite("AddonsStore session switch isolates guest and stremio add-ons")
    manifestUrl = "https://addon.example.com/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport(script), registry)

    Harness_Ok(addons.Install(manifestUrl).ok, "guest install ok")
    Harness_Equal(addons.GetAll().Count(), 3, "guest session has built-ins + example")

    addons.SwitchSession("stremio")
    Harness_Equal(addons.GetAll().Count(), 0, "stremio session starts empty")
    Harness_Ok(addons.Get("com.example.addon") = invalid, "guest add-on not visible in stremio")

    addons.SwitchSession("guest")
    Harness_Equal(addons.GetAll().Count(), 3, "guest add-ons restored on switch back")
    Harness_Ok(addons.Get("com.example.addon") <> invalid, "guest add-on resolves again")

    reopened = AddonsStore(ScriptedTransport([]), registry, "stremio")
    Harness_Equal(reopened.GetAll().Count(), 0, "stremio registry keys stayed empty")
end sub

sub Test_Addons_StremioInstalledPersists()
    Harness_Suite("AddonsStore stremio session installs into its own registry key")
    manifestUrl = "https://addon.example.com/manifest.json"
    script = [
        { method: "GET", url: manifestUrl, ok: true, status: 200, json: ManifestFixture("com.example.addon", "Example"), error: "" }
    ]
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport(script), registry, "stremio")

    Harness_Ok(addons.Install(manifestUrl).ok, "stremio install ok")
    Harness_Equal(addons.GetAll().Count(), 1, "only the installed add-on shows")

    reopened = AddonsStore(ScriptedTransport([]), registry, "stremio")
    Harness_Ok(reopened.Get("com.example.addon") <> invalid, "stremio add-on reloaded")

    guest = AddonsStore(ScriptedTransport([]), registry)
    Harness_Equal(guest.GetAll().Count(), 2, "guest session unaffected by the stremio install")
end sub

' ---------------------------------------------------------------------------
' Display order.
'
' These assert the ORDER CONTRACT, not a platform behaviour. The bug they exist
' for could not be asserted directly: m.installed is an roAssociativeArray,
' whose key iteration is declaration order under the brs interpreter and the
' runtime's own hash order on a Roku device. GetAll used to walk that map
' directly, so Home's catalog rows came out in a different order on the device
' than in the simulator, and any "first add-on advertising X" picker chose a
' different provider on device than in the sim. The interpreter has only the one
' ordering, so a test written against it would have passed against the broken
' code forever.
'
' What CAN be pinned, and is pinned below, is that the order comes from the
' explicit order list and never from the map's iteration. That is a property of
' the source, it holds identically on both platforms, and the old code fails it.
' ---------------------------------------------------------------------------

function RecordFixture(id as string, name as string) as object
    return {
        id: id
        name: name
        version: "1.0.0"
        types: ["movie", "series"]
        catalogs: []
        resources: ["catalog", "meta"]
        address: "https://" + id + ".example.com"
        builtin: false
    }
end function

function IdsOf(list as object) as object
    ids = []
    for each record in list
        ids.Push(record.id)
    end for
    return ids
end function

sub AssertOrder(list as object, expected as object, what as string) as void
    got = IdsOf(list)
    if got.Count() <> expected.Count() then
        Harness_Ok(false, what + "  (got " + got.Count().ToStr() + " ids, expected " + expected.Count().ToStr() + ")")
        return
    end if
    for i = 0 to got.Count() - 1
        if got[i] <> expected[i] then
            Harness_Ok(false, what + "  (position " + i.ToStr() + " was " + got[i] + ", expected " + expected[i] + ")")
            return
        end if
    end for
    Harness_Ok(true, what)
end sub

function JsonIdArray(ids as object) as string
    parts = []
    for each id in ids
        parts.Push(Chr(34) + id + Chr(34))
    end for
    return "[" + parts.Join(", ") + "]"
end function

sub Test_Addons_BuiltinOrderIsFixed()
    Harness_Suite("the shipped built-ins have a fixed, declared order")
    addons = AddonsStore(ScriptedTransport([]), invalid)

    Harness_Equal(JsonIdArray(addons.BuiltinIds()), "[" + Chr(34) + "com.linvo.cinemeta" + Chr(34) + ", " + Chr(34) + "org.stremio.opensubtitlesv3" + Chr(34) + "]", "BuiltinIds is the declared pair, metadata first")
    AssertOrder(addons.GetAll(), ["com.linvo.cinemeta", "org.stremio.opensubtitlesv3"], "GetAll lists the built-ins in BuiltinIds order")
end sub

sub Test_Addons_GetAllUsesRegistrationOrder()
    Harness_Suite("GetAll lists installed add-ons in registration order")
    addons = AddonsStore(ScriptedTransport([]), invalid, "stremio")

    ' Registered Z, A, M on purpose. Name order would be A, M, Z and map
    ' iteration order is whatever the platform does — only registration order
    ' gives Z, A, M.
    Harness_Ok(addons.Register(RecordFixture("com.z.addon", "Zeta")), "Zeta registered")
    Harness_Ok(addons.Register(RecordFixture("com.a.addon", "Alpha")), "Alpha registered")
    Harness_Ok(addons.Register(RecordFixture("com.m.addon", "Mid")), "Mid registered")

    AssertOrder(addons.GetAll(), ["com.z.addon", "com.a.addon", "com.m.addon"], "registration order, not name order")
end sub

sub Test_Addons_GetAllFollowsPersistedOrderNotRecordMap()
    Harness_Suite("GetAll follows the persisted order list, not the record map")
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport([]), registry, "stremio")
    addons.Register(RecordFixture("com.a.addon", "Alpha"))
    addons.Register(RecordFixture("com.b.addon", "Beta"))
    addons.Register(RecordFixture("com.c.addon", "Charlie"))
    AssertOrder(addons.GetAll(), ["com.a.addon", "com.b.addon", "com.c.addon"], "registration order first")

    ' Rewrite ONLY the order key, leaving the record map exactly as written. A
    ' GetAll that walked the map would ignore this and still report A, B, C.
    registry.Write("stremio_addons_order", JsonIdArray(["com.c.addon", "com.a.addon", "com.b.addon"]))
    reopened = AddonsStore(ScriptedTransport([]), registry, "stremio")
    AssertOrder(reopened.GetAll(), ["com.c.addon", "com.a.addon", "com.b.addon"], "the order key decides the list, the record map cannot")
    Harness_Equal(reopened.GetAll().Count(), 3, "no record lost to the reorder")
end sub

sub Test_Addons_OrderSurvivesReload()
    Harness_Suite("the display order survives a relaunch")
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport([]), registry, "stremio")
    addons.Register(RecordFixture("com.z.addon", "Zeta"))
    addons.Register(RecordFixture("com.a.addon", "Alpha"))

    reopened = AddonsStore(ScriptedTransport([]), registry, "stremio")
    AssertOrder(reopened.GetAll(), ["com.z.addon", "com.a.addon"], "order still registration order after reload")
end sub

sub Test_Addons_MissingOrderListFallsBackToNameSort()
    Harness_Suite("records with no entry in the order list still land somewhere stable")
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport([]), registry, "stremio")
    addons.Register(RecordFixture("com.z.addon", "Zeta"))
    addons.Register(RecordFixture("com.a.addon", "Alpha"))
    addons.Register(RecordFixture("com.m.addon", "Mid"))

    ' A registry written before the order key existed has no order to read.
    registry.Write("stremio_addons_order", "")
    reopened = AddonsStore(ScriptedTransport([]), registry, "stremio")
    AssertOrder(reopened.GetAll(), ["com.a.addon", "com.m.addon", "com.z.addon"], "no order list falls back to name order, not map order")

    registry.Write("stremio_addons_order", "{ not json")
    torn = AddonsStore(ScriptedTransport([]), registry, "stremio")
    AssertOrder(torn.GetAll(), ["com.a.addon", "com.m.addon", "com.z.addon"], "a corrupt order list is a cold start, not a crash")
end sub

sub Test_Addons_ReinstallMovesToEnd()
    Harness_Suite("re-installing a removed add-on puts it at the end")
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport([]), registry, "stremio")
    addons.Register(RecordFixture("com.a.addon", "Alpha"))
    addons.Register(RecordFixture("com.b.addon", "Beta"))
    addons.Register(RecordFixture("com.c.addon", "Charlie"))

    Harness_Ok(addons.Uninstall("com.b.addon"), "Beta removed")
    AssertOrder(addons.GetAll(), ["com.a.addon", "com.c.addon"], "Beta gone from the list")
    Harness_Ok(addons.Register(RecordFixture("com.b.addon", "Beta")), "Beta re-registered")
    AssertOrder(addons.GetAll(), ["com.a.addon", "com.c.addon", "com.b.addon"], "Beta re-registered lands at the end, not back in its old slot")
end sub

sub Test_Addons_OrderLivesOutsideTheRecordMap()
    Harness_Suite("the display order is persisted outside the record map")
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport([]), registry, "stremio")
    addons.Register(RecordFixture("com.a.addon", "Alpha"))

    ' The whole reason for a second key: the record map is persisted as a JSON
    ' OBJECT and ParseJson does not preserve object key order, so an order kept
    ' in there would be lost on the next launch. An ARRAY round-trips in
    ' sequence; this asserts it is written as one.
    Harness_Equal(registry.values["stremio_addons_order"], "[" + Chr(34) + "com.a.addon" + Chr(34) + "]", "order persisted as a JSON array of ids")
    Harness_Ok(registry.values["stremio_addons"].Left(1) = "{", "records still persisted as the JSON object they are")

    addons.SwitchSession("guest")
    Harness_Equal(addons.GetAll().Count(), 2, "switching to guest drops the stremio order with the rest of its data")
    Harness_Equal(registry.values["addons_order"], invalid, "the stremio order never leaked into the guest key")

    addons.Register(RecordFixture("com.guest.addon", "Guest"))
    Harness_Equal(registry.values["addons_order"], "[" + Chr(34) + "com.guest.addon" + Chr(34) + "]", "the guest session keeps its own order, holding only guest add-ons")
    AssertOrder(addons.GetAll(), ["com.linvo.cinemeta", "org.stremio.opensubtitlesv3", "com.guest.addon"], "guest list is built-ins in fixed order, then the guest install")
end sub

sub Test_Addons_IsBuiltinSurvivesSyncProvenance()
    Harness_Suite("IsBuiltin keys off the id, not the record's builtin flag")
    addons = AddonsStore(ScriptedTransport([]), invalid, "stremio")
    outcome = addons.InstallFromDescriptor("https://opensubtitles-v3.strem.io/manifest.json", {
        id: "org.stremio.opensubtitlesv3"
        name: "OpenSubtitles v3"
        version: "1.0.0"
        types: ["movie", "series"]
        catalogs: []
        resources: ["subtitles"]
    })

    Harness_Ok(outcome.ok, "the account sync adopts the built-in by id")
    ' The whole point: the synced record carries builtin: false, exactly like
    ' every other add-on it synced. The flag is useless for ranking; the id is
    ' not, which is why anything picking a provider asks for this and not for
    ' record.builtin.
    Harness_Equal(addons.Get("org.stremio.opensubtitlesv3").builtin, false, "a synced built-in is stamped builtin: false like everything else")
    Harness_Ok(addons.IsBuiltin("org.stremio.opensubtitlesv3"), "IsBuiltin still recognises it")
    Harness_Ok(not addons.IsBuiltin("com.example.addon"), "IsBuiltin does not claim a third-party add-on")
end sub