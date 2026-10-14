function SearchTest_Event(task as object) as object
    return {
        task: task
        GetRoSGNode: function() as object
            return m.task
        end function
    }
end function

sub SearchTest_Reset()
    m.reaped = []
    m.flushed = 0
    m.rendered = 0
    m.updated = 0
    m.rows = []
    m.landed = {}
    m.searchFailed = false
    m.searchOrder = [{ key: "provider|movie|top", addonAddress: "https://catalog.example", title: "Movies", rawType: "movie" }]
    m.top = {
        screenActive: true
        focused: false
        scene: { dialog: invalid }
        getScene: function() as object
            return m.scene
        end function
        SetFocus: function(on as boolean) as boolean
            m.focused = on
            return true
        end function
    }
    m.results = {
        focused: false
        SetFocus: function(on as boolean) as boolean
            m.focused = on
            return true
        end function
    }
end sub

sub AsyncTask_Reap(task as object, parent as object, doStop as boolean)
    m.reaped.Push(task.id)
end sub
sub FlushPendingQuery()
    m.flushed = m.flushed + 1
end sub
sub RenderRows()
    m.rendered = m.rendered + 1
end sub
sub UpdateSearchStatus()
    m.updated = m.updated + 1
end sub

Harness_Suite("Search rejects stale query and source events")
SearchTest_Reset()
old = { id: "searchLoader1", addonKey: "provider", result: { sections: [{ key: "provider|movie|top", metas: [{ id: "ttold", type: "movie", name: "Old query" }] }] } }
current = { id: "searchLoader2", addonKey: "provider", result: { sections: [{ key: "provider|movie|top", metas: [{ id: "ttnew", type: "movie", name: "New query" }] }] } }
m.searchTasks = { provider: current }
onSearchLoaded(SearchTest_Event({ id: "searchLoader2", addonKey: "provider", result: invalid }))
Harness_Equal(m.searchTasks.provider.id, "searchLoader2", "blank query notification preserves running worker")
Harness_Equal(m.reaped.Count(), 0, "blank query notification is not reaped")
onSearchLoaded(SearchTest_Event(old))
Harness_Equal(m.searchTasks.provider.id, "searchLoader2", "stale event leaves replacement worker intact")
Harness_Equal(m.landed.Count(), 0, "stale results do not enter current query")
Harness_Equal(m.reaped.Count(), 0, "stale notification does not reap replacement worker")
onSearchLoaded(SearchTest_Event(current))
Harness_Equal(m.searchTasks.provider, invalid, "current event claims its own slot")
Harness_Equal(m.reaped[0], "searchLoader2", "current worker is reaped")
Harness_Equal(m.rows[0].metas[0].id, "ttnew", "current query result reaches visible model")
Harness_Ok(m.results.focused, "first usable results take list focus")
onSearchLoaded(SearchTest_Event(current))
Harness_Equal(m.reaped.Count(), 1, "duplicate completion is ignored")
m.sourcesTask = { id: "searchSources4", result: { sources: [{ address: "new" }] } }
onSourcesLoaded(SearchTest_Event({ id: "searchSources4", result: invalid }))
Harness_Equal(m.sourcesTask.id, "searchSources4", "blank source notification preserves running worker")
onSourcesLoaded(SearchTest_Event({ id: "searchSources3", result: { sources: [{ address: "old" }] } }))
Harness_Equal(m.sourcesTask.id, "searchSources4", "stale source notification leaves current worker intact")
Harness_Equal(m.flushed, 0, "stale source notification cannot start query")
onSourcesLoaded(SearchTest_Event(m.sourcesTask))
Harness_Equal(m.sourcesTask, invalid, "current source completion clears slot")
Harness_Equal(m.sources[0].address, "new", "current source answer adopted")
Harness_Equal(m.flushed, 1, "pending query released once")
m.workerSequence = 0
Harness_Equal(NextSearchWorkerId("searchLoader"), "searchLoader1", "first worker id")
Harness_Equal(NextSearchWorkerId("searchSources"), "searchSources2", "worker sequence spans request types")

Harness_Suite("Search preserves modal focus and filtered selection")
SearchTest_Reset()
RestoreSearchFocus()
Harness_Ok(m.top.focused, "empty results leave a working screen focus target")
Harness_Ok(not m.results.focused, "empty list is not asked to take focus")
m.rows = [{}]
m.top.scene.dialog = { id: "otherDialog" }
RestoreSearchFocus()
Harness_Ok(not m.results.focused, "provider results cannot steal focus from dialog")
m.searchDialog = { id: "searchDialog5" }
onSearchDialogClosed(SearchTest_Event({ id: "searchDialog4" }))
Harness_Equal(m.searchDialog.id, "searchDialog5", "stale dialog close does not discard new dialog")
onSearchDialogClosed(SearchTest_Event(m.searchDialog))
Harness_Equal(m.top.scene.dialog.id, "otherDialog", "closing search preserves replacement modal")
m.top.scene.dialog = invalid
m.top.screenActive = false
RestoreSearchFocus()
Harness_Ok(not m.results.focused, "hidden Search cannot steal focus")
m.top.screenActive = true
RestoreSearchFocus()
Harness_Ok(m.results.focused, "visible nonempty Search restores result focus")
raw = [42, { id: "", type: "movie", name: "Invalid" }, { id: "ttfirst", type: "movie", name: "First", poster: 42, runtime: {} }, { id: "ttsecond", type: "series", name: "Second" }]
valid = SearchUsableMetas(raw)
Harness_Equal(valid.Count(), 2, "invalid provider entries omitted")
Harness_Equal(valid[0].poster, "", "invalid artwork field cannot break typed binding")
Harness_Equal(valid[0].runtime, invalid, "invalid runtime cannot break Details formatting")
Harness_Equal(raw[2].poster, 42, "normalizing results does not mutate provider records")
m.rows = [{ addonAddress: "https://catalog.example", metas: valid }]
m.results.rowItemSelected = [0, 1]
onResultSelected()
Harness_Equal(m.top.pushRequest.params.meta.id, "ttsecond", "selected displayed index resolves filtered title")
Harness_Equal(SearchUsableMetas("garbage").Count(), 0, "nonarray response safe")

Harness_Suite("Home and Search keep all content in compact viewports")
Harness_Equal(HomeVisibleRows(0), 0, "empty Home has zero visible rows")
Harness_Equal(HomeVisibleRows(1), 1, "one Home row remains one")
Harness_Equal(HomeVisibleRows(30), 2, "many Home catalogs use two visible slots")
Harness_Equal(SearchVisibleRows(0), 0, "empty Search has zero visible rows")
Harness_Equal(SearchVisibleRows(30), 2, "many Search catalogs use two visible slots")
portrait = RowCellSize({ metaType: "movie", posterShape: "poster" })
Harness_Equal(portrait[0], 216, "compact Home portrait width")
Harness_Equal(portrait[1], 324, "compact Home portrait height")
landscape = SearchCellSize("movie", "landscape")
Harness_Equal(landscape[0], 384, "compact Search landscape width")
Harness_Equal(landscape[1], 216, "compact Search landscape height")
square = SearchCellSize("channel", "")
Harness_Equal(square[0], 216, "compact Search square width")
Harness_Equal(square[1], 216, "compact Search square height")
Harness_Finish()
if m.failed > 0
    bad = invalid
    x = bad.poison
end if
