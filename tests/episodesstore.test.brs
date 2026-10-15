' EpisodesStore unit tests.
'
' GetMeta talks to the add-on through the scripted transport; Seasons /
' EpisodesForSeason / ResolveVideoId / NeedsMetaFetch / MergeMeta are pure
' helpers over an already-fetched meta so they run without any transport round trip.

function SeriesMetaFixture() as object
    return {
        id: "tt1234567"
        type: "series"
        name: "Test Series"
        videos: [
            { id: "tt1234567:1:1", name: "Pilot", season: 1, episode: 1 }
            { id: "tt1234567:1:2", name: "Second", season: 1, episode: 2 }
            { id: "tt1234567:2:1", name: "S2E1", season: 2, episode: 1 }
        ]
    }
end function

sub Test_Episodes_GetMetaMovie()
    Harness_Suite("EpisodesStore.GetMeta fetches a movie meta")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/meta/movie/tt0133093.json"
            ok: true
            status: 200
            json: { meta: { id: "tt0133093", type: "movie", name: "The Matrix" } }
            error: ""
        }
    ]
    store = EpisodesStore(ScriptedTransport(script))
    result = store.GetMeta(address, "movie", "tt0133093")

    Harness_Ok(result.ok, "meta ok")
    Harness_Equal(result.meta.name, "The Matrix", "meta parsed")
end sub

sub Test_Episodes_GetMetaSeries()
    Harness_Suite("EpisodesStore.GetMeta fetches a series meta")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/meta/series/tt1234567.json"
            ok: true
            status: 200
            json: { meta: SeriesMetaFixture() }
            error: ""
        }
    ]
    store = EpisodesStore(ScriptedTransport(script))
    result = store.GetMeta(address, "series", "tt1234567")

    Harness_Ok(result.ok, "meta ok")
    Harness_Equal(result.meta.videos.Count(), 3, "videos parsed")
end sub

sub Test_Episodes_RejectsSeriesWithoutVideos()
    Harness_Suite("EpisodesStore.GetMeta rejects a series with no videos")
    script = [
        { method: "GET", ok: true, status: 200, json: { meta: { id: "tt0000000", type: "series", name: "Empty" } }, error: "" }
    ]
    store = EpisodesStore(ScriptedTransport(script))
    result = store.GetMeta("https://addon.example.com", "series", "tt0000000")

    Harness_Ok(not result.ok, "meta rejected")
    Harness_Equal(result.error, "series meta missing videos", "error names the missing videos")
end sub

sub Test_Episodes_Seasons()
    Harness_Suite("EpisodesStore.Seasons lists distinct seasons sorted")
    store = EpisodesStore(ScriptedTransport([]))
    seasons = store.Seasons(SeriesMetaFixture())

    Harness_Equal(seasons.Count(), 2, "two seasons")
    Harness_Equal(seasons[0], 1, "first season is 1")
    Harness_Equal(seasons[1], 2, "second season is 2")
end sub

sub Test_Episodes_EpisodesForSeason()
    Harness_Suite("EpisodesStore.EpisodesForSeason filters by season")
    store = EpisodesStore(ScriptedTransport([]))
    first = store.EpisodesForSeason(SeriesMetaFixture(), 1)
    second = store.EpisodesForSeason(SeriesMetaFixture(), 2)

    Harness_Equal(first.Count(), 2, "season 1 has two episodes")
    Harness_Equal(first[1].episode, 2, "episode numbers intact")
    Harness_Equal(second.Count(), 1, "season 2 has one episode")
    Harness_Equal(second[0].name, "S2E1", "episode names intact")
end sub

sub Test_Episodes_ResolveVideoId()
    Harness_Suite("EpisodesStore.ResolveVideoId builds the stream-id convention")
    store = EpisodesStore(ScriptedTransport([]))

    Harness_Equal(store.ResolveVideoId("tt1234567", 1, 1), "tt1234567:1:1", "movie/episode id shape")
    Harness_Equal(store.ResolveVideoId("tt1234567", 12, 4), "tt1234567:12:4", "double-digit season/episode")
end sub

sub Test_Episodes_OrderedSeasons()
    Harness_Suite("EpisodesStore.OrderedSeasons keeps ascending seasons with specials last")
    store = EpisodesStore(ScriptedTransport([]))
    order = store.OrderedSeasons([0, 1, 2])
    Harness_Equal(order.Count(), 3, "all seasons survive")
    Harness_Equal(order[0], 1, "real seasons first")
    Harness_Equal(order[1], 2, "real seasons ascending")
    Harness_Equal(order[2], 0, "specials last")
    Harness_Equal(store.OrderedSeasons([]).Count(), 0, "empty input stays empty")
    Harness_Equal(store.OrderedSeasons([0]).Count(), 1, "a specials-only series still lists the special")
end sub

sub Test_Episodes_OrderedVideoIds()
    Harness_Suite("EpisodesStore.OrderedVideoIds returns the bitfield-indexing episode order")
    meta = {
        id: "tt1234567"
        type: "series"
        videos: [
            { id: "tt1234567:2:1", name: "S2E1", season: 2, episode: 1 }
            { id: "tt1234567:0:1", name: "Special", season: 0, episode: 1 }
            { id: "tt1234567:1:1", name: "Pilot", season: 1, episode: 1 }
            { id: "tt1234567:1:2", name: "Second", season: 1, episode: 2 }
        ]
    }
    store = EpisodesStore(ScriptedTransport([]))
    ids = store.OrderedVideoIds("tt1234567", meta)
    Harness_Equal(ids.Count(), 3, "specials are skipped")
    Harness_Equal(ids[0], "tt1234567:1:1", "season 1 first episode first")
    Harness_Equal(ids[1], "tt1234567:1:2", "episode order kept")
    Harness_Equal(ids[2], "tt1234567:2:1", "season 2 after season 1")
    Harness_Equal(store.OrderedVideoIds("tt1234567", invalid).Count(), 0, "missing meta yields an empty list")
    Harness_Equal(store.OrderedVideoIds("", meta).Count(), 0, "blank seriesId yields an empty list")
end sub

' A complete meta (all hero fields present) never needs a fetch; a slim catalog
' record missing any of them does. A meta without a fetchable id/type cannot be
' topped up, so it is "no fetch" too.
sub Test_Episodes_NeedsMetaFetch()
    Harness_Suite("EpisodesStore.NeedsMetaFetch flags only sparse metas")
    store = EpisodesStore(ScriptedTransport([]))

    Harness_Ok(not store.NeedsMetaFetch(invalid), "invalid meta: no fetch")
    Harness_Ok(not store.NeedsMetaFetch({}), "empty meta: no fetch")
    Harness_Ok(not store.NeedsMetaFetch({ id: "tt1", name: "No type" }), "missing type: no fetch")
    Harness_Ok(not store.NeedsMetaFetch({ type: "movie", name: "No id" }), "missing id: no fetch")

    complete = {
        id: "tt1234567"
        type: "series"
        name: "Series"
        description: "A summary"
        releaseInfo: "2023"
        imdbRating: "8.1"
        background: "https://example.com/bg.jpg"
        poster: "https://example.com/poster.jpg"
        videos: [{ id: "tt1234567:1:1", season: 1, episode: 1 }]
    }
    Harness_Ok(not store.NeedsMetaFetch(complete), "complete meta: no fetch")

    sparse = { id: "tt1234567", type: "movie", name: "Movie" }
    Harness_Ok(store.NeedsMetaFetch(sparse), "slim catalog meta: fetch")

    Harness_Ok(store.NeedsMetaFetch({ id: "tt1", type: "movie", name: "M", description: "ok" }), "missing poster: fetch")
    Harness_Ok(store.NeedsMetaFetch({ id: "tt1", type: "movie", name: "M", poster: "url", description: "ok", releaseInfo: "2023", imdbRating: "8" }), "missing background: fetch")
    Harness_Ok(store.NeedsMetaFetch({ id: "tt1", type: "movie", name: "M", poster: "url", description: "ok", releaseInfo: "", imdbRating: "8", background: "bg" }), "empty releaseInfo: fetch")
end sub

' Merged meta starts from the fetched record and lets any non-empty field from
' the provided record win, so nothing the caller passed is lost. Empty-string
' provided fields give way to fetched values. Neither input is mutated.
sub Test_Episodes_MergeMeta()
    Harness_Suite("EpisodesStore.MergeMeta fills gaps without losing provided values")
    store = EpisodesStore(ScriptedTransport([]))

    fetched = {
        description: "Fetched description"
        releaseInfo: "2023"
        imdbRating: "8.6"
        background: "https://example.com/bg.jpg"
        poster: "https://example.com/poster.jpg"
    }

    slim = { id: "tt1234567", type: "movie", name: "Mock Movie" }
    merged = store.MergeMeta(slim, fetched)
    Harness_Equal(merged.id, "tt1234567", "provided id kept")
    Harness_Equal(merged.type, "movie", "provided type kept")
    Harness_Equal(merged.name, "Mock Movie", "provided name kept")
    Harness_Equal(merged.description, "Fetched description", "missing description filled")
    Harness_Equal(merged.releaseInfo, "2023", "missing releaseInfo filled")
    Harness_Equal(merged.imdbRating, "8.6", "missing imdbRating filled")
    Harness_Equal(merged.background, "https://example.com/bg.jpg", "missing background filled")
    Harness_Equal(merged.poster, "https://example.com/poster.jpg", "missing poster filled")

    fetchedWithRuntime = { description: "Fetched description", releaseInfo: "2023", imdbRating: "8.6", background: "bg", poster: "poster", runtime: 121 }
    keep = store.MergeMeta({ id: "tt1", name: "Kept", description: "provided wins", runtime: "" }, fetchedWithRuntime)
    Harness_Equal(keep.description, "provided wins", "non-empty provided value wins over fetched")
    Harness_Equal(keep.runtime, 121, "empty provided value gives way to fetched")
    Harness_Equal(keep.id, "tt1", "provided id kept in override case")
    Harness_Equal(keep.imdbRating, "8.6", "fetched fields still fill gaps")

    fromFetchedOnly = store.MergeMeta(invalid, fetched)
    Harness_Equal(fromFetchedOnly.description, "Fetched description", "fetched-only merge keeps fetched")

    fromProvidedOnly = store.MergeMeta({ id: "tt9", type: "movie", name: "Alone" }, invalid)
    Harness_Equal(fromProvidedOnly.id, "tt9", "provided-only merge keeps provided")
    Harness_Equal(fromProvidedOnly.name, "Alone", "provided-only merge keeps name")

    ' Real Cinemeta metas carry object fields like `links`; those must never be
    ' compared against a blank string (Type Mismatch crash) and the provided
    ' value wins over the fetched one.
    providedLinks = [{ name: "Watch Now", category: "watch", url: "https://example.com/watch" }]
    fetched = { description: "Fetched", links: [{ name: "Fetched Link", category: "other" }] }
    withLinks = store.MergeMeta({ id: "tt7", name: "Linked", links: providedLinks }, fetched)
    Harness_Equal(withLinks.links.Count(), 1, "provided links kept (no type-mismatch crash)")
    Harness_Equal(withLinks.links[0].name, "Watch Now", "provided object value wins over fetched")
    Harness_Equal(withLinks.description, "Fetched", "fetched string still fills a gap")

    fetchedWithLinks = { description: "Fetched", links: [{ name: "Fetched Link", category: "other" }], videos: [] }
    fromFetchedLinks = store.MergeMeta({ id: "tt8", name: "No Links" }, fetchedWithLinks)
    Harness_Equal(fromFetchedLinks.links.Count(), 1, "fetched object field survives when provided lacks it")
    Harness_Ok(fromFetchedLinks.videos <> invalid and Type(fromFetchedLinks.videos) = "roArray", "fetched array survives")

    longVideos=[]
    for n=511 to 1 step -1
        longVideos.Push({season:1,episode:n,id:"opaque-"+n.ToStr()})
    end for
    longVideos.Push({season:0,episode:1,id:"special"})
    longIds=store.OrderedVideoIds("series",{videos:longVideos})
    Harness_Equal(longIds.Count(),511,"long-show ordering retains every regular episode")
    Harness_Equal(longIds[0],"opaque-1","long-show first opaque id follows numeric order")
    Harness_Equal(longIds[510],"opaque-511","late opaque episode remains accessible")
    duplicateIds=store.OrderedVideoIds("series",{videos:[{season:1,episode:1},{season:1,episode:1,id:"first"},{season:1,episode:1,id:"second"}]})
    Harness_Equal(duplicateIds[0],"first","duplicate coordinates retain the original resolver's first usable id")
    Harness_Equal(duplicateIds[2],"first","duplicate order cannot silently change watched-bitfield identities")

    freshVideos=[{id:"real:episode",season:1,episode:1}]
    emptyPreview=store.MergeMeta({id:"series",videos:[]},{videos:freshVideos})
    Harness_Equal(emptyPreview.videos.Count(),1,"empty catalog preview cannot erase fetched episodes")
    partialPreview=store.MergeMeta({id:"series",videos:[{id:"preview"}]},{videos:freshVideos})
    Harness_Equal(partialPreview.videos[0].id,"real:episode","fresh full episode metadata supersedes a partial preview")
    retained=store.MergeMeta({id:"series",videos:freshVideos},{description:"only hero"})
    Harness_Equal(retained.videos[0].id,"real:episode","a response without episodes cannot erase existing videos")
    Harness_Equal(slim.description, invalid, "provided input not mutated")
    Harness_Equal(fetched.name, invalid, "fetched input not mutated")
end sub
