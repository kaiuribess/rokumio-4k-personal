' watchstatepush tests — the two testable halves of the write-back pipeline: the
' datastorePut wire format (through ScriptedTransport) and
' LibraryStore.BuildWatchStateItem (the merge that turns a player's position
' update into a full LibraryItem to push, then commits it back into the cached
' library). The LibraryPutTask worker itself runs its own Transport on a task
' thread (like AddonSyncTask/LibrarySyncTask), so its HTTP cannot be injected
' here; MainScene's coalescing is pure orchestration with no runnable unit
' surface in the interpreter — the store merge and the wire format are the
' contracts that pin it.

' A datastoreGet library item shape (same family as the librarysync fixture) —
' the BuildWatchStateItem merge must preserve every field it does not overwrite.
function WatchItemFixture(metaId as string, metaType as string, name as string, mtime as string, options = invalid as dynamic) as object
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
            timesWatched: 3
            watched: invalid
        }
        behaviorHints: { defaultVideoId: invalid }
    }
    if options <> invalid
        if options.removed <> invalid then item.removed = options.removed
        if options.temp <> invalid then item.temp = options.temp
        if options.timeOffset <> invalid then item.state.timeOffset = options.timeOffset
        if options.videoId <> invalid then item.state.video_id = options.videoId
        if options.timesWatched <> invalid then item.state.timesWatched = options.timesWatched
    end if
    return item
end function

sub Test_WatchStatePush_PostsDatastorePutWithoutTypeTag()
    Harness_Suite("datastorePut POST body carries authKey/collection/changes and no type tag")
    script = [
        {
            method: "POST"
            url: "https://api.strem.io/api/datastorePut"
            ok: true
            status: 200
            json: { result: { success: true } }
        }
    ]
    http = ScriptedTransport(script)
    item = { _id: "tt0133093" }
    res = http.Post("https://api.strem.io/api/datastorePut", { authKey: "sk_test_key", collection: "libraryItem", changes: [item] })
    Harness_Ok(res.ok, "request succeeds")
    Harness_Ok(res.json.result.success, "result envelope reports success")
    Harness_Equal(http.log.Count(), 1, "one request logged")
    Harness_Equal(http.log[0].body.authKey, "sk_test_key", "request carries the authKey")
    Harness_Equal(http.log[0].body.collection, "libraryItem", "request targets the libraryItem collection")
    Harness_Equal(http.log[0].body.changes.Count(), 1, "one change entry")
    Harness_Equal(http.log[0].body.changes[0]._id, "tt0133093", "change entry is the library item")
    Harness_Equal(http.log[0].body.type, invalid, "no type tag on datastorePut")
end sub

sub Test_WatchStatePush_ClonesCachedItemAndOverwritesState()
    Harness_Suite("BuildWatchStateItem clones the cached item and overwrites only the watch state")
    items = []
    items.Push(WatchItemFixture("tt1234567", "series", "Breaking Bad", "2024-06-01T00:00:00Z", { videoId: "tt1234567:1:1", timesWatched: 3 }))
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    item = store.BuildWatchStateItem({ videoId: "tt1234567:5:3", metaId: "tt1234567", metaType: "series", name: "Breaking Bad", poster: "https://img.example.com/tt1234567.png", position: 1800000, duration: 2700000 }, "2026-09-15T12:00:00Z")
    Harness_Ok(item <> invalid, "item built")
    Harness_Equal(item._id, "tt1234567", "meta id kept")
    Harness_Equal(item.type, "series", "type kept")
    Harness_Equal(item.state.video_id, "tt1234567:5:3", "video id overwritten")
    Harness_Equal(item.state.timeOffset, 1800000, "position overwritten")
    Harness_Equal(item.state.duration, 2700000, "duration overwritten")
    Harness_Equal(item.state.lastWatched, "2026-09-15T12:00:00Z", "lastWatched stamped")
    Harness_Equal(item._mtime, "2026-09-15T12:00:00Z", "mtime stamped")
    Harness_Equal(item.state.timesWatched, 3, "untracked server field preserved")
    Harness_Equal(item.removed, false, "removed flag preserved")
    Harness_Equal(item.temp, false, "temp flag preserved")
    Harness_Equal(item.name, "Breaking Bad", "name carried")
end sub

sub Test_WatchStatePush_MovieVideoIdFallsBackToMetaId()
    Harness_Suite("BuildWatchStateItem defaults the video id to the meta id for movies")
    items = []
    items.Push(WatchItemFixture("tt0133093", "movie", "The Matrix", "2024-06-10T00:00:00Z"))
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)
    item = store.BuildWatchStateItem({ metaId: "tt0133093", position: 420000, duration: 8164000 }, "2026-09-15T12:00:00Z")
    Harness_Ok(item <> invalid, "item built")
    Harness_Equal(item.state.video_id, "tt0133093", "movie video id is the meta id")
    Harness_Equal(item.state.timeOffset, 420000, "position carried")
end sub

sub Test_WatchStatePush_UnknownMetaFallsBackToTemp()
    Harness_Suite("BuildWatchStateItem builds a temp item for metas the cache has never seen")
    store = LibraryStore(MockRegistry(), "stremio")
    item = store.BuildWatchStateItem({ videoId: "tt9999999", metaId: "tt9999999", metaType: "movie", name: "New Arrival", poster: "https://img.example.com/tt9999999.png", position: 60000, duration: 600000 }, "2026-09-15T12:00:00Z")
    Harness_Ok(item <> invalid, "item built")
    Harness_Equal(item._id, "tt9999999", "meta id set")
    Harness_Equal(item.type, "movie", "type set")
    Harness_Equal(item.name, "New Arrival", "name set")
    Harness_Equal(item.temp, true, "temp item so it never promotes to the permanent library")
    Harness_Equal(item.removed, true, "removed so it never shows as saved")
    Harness_Equal(item.state.video_id, "tt9999999", "video id set")
    Harness_Equal(item.state.timeOffset, 60000, "position carried")
    Harness_Equal(item.state.lastWatched, "2026-09-15T12:00:00Z", "lastWatched stamped")
    Harness_Equal(item._mtime, "2026-09-15T12:00:00Z", "mtime stamped")
end sub

sub Test_WatchStatePush_CommitsToCachedItem()
    Harness_Suite("BuildWatchStateItem commits the built item into the cached library")
    items = []
    items.Push(WatchItemFixture("tt1234567", "series", "Breaking Bad", "2024-06-01T00:00:00Z", { videoId: "tt1234567:1:1", timesWatched: 2 }))
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)
    item = store.BuildWatchStateItem({ videoId: "tt1234567:5:3", metaId: "tt1234567", metaType: "series", position: 1800000, duration: 2700000 }, "2026-09-15T12:00:00Z")
    Harness_Ok(item <> invalid, "item built")
    cached = store.StremioLibraryItems()[0]
    Harness_Equal(cached.state.video_id, "tt1234567:5:3", "cached video id advanced to the committed item")
    Harness_Equal(cached.state.timeOffset, 1800000, "cached position advanced to the committed item")
    Harness_Equal(cached._mtime, "2026-09-15T12:00:00Z", "cached mtime advanced to the committed item")
end sub

sub Test_WatchStatePush_RemovedItemResurfacesInContinueWatching()
    Harness_Suite("watching an item the user added then removed re-qualifies it for continue watching")
    ' The account holds the tombstone an earlier remove push left behind:
    ' removed, not temp, which is exactly what hides it from CW everywhere.
    items = []
    items.Push(WatchItemFixture("tt0133093", "movie", "The Matrix", "2024-06-01T00:00:00Z", { removed: true, temp: false, timesWatched: 0 }))
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    item = store.BuildWatchStateItem({ videoId: "tt0133093", metaId: "tt0133093", metaType: "movie", name: "The Matrix", poster: "https://img.example.com/tt0133093.png", position: 420000, duration: 8164000 }, "2026-09-15T12:00:00Z")
    Harness_Ok(item <> invalid, "item built")
    Harness_Equal(item.removed, true, "the title stays out of the saved library")
    Harness_Equal(item.temp, true, "but temp flips on, so the server keeps it in continue watching")

    cached = store.StremioLibraryItems()[0]
    Harness_Equal(cached.temp, true, "the commit carries the temp flag for the next push")
    Harness_Ok(StremioLibraryCodec().ParseLibraryItem(cached).cw, "a fresh sync would derive it as continue watching again")
end sub

sub Test_WatchStatePush_GuestSessionRefused()
    Harness_Suite("BuildWatchStateItem refuses a guest session")
    store = LibraryStore(MockRegistry())
    item = store.BuildWatchStateItem({ videoId: "tt0133093", metaId: "tt0133093", metaType: "movie", position: 1000 }, "2026-09-15T12:00:00Z")
    Harness_Equal(item, invalid, "guest store returns invalid, never pushes")
end sub

sub Test_WatchStatePush_TimestampAutoStampedWhenOmitted()
    Harness_Suite("BuildWatchStateItem stamps an ISO timestamp when now is not given")
    store = LibraryStore(MockRegistry(), "stremio")
    item = store.BuildWatchStateItem({ videoId: "tt0133093", metaId: "tt0133093", metaType: "movie", position: 1 }, "")
    Harness_Ok(item <> invalid, "item built")
    Harness_Ok(item._mtime <> "", "mtime auto-stamped")
    Harness_Equal(item._mtime, item.state.lastWatched, "item and state share the timestamp")
end sub

sub Test_WatchStatePush_MetaIdRequired()
    Harness_Suite("BuildWatchStateItem requires a meta id")
    store = LibraryStore(MockRegistry(), "stremio")
    Harness_Equal(store.BuildWatchStateItem(invalid, "2026-09-15T12:00:00Z"), invalid, "invalid packet refused")
    Harness_Equal(store.BuildWatchStateItem({ metaId: "", position: 1 }, "2026-09-15T12:00:00Z"), invalid, "blank meta id refused")
end sub