' librarysync tests — LibraryStore.SyncFromStremio: the mapping the
' LibrarySyncTask result feeds. The Task itself runs on a worker thread with
' its own Transport (like AddonSyncTask), so its HTTP call cannot be injected
' here; these tests pin the classification, ordering and persistence rules the
' sync must satisfy against the datastoreGet item shape.
'
' CW filter: timeOffset > 0 && type != "other" && (!removed || temp).
' Saved: removed == false && temp == false. Only the continue-watching stack
' persists (stremio_library key); everything else is in-memory for the session.

' A datastoreGet library item shape, mirroring the verified API item. options
' override the default neutral state per test.
function LibraryItemFixture(metaId as string, metaType as string, name as string, mtime as string, options = invalid as dynamic) as object
    item = {
        _id: metaId
        type: metaType
        name: name
        poster: "https://img.example.com/" + metaId + ".png"
        removed: false
        temp: false
        _ctime: "2024-01-01T00:00:00Z"
        _mtime: mtime
        state: {
            timeOffset: 0
            duration: 0
            timesWatched: 1
        }
        behaviorHints: { defaultVideoId: invalid }
    }
    if options <> invalid
        if options.timeOffset <> invalid then item.state.timeOffset = options.timeOffset
        if options.duration <> invalid then item.state.duration = options.duration
        if options.videoId <> invalid then item.state.video_id = options.videoId
        if options.removed <> invalid then item.removed = options.removed
        if options.temp <> invalid then item.temp = options.temp
        if options.watched <> invalid then item.state.watched = options.watched
        if options.timesWatched <> invalid then item.state.timesWatched = options.timesWatched
        if options.flaggedWatched <> invalid then item.state.flaggedWatched = options.flaggedWatched
        if options.posterShape <> invalid then item.posterShape = options.posterShape
    end if
    return item
end function

sub Test_LibrarySync_WireFormatCarriesNoTypeTag()
    Harness_Suite("datastoreGet POST body carries authKey/collection/all and no type tag")
    script = [
        {
            method: "POST"
            url: "https://api.strem.io/api/datastoreGet"
            ok: true
            status: 200
            json: { result: [] }
        }
    ]
    http = ScriptedTransport(script)
    res = http.Post("https://api.strem.io/api/datastoreGet", { authKey: "sk_test_key", collection: "libraryItem", all: true })
    Harness_Ok(res.ok, "request succeeds")
    Harness_Equal(http.log.Count(), 1, "one request logged")
    Harness_Equal(http.log[0].body.authKey, "sk_test_key", "request carries the authKey")
    Harness_Equal(http.log[0].body.collection, "libraryItem", "request targets the libraryItem collection")
    Harness_Equal(http.log[0].body.all, true, "request pulls all items")
    Harness_Equal(http.log[0].body.type, invalid, "no type tag on datastoreGet")
end sub

sub Test_LibrarySync_CwClassifiedAndMapped()
    Harness_Suite("SyncFromStremio maps continue-watching items to positions")
    items = []
    items.Push(LibraryItemFixture("tt0133093", "movie", "The Matrix", "2024-06-10T08:00:00Z", { timeOffset: 420000, duration: 8164000, posterShape: "landscape" }))
    items.Push(LibraryItemFixture("tt1234567", "series", "Breaking Bad", "2024-06-15T08:00:00Z", { timeOffset: 1800000, duration: 2700000, videoId: "tt1234567:5:3" }))
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    cw = store.ContinueWatching()
    Harness_Equal(cw.Count(), 2, "two cw entries")
    Harness_Equal(cw[0].videoId, "tt1234567:5:3", "series video id kept")
    Harness_Equal(cw[0].metaId, "tt1234567", "series meta id kept")
    Harness_Equal(cw[0].metaType, "series", "series type kept")
    Harness_Equal(cw[0].season, 5, "series season parsed from video id")
    Harness_Equal(cw[0].episode, 3, "series episode parsed from video id")
    Harness_Equal(cw[0].position, 1800000, "series ms position carried")
    Harness_Equal(cw[0].duration, 2700000, "series duration carried")
    Harness_Equal(cw[1].videoId, "tt0133093", "movie video id is its meta id")
    Harness_Equal(cw[1].season, 0, "movie season zero")
    Harness_Equal(cw[1].episode, 0, "movie episode zero")
    Harness_Equal(cw[1].position, 420000, "movie ms position carried")
    Harness_Equal(cw[1].posterShape, "landscape", "posterShape carried onto the position")
end sub

sub Test_LibrarySync_CwOrderedByMtimeDesc()
    Harness_Suite("SyncFromStremio orders continue watching newest first")
    items = []
    items.Push(LibraryItemFixture("tt0000001", "movie", "Old", "2024-06-01T00:00:00Z", { timeOffset: 1000 }))
    items.Push(LibraryItemFixture("tt0000003", "movie", "Newest", "2024-06-03T00:00:00Z", { timeOffset: 1000 }))
    items.Push(LibraryItemFixture("tt0000002", "movie", "Middle", "2024-06-02T00:00:00Z", { timeOffset: 1000 }))
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    cw = store.ContinueWatching()
    Harness_Equal(cw.Count(), 3, "three cw entries")
    Harness_Equal(cw[0].metaId, "tt0000003", "newest mtime first")
    Harness_Equal(cw[1].metaId, "tt0000002", "middle mtime second")
    Harness_Equal(cw[2].metaId, "tt0000001", "oldest mtime last")
end sub

sub Test_LibrarySync_CwClassificationRules()
    Harness_Suite("continue-watching filter: timeOffset, type and removed/temp")
    items = []
    items.Push(LibraryItemFixture("tt1000001", "movie", "Zero Offset", "2024-06-01T00:00:00Z"))                                                    ' no timeOffset -> not cw
    items.Push(LibraryItemFixture("tt1000002", "other", "Other Type", "2024-06-02T00:00:00Z", { timeOffset: 1000, videoId: "tt1000002" }))          ' type "other" -> not cw
    items.Push(LibraryItemFixture("tt1000003", "movie", "Removed", "2024-06-03T00:00:00Z", { timeOffset: 1000, removed: true }))                     ' removed non-temp -> not cw
    items.Push(LibraryItemFixture("tt1000004", "movie", "Temp Removed", "2024-06-04T00:00:00Z", { timeOffset: 1000, removed: true, temp: true }))      ' removed but temp -> cw
    items.Push(LibraryItemFixture("tt1000005", "movie", "Active", "2024-06-05T00:00:00Z", { timeOffset: 1000 }))                                      ' plain watch -> cw
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    cw = store.ContinueWatching()
    Harness_Equal(cw.Count(), 2, "only temp-removed and active qualify")
    Harness_Equal(cw[0].metaId, "tt1000005", "active watch newest")
    Harness_Equal(cw[1].metaId, "tt1000004", "removed-but-temp retains its watch state")
end sub

sub Test_LibrarySync_ChannelsKeptOutOfCw()
    Harness_Suite("SyncFromStremio keeps channel/tv items saved but out of continue watching")
    items = []
    items.Push(LibraryItemFixture("cnn1", "channel", "CNN", "2024-06-03T00:00:00Z", { timeOffset: 1000 }))        ' live channel, would qualify on position alone
    items.Push(LibraryItemFixture("ntv1", "tv", "NTV", "2024-06-02T00:00:00Z", { timeOffset: 1000 }))            ' live tv, same
    items.Push(LibraryItemFixture("tt1000005", "movie", "Active", "2024-06-01T00:00:00Z", { timeOffset: 1000 })) ' plain watch -> cw
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    cw = store.ContinueWatching()
    Harness_Equal(cw.Count(), 1, "only the movie qualifies")
    Harness_Equal(cw[0].metaId, "tt1000005", "movie entry kept")
    Harness_Ok(store.IsSaved("cnn1"), "channel still saved")
    Harness_Ok(store.IsSaved("ntv1"), "tv still saved")
    Harness_Equal(store.StremioLibraryItems().Count(), 3, "channels retained in the full library")
end sub

sub Test_LibrarySync_SavedMappedInMemory()
    Harness_Suite("SyncFromStremio fills saved entries for the session")
    items = []
    items.Push(LibraryItemFixture("tt0111161", "movie", "Shawshank", "2024-06-01T00:00:00Z", { posterShape: "square" }))
    items.Push(LibraryItemFixture("tt2000001", "movie", "Removed", "2024-06-01T00:00:00Z", { removed: true }))
    items.Push(LibraryItemFixture("tt2000002", "movie", "Temp", "2024-06-01T00:00:00Z", { temp: true }))
    items.Push(LibraryItemFixture("tt0111161", "movie", "Shawshank", "2024-06-02T00:00:00Z"))
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    saved = store.SavedItems()
    Harness_Equal(saved.Count(), 1, "only non-removed non-temp saved, deduped")
    Harness_Equal(saved[0].metaId, "tt0111161", "saved entry present")
    Harness_Equal(saved[0].posterShape, "square", "posterShape carried onto the saved record")
    Harness_Equal(store.IsSaved("tt0111161"), true, "is saved")
    Harness_Equal(store.IsSaved("tt2000001"), false, "removed item not saved")
    Harness_Equal(store.IsSaved("tt2000002"), false, "temp item not saved")
end sub

sub Test_LibrarySync_StremioLibraryKeepsEveryItem()
    Harness_Suite("stremioLibrary keeps all items, cw or not")
    items = []
    items.Push(LibraryItemFixture("tt0111161", "movie", "Shawshank", "2024-06-01T00:00:00Z"))
    items.Push(LibraryItemFixture("tt0133093", "movie", "Matrix", "2024-06-02T00:00:00Z", { timeOffset: 1000 }))
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    Harness_Equal(store.StremioLibraryItems().Count(), 2, "both items retained in memory")
    Harness_Equal(store.StremioLibraryItems()[0]._id, "tt0111161", "saved item kept")
    Harness_Equal(store.StremioLibraryItems()[1]._id, "tt0133093", "cw item kept")
end sub

sub Test_LibrarySync_VideoIdParsing()
    Harness_Suite("video id parsing: movie, series and unparsable")
    items = []
    items.Push(LibraryItemFixture("tt3000001", "series", "Five Parter", "2024-06-02T00:00:00Z", { timeOffset: 1000, videoId: "tt3000001:5:2" }))     ' 3 parts -> series
    items.Push(LibraryItemFixture("tt3000002", "movie", "Two Parter", "2024-06-03T00:00:00Z", { timeOffset: 1000, videoId: "tt3000002:1" }))         ' 2 parts -> unparsable, dropped
    items.Push(LibraryItemFixture("tt3000003", "movie", "Bare Id", "2024-06-04T00:00:00Z", { timeOffset: 1000, videoId: "tt3000003" }))              ' 1 part -> movie
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    cw = store.ContinueWatching()
    Harness_Equal(cw.Count(), 2, "unparsable video id dropped from cw")
    Harness_Equal(cw[0].videoId, "tt3000003", "bare id movie entry kept")
    Harness_Equal(cw[1].videoId, "tt3000001:5:2", "series entry kept")
    Harness_Equal(store.StremioLibraryItems().Count(), 3, "dropped item still in the full library")
end sub

sub Test_LibrarySync_PrunesPerMeta()
    Harness_Suite("multiple library items for one meta keep only the newest")
    items = []
    items.Push(LibraryItemFixture("tt1234567", "series", "Breaking Bad", "2024-05-01T00:00:00Z", { timeOffset: 1000, videoId: "tt1234567:1:1" }))
    items.Push(LibraryItemFixture("tt1234567", "series", "Breaking Bad", "2024-06-01T00:00:00Z", { timeOffset: 2000, videoId: "tt1234567:2:2" }))
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    cw = store.ContinueWatching()
    Harness_Equal(cw.Count(), 1, "one entry per meta")
    Harness_Equal(cw[0].videoId, "tt1234567:2:2", "newest episode wins")
    Harness_Equal(cw[0].metaId, "tt1234567", "meta kept")
end sub

' Zero-pad a small id segment so ids and ISO day strings sort deterministically.
function Pad2(n as integer) as string
    if n < 10 then return "0" + n.ToStr()
    return n.ToStr()
end function

function Pad3(n as integer) as string
    if n < 10 then return "00" + n.ToStr()
    if n < 100 then return "0" + n.ToStr()
    return n.ToStr()
end function

sub Test_LibrarySync_CappedAtMax()
    Harness_Suite("continue watching capped at MAX_CONTINUE_WATCHING after sync")
    items = []
    for i = 1 to 12
        items.Push(LibraryItemFixture("tt4" + Pad3(i), "movie", "Movie " + i.ToStr(), "2024-06-" + Pad2(20 - i), { timeOffset: 1000 }))
    end for
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    cw = store.ContinueWatching()
    Harness_Equal(cw.Count(), 8, "capped to eight")
    Harness_Equal(cw[0].metaId, "tt4001", "newest kept first")
    Harness_Equal(cw[7].metaId, "tt4008", "oldest retained is the 8th newest")
end sub

sub Test_LibrarySync_PersistsOnlyCw()
    Harness_Suite("stremio sync persists only the continue-watching stack")
    registry = MockRegistry()
    items = []
    items.Push(LibraryItemFixture("tt0111161", "movie", "Shawshank", "2024-06-01T00:00:00Z"))
    items.Push(LibraryItemFixture("tt0133093", "movie", "Matrix", "2024-06-02T00:00:00Z", { timeOffset: 120000, duration: 3600000 }))
    store = LibraryStore(registry, "stremio")
    store.SyncFromStremio(items)

    raw = registry.Read("stremio_library")
    Harness_Ok(raw <> "", "stremio_library key written")
    parsed = ParseJson(raw)
    Harness_Ok(parsed <> invalid, "stremio_library parses")
    Harness_Equal(parsed.continueWatching.Count(), 1, "only cw persisted")
    Harness_Equal(parsed.continueWatching[0].videoId, "tt0133093", "cw entry persisted")
    Harness_Ok(parsed.saved = invalid, "saved map not persisted")
    Harness_Equal(registry.Read("library"), "", "guest key untouched")

    reopened = LibraryStore(registry, "stremio")
    Harness_Equal(reopened.ContinueWatching().Count(), 1, "cw restored on reload")
    Harness_Equal(reopened.SavedItems().Count(), 0, "saved not persisted (memory-only)")
    Harness_Equal(reopened.StremioLibraryItems().Count(), 0, "full library not persisted (memory-only)")
end sub

sub Test_LibrarySync_RejectsBadInput()
    Harness_Suite("SyncFromStremio ignores invalid input")
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(invalid)
    Harness_Equal(store.ContinueWatching().Count(), 0, "invalid input leaves cw empty")
    Harness_Equal(store.StremioLibraryItems().Count(), 0, "invalid input leaves library empty")
    store.SyncFromStremio("not an array")
    Harness_Equal(store.ContinueWatching().Count(), 0, "non-array leaves cw empty")
end sub

sub Test_LibrarySync_GuestSessionIgnored()
    Harness_Suite("SyncFromStremio refuses to clobber a guest session")
    store = LibraryStore(MockRegistry())
    store.SetPosition("tt0133093", "tt0133093", "movie", 0, 0, "The Matrix", "", 120000, 3600000)
    store.AddSaved("tt0111161", "movie", "Shawshank")
    items = []
    items.Push(LibraryItemFixture("tt9999999", "movie", "Remote", "2024-06-01T00:00:00Z", { timeOffset: 1000 }))
    store.SyncFromStremio(items)

    Harness_Equal(store.ContinueWatching().Count(), 1, "guest cw untouched")
    Harness_Equal(store.ContinueWatching()[0].videoId, "tt0133093", "guest position kept")
    Harness_Equal(store.SavedItems().Count(), 1, "guest saved kept")
    Harness_Equal(store.StremioLibraryItems().Count(), 0, "remote library not adopted into a guest session")
end sub

sub Test_LibrarySync_AccountWatchedFlags()
    Harness_Suite("account layer drives IsWatched and SeriesStatus from sync flags")
    items = []
    items.Push(LibraryItemFixture("tt5000001", "movie", "Plain", "2024-06-01T00:00:00Z", { timesWatched: 0 }))
    items.Push(LibraryItemFixture("tt5000002", "movie", "TimesWatched", "2024-06-02T00:00:00Z"))
    items.Push(LibraryItemFixture("tt5000003", "movie", "Flagged", "2024-06-03T00:00:00Z", { timesWatched: 0, flaggedWatched: 1 }))
    items.Push(LibraryItemFixture("tt5000004", "series", "InProgress", "2024-06-04T00:00:00Z", { timesWatched: 0, timeOffset: 1000 }))
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    Harness_Ok(not store.IsWatched("tt5000001"), "untouched item not watched")
    Harness_Ok(store.IsWatched("tt5000002"), "timesWatched flags the whole item watched")
    Harness_Ok(store.IsWatched("tt5000003"), "flaggedWatched flags the whole item watched")
    Harness_Ok(not store.IsWatched("tt5000004"), "in-progress is not watched")
    Harness_Equal(store.SeriesStatus("tt5000001"), "none", "untouched item is none")
    Harness_Equal(store.SeriesStatus("tt5000002"), "done", "account watched is done")
    Harness_Equal(store.SeriesStatus("tt5000004"), "progress", "account in-progress is progress")
    Harness_Equal(store.SeriesStatus(""), "none", "blank id is none")
    Harness_Equal(store.WatchedGlyph("tt5000001", "movie"), "", "untouched item has no badge")
    Harness_Equal(store.WatchedGlyph("tt5000002", "movie"), "eye", "account-watched movie shows the watched glyph")
    Harness_Equal(store.WatchedGlyph("tt5000003", "movie"), "eye", "flagged-watched movie shows the watched glyph")
    Harness_Equal(store.WatchedGlyph("tt5000004", "series"), "clock", "account in-progress series shows the progress glyph")
    Harness_Equal(store.WatchedGlyph("", "series"), "", "blank id has no badge")
end sub

sub Test_LibrarySync_EpisodeWatchedFromBitfield()
    Harness_Suite("EpisodeWatched decodes the account watched bitfield against the episode list")
    items = []
    ' Sparse coherent field: bits 3 and 7 set, authored over the same 12-id list
    ' the decode runs against, anchored on the last watched id (index 7).
    items.Push(LibraryItemFixture("tt3330003", "series", "Sparse", "2024-06-01T00:00:00Z", { timesWatched: 0, watched: "tt3330003:1:8:8:eJzrYAAAARIAiQ==" }))
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    ids = ["tt3330003:1:1", "tt3330003:1:2", "tt3330003:1:3", "tt3330003:1:4", "tt3330003:1:5", "tt3330003:1:6", "tt3330003:1:7", "tt3330003:1:8", "tt3330003:1:9", "tt3330003:1:10", "tt3330003:1:11", "tt3330003:1:12"]
    Harness_Ok(store.EpisodeWatched("tt3330003", 1, 4, ids), "bit 3 episode is watched")
    Harness_Ok(store.EpisodeWatched("tt3330003", 1, 8, ids), "bit 7 episode is watched")
    Harness_Ok(not store.EpisodeWatched("tt3330003", 1, 5, ids), "bit 4 episode is not watched")
    Harness_Ok(not store.EpisodeWatched("tt3330003", 2, 1, ids), "episode outside the list is not watched")
    Harness_Ok(not store.EpisodeWatched("tt9999999", 1, 1, ids), "series never synced is not watched")
    Harness_Ok(not store.EpisodeWatched("tt3330003", 1, 1, invalid), "invalid episode list is refused")
end sub

sub Test_LibrarySync_EpisodeWatchedEmptyBitfield()
    Harness_Suite("EpisodeWatched ignores missing and empty account bitfields")
    items = []
    items.Push(LibraryItemFixture("tt5000005", "series", "No Bits", "2024-06-01T00:00:00Z", { timesWatched: 0 }))
    items.Push(LibraryItemFixture("tt5000006", "series", "Empty Bits", "2024-06-02T00:00:00Z", { timesWatched: 0, watched: "" }))
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    Harness_Ok(not store.EpisodeWatched("tt5000005", 1, 1, ["tt5000005:1:1"]), "no bitfield means not watched")
    Harness_Ok(not store.EpisodeWatched("tt5000006", 1, 1, ["tt5000006:1:1"]), "empty bitfield means not watched")
end sub