' SearchScreen — multi-add-on title search. Entry shows a voice-enabled system
' keyboard dialog; Search fans the query out to every
' search-capable catalog across all installed add-ons. Rows appear only for
' catalogs that return results — nothing is premised on the screen, so a catalog
' with no matches (or a failed add-on) simply never shows a row. Each row is
' titled "{Catalog} - {mediaType}" ("Popular - Movies", "HD - Tv channel").
'
' Sources are resolved once per installed add-on set through the same shared
' resolution as Discover (CatalogSourcesTask fetches manifests the registry has
' none for; a query arriving before sources land is held as m.pendingQuery and
' run when they do). One SearchLoaderTask per add-on runs off the render thread,
' carrying that add-on's catalogs, and lands a { sections } batch the screen fans
' into rows by catalog key — so results appear as each add-on answers, in the
' same order the catalogs were discovered. OK on a result pushes DetailsScreen
' with the meta's own add-on address. The * (options) key reopens the keyboard.

sub init()
    m.status = m.top.FindNode("searchStatus")
    m.results = m.top.FindNode("searchResults")
    m.subtitle = m.top.FindNode("searchSub")

    t = Theme()
    m.top.FindNode("searchTitle").color = t.accent
    m.top.FindNode("searchSub").color = t.textSecondary
    m.top.FindNode("searchFooterBg").color = t.screenBg
    m.top.FindNode("searchHelp").color = t.textPrimary
    m.status.color = t.accent
    m.results.rowLabelOffset = [[0,10]]
    m.results.focusBitmapBlendColor = t.accent

    m.results.ObserveField("rowItemSelected", "onResultSelected")

    m.pendingQuery = ""
    m.lastQuery = ""
    m.sources = []
    m.sourcesSignature = ""
    m.sourcesTask = invalid
    m.searchOrder = []
    m.landed = {}
    m.searchFailed = false
    m.rows = []
    m.searchTasks = invalid
    m.workerSequence = 0
    m.searchDialog = invalid
end sub

function OnEnter(params as object) as void
    ' The add-on set can move while Search is off-screen (install/uninstall,
    ' session swap). Re-derive when it did, so the rows never describe a
    ' registry that no longer exists.
    if m.stores <> invalid and CatalogSignature() <> m.sourcesSignature then ResetSearch()

    ' A caller-supplied query (future rail-injected) runs as soon as sources are
    ' in hand; it is held in m.pendingQuery until they land.
    if params <> invalid and params.query <> invalid and params.query <> ""
        m.pendingQuery = params.query
        EnsureSources()
        return
    end if

    ' Re-entry after Details: results are still here, just take focus back.
    if m.rows.Count() > 0
        m.results.SetFocus(true)
        return
    end if

    EnsureSources()
    ShowSearchDialog()
end function

function OnExit() as void
    ' Any query held while sources were still resolving is dropped with the
    ' exit — a later re-entry shows a fresh prompt, it must not replay it.
    m.pendingQuery = ""
    CancelSearch()
    CancelSources()
    if m.searchDialog <> invalid
        m.searchDialog.close = true
        m.searchDialog = invalid
    end if
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

' --- sources (which add-ons serve which catalogs) ---------------------------

' The installed add-on set the current sources were derived from, as a
' comparable string. Mirrors Home/Discover: derive from live store state, sort
' so ordering cannot make two equal sets look different, join. No network — a
' set comparison, not a re-derivation.
function CatalogSignature() as string
    if m.stores = invalid then return ""
    addons = m.stores.addons.callFunc("AddonsGetAll")
    if Type(addons) <> "roArray" then return ""
    parts = []
    for each addon in addons
        if Type(addon) <> "roAssociativeArray" then continue for
        parts.Push({id:addon.id,address:addon.address,name:addon.name,version:addon.version,resources:addon.resources,types:addon.types,idPrefixes:addon.idPrefixes,catalogs:addon.catalogs})
    end for
    return FormatJson(parts)
end function

' Resolve the catalog sources, reusing the cache when the installed set is
' unchanged. When every add-on already carries its catalog descriptors the
' sources are built inline; otherwise a CatalogSourcesTask fetches the missing
' manifests off the UI thread (the built-in seeds are the only packets that
' need it).
sub EnsureSources()
    if m.stores = invalid
        m.status.text = "Failed to load add-ons."
        return
    end if

    signature = CatalogSignature()
    if signature = m.sourcesSignature and m.sources.Count() > 0 then
        FlushPendingQuery()
        return
    end if

    addons = m.stores.addons.callFunc("AddonsGetAll")
    if addons = invalid then addons = []

    packets = []
    allKnown = true
    for each addon in addons
        address = addon.address
        if address = invalid or address = "" then continue for
        resources = addon.resources
        ' Catalog support is declared by the catalogs list, independent of
        ' the manifest's resource list (Stremio's catalog special case).
        if Type(addon.catalogs) = "roArray" and addon.catalogs.Count() = 0 then continue for
        if addon.catalogs = invalid or Type(addon.catalogs) <> "roArray" then allKnown = false
        name = addon.name
        if name = invalid then name = ""
        packets.Push({ address: address, name: name, resources: resources, catalogs: addon.catalogs })
    end for

    CancelSources()
    m.sources = []
    m.sourcesSignature = signature
    if packets.Count() = 0
        m.sources = []
        FlushPendingQuery()
        return
    end if

    if allKnown
        m.sources = packets
        FlushPendingQuery()
        return
    end if

    CancelSources()
    task = AsyncTask_Launch(m.top, "CatalogSourcesTask", "onSourcesLoaded", { addons: packets }, NextSearchWorkerId("searchSources"))
    m.sourcesTask = task
end sub

' A CatalogSourcesTask result landed. Dropped when it arrived after a cancel
' (m.sourcesTask was cleared) so a late manifest can never repaint a screen the
' user already left.
sub onSourcesLoaded(event as object)
    if m.sourcesTask = invalid then return
    task = event.GetRoSGNode()
    if task = invalid then return
    ' A canceled worker may already have queued an observer notification.
    ' Compare scalar ids; comparing SceneGraph node references can throw.
    if task.id <> m.sourcesTask.id then return
    result = task.result
    if result = invalid then return
    m.sourcesTask = invalid
    AsyncTask_Reap(task, m.top, false)

    if result = invalid or result.sources = invalid or Type(result.sources) <> "roArray"
        m.status.text = "Failed to load add-ons."
        return
    end if

    m.sources = result.sources
    FlushPendingQuery()
end sub

sub CancelSources()
    if m.sourcesTask <> invalid
        task = m.sourcesTask
        m.sourcesTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

' A query that arrived before sources landed: run it now that they have. Nothing
' to do for a plain entry (no pending query).
sub FlushPendingQuery()
    if m.pendingQuery <> invalid and m.pendingQuery <> "" then
        query = m.pendingQuery
        m.pendingQuery = ""
        RunSearch(query)
    end if
end sub

' Drop the sources/rows/results for a changed add-on set so the next entry
' re-resolves from scratch.
sub ResetSearch()
    CancelSearch()
    CancelSources()
    m.sources = []
    m.sourcesSignature = ""
    m.pendingQuery = ""
    m.lastQuery = ""
    m.searchOrder = []
    m.landed = {}
    m.searchFailed = false
    m.rows = []
    m.subtitle.text = "Speak or type a movie or TV show"
    ClearResults()
end sub

sub ClearResults()
    if m.results <> invalid
        m.results.content = CreateObject("roSGNode", "ContentNode")
        m.results.numRows = 0
    end if
end sub

' The query prompt. Starts empty, so each search is a fresh prompt rather than an
' edit of the last one.
sub ShowSearchDialog()
    if m.top.getScene().dialog <> invalid then return
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    ' Older firmware can still search with the remote's on-screen keyboard.
    ' Dynamic nodes and dictation availability are owned by Roku OS.
    if dialog = invalid then dialog = CreateObject("roSGNode", "KeyboardDialog")
    if dialog = invalid
        m.status.text = "Search keyboard unavailable on this Roku."
        return
    end if
    dialog.title = "Search"
    dialog.id = NextSearchWorkerId("searchDialog")
    if dialog.HasField("keyboardDomain")
        dialog.keyboardDomain = "generic"
        dialog.message = ["Type a title, or hold your remote's microphone button and say it."]
    else
        dialog.message = "Enter a title"
    end if
    ' Starts empty. Each search is a fresh prompt rather than an edit of the last
    ' one, so there is no stale query sitting in the box inviting a re-run of
    ' what was searched before. m.lastQuery is still recorded below and is what
    ' the "no results" message names.
    dialog.text = ""
    dialog.buttons = ["Search", "Cancel"]
    dialog.observeField("buttonSelected", "onSearchChoice")
    dialog.observeField("wasClosed", "onSearchDialogClosed")
    ' Before the dialog is shown, and that ordering is load bearing. The edit
    ' box is built as soon as the node is created, so this is the earliest the
    ' voice setting can land and the dictation UI is not listening yet. It was
    ' an observer firing at registration that got there before; a direct call at
    ' this point in the sequence is the same moment without the extra field.
    ApplySearchKeyboard(dialog)
    m.searchDialog = dialog
    m.top.getScene().dialog = dialog
end sub

' StandardKeyboardDialog exposes its internal VoiceTextEditBox. Configure it
' before showing the dialog; fall back to the legacy editor on older firmware.
' Roku may suppress dictation when no compatible voice remote is paired or the
' account region/language does not support it. Typed entry always remains.
sub ApplySearchKeyboard(dialog as object) as void
    if dialog = invalid then return
    editor = invalid
    if dialog.HasField("textEditBox")
        editor = dialog.textEditBox
    else if dialog.HasField("keyboard") and dialog.keyboard <> invalid
        editor = dialog.keyboard.textEditBox
    end if
    if editor = invalid then return

    ' DynamicKeyboard's documented edit-box default is letter-by-letter
    ' "alphanumeric"; movie titles require full-word "generic" dictation.
    if editor.HasField("voiceEntryType") then editor.voiceEntryType = "generic"
    if editor.HasField("voiceEnabled") then editor.voiceEnabled = true
    ' Caret after the text rather than at 0. A caret parked at 0 makes backspace
    ' and the left arrow no-ops by definition while typing still appends, which
    ' from the outside is indistinguishable from a dead keyboard.
    editor.cursorPosition = Len(dialog.text)
end sub

sub onSearchChoice(event as object)
    dialog = event.GetRoSGNode()
    if dialog <> invalid and m.searchDialog <> invalid
        if dialog.id <> m.searchDialog.id then return
        index = dialog.buttonSelected
        query = dialog.text
        ' StandardDialog's own dismissal, and the one ConfirmExitDialog already
        ' uses: setting close makes the scene drop the node from the dialog slot
        ' by itself. Both values are read above before anything is torn down.
        dialog.close = true
        if index = 0
            RunSearch(query.Trim())
        end if
    end if
end sub

sub onSearchDialogClosed(event as object)
    dialog = event.GetRoSGNode()
    if dialog = invalid or m.searchDialog = invalid then return
    if dialog.id <> m.searchDialog.id then return
    m.searchDialog = invalid
    scene = m.top.getScene()
    if scene.dialog <> invalid and scene.dialog.id = dialog.id then scene.dialog = invalid
    RestoreSearchFocus()
end sub

' Keep a useful focus target while providers load. Focusing an empty RowList
' can fail on-device; the first usable results take focus explicitly later.
sub RestoreSearchFocus()
    if not m.top.screenActive then return
    if m.top.getScene().dialog <> invalid then return
    if m.rows.Count() > 0
        m.results.SetFocus(true)
    else
        m.top.SetFocus(true)
    end if
end sub

function NextSearchWorkerId(prefix as string) as string
    m.workerSequence = m.workerSequence + 1
    return prefix + m.workerSequence.ToStr()
end function

' Kick the query off the render thread against every search-capable catalog
' across the resolved sources. One SearchLoaderTask per add-on runs in parallel,
' each carrying that add-on's catalogs. No rows are premised: the grid stays
' empty until a catalog answers with results, and each row is then inserted in
' the catalog's discovery order.
sub RunSearch(query as string)
    if query = "" then
        m.status.text = "Type something to search."
        return
    end if
    m.subtitle.text = "Results for " + Chr(34) + query + Chr(34)

    ' Sources still resolving (a task is in flight): hold the query until they
    ' land, then run against whatever arrived.
    if m.sources = invalid or m.sources.Count() = 0
        if m.sourcesTask <> invalid
            m.pendingQuery = query
            m.status.text = "Searching…"
            return
        end if
        m.status.text = "No search add-ons installed."
        return
    end if

    candidates = SearchCandidates()

    CancelSearch()
    m.pendingQuery = ""
    m.lastQuery = query

    if candidates.Count() = 0 then
        m.searchOrder = []
        m.landed = {}
        m.searchFailed = false
        m.rows = []
        ClearResults()
        m.status.text = "No search add-ons installed."
        return
    end if

    m.searchOrder = candidates
    m.landed = {}
    m.searchFailed = false
    m.rows = []
    m.searchTasks = {}
    m.status.text = "Searching…"
    ClearResults()

    LaunchSearchTasks()
    RestoreSearchFocus()
end sub

' The ordered list of searchable catalogs across all sources: one entry per
' search-capable catalog, in addon/manifest order. Title is always
' "{Catalog} - {mediaType}"; when two entries would still carry the same title
' (same catalog name, same media type, different add-ons) the add-on's name is
' prefixed so the rows stay distinguishable.
function SearchCandidates() as object
    candidates = []
    if m.stores = invalid then return candidates

    for each source in m.sources
        if source = invalid then continue for
        if source.catalogs = invalid then continue for
        address = source.address
        if address = invalid or address = "" then continue for
        addonName = source.name
        if addonName = invalid then addonName = ""
        for each descriptor in source.catalogs
            if descriptor = invalid then continue for
            if descriptor.type = invalid or descriptor.type = "" then continue for
            if descriptor.id = invalid or descriptor.id = "" then continue for
            caps = m.stores.addons.callFunc("AddonsCatalogCapabilities", descriptor)
            if caps = invalid or not caps.search then continue for
            base = m.stores.addons.callFunc("AddonsCatalogTitle", descriptor, source.name)
            candidates.Push({
                key: address + "|" + descriptor.type + "|" + descriptor.id
                addonKey: address
                addonName: addonName
                addonAddress: address
                rawType: descriptor.type
                catalogId: descriptor.id
                title: base + " - " + TypeSearchLabel(descriptor.type)
            })
        end for
    end for

    titleCounts = {}
    for each c in candidates
        if titleCounts[c.title] = invalid then titleCounts[c.title] = 0
        titleCounts[c.title] = titleCounts[c.title] + 1
    end for
    for each c in candidates
        if titleCounts[c.title] > 1 then c.title = c.addonName + " - " + c.title
    end for

    return candidates
end function

' The media type half of a search row title ("Popular - Movies"). movie/series
' read as "Movies"/"Series"; channel and tv are one family spelled "Tv channel";
' anything else keeps its declared name capitalized.
function TypeSearchLabel(raw as dynamic) as string
    if raw = invalid then return ""
    if raw = "movie" then return "Movies"
    if raw = "series" then return "Series"
    if raw = "channel" or raw = "tv" then return "Tv channel"
    if raw = "" then return ""
    ' UCase is a global function, not an roString method; the chained form threw
    ' &hf4 the first time an add-on declared a custom catalog type.
    return UCase(raw.Left(1)) + raw.Mid(1)
end function

' One SearchLoaderTask per add-on, passing the catalogs that add-on serves.
' Tasks are independent, so their completion order does not matter.
sub LaunchSearchTasks()
    byAddon = {}
    order = []
    for each candidate in m.searchOrder
        addonKey = candidate.addonKey
        if byAddon.DoesExist(addonKey) = false
            byAddon[addonKey] = { address: candidate.addonAddress, cats: [] }
            order.Push(addonKey)
        end if
        byAddon[addonKey].cats.Push({
            key: candidate.key
            type: candidate.rawType
            id: candidate.catalogId
        })
    end for

    for each addonKey in order
        task = AsyncTask_Launch(m.top, "SearchLoaderTask", "onSearchLoaded", {
            addonAddress: byAddon[addonKey].address
            addonKey: addonKey
            catalogs: byAddon[addonKey].cats
            query: m.lastQuery
        }, NextSearchWorkerId("searchLoader"))
        m.searchTasks[addonKey] = task
    end for
end sub

' One add-on's search landed (or failed). The task reports its sections keyed by
' catalog key; a stale result that landed after CancelSearch is dropped by the
' slot guard — the whole map is invalid (cancel), or the slot was cleared
' (already applied). A section's metas are parked in m.landed by key, then the
' row list is rebuilt from scratch so only catalogs that actually returned
' results appear, in discovery order.
sub onSearchLoaded(event as object)
    if m.searchTasks = invalid then return
    task = event.GetRoSGNode()
    if task = invalid then return
    addonKey = task.addonKey
    if addonKey = invalid or addonKey = "" then return
    slot = m.searchTasks[addonKey]
    if slot = invalid then return
    if task.id <> slot.id then return
    result = task.result
    if result = invalid then return
    m.searchTasks[addonKey] = invalid

    AsyncTask_Reap(task, m.top, false)

    if result = invalid or result.sections = invalid or Type(result.sections) <> "roArray"
        m.searchFailed = true
    else
        for each section in result.sections
            if section = invalid or section.key = invalid then continue for
            if Type(section.metas) = "roArray" and section.metas.Count() > 0
                m.landed[section.key] = section.metas
            else if section.error <> invalid and section.error <> ""
                m.searchFailed = true
            end if
        end for
    end if

    RebuildRows()
    UpdateSearchStatus()
end sub

' m.rows = every catalog that landed metas, in the discovery order of
' m.searchOrder. Rows appear only with results, so a catalog with no matches (or
' an add-on that got no usable answer) never occupies a row.
sub RebuildRows()
    prevCount = m.rows.Count()
    rows = []
    for each candidate in m.searchOrder
        metas = SearchUsableMetas(m.landed[candidate.key])
        if metas.Count() > 0
            rows.Push({
                key: candidate.key
                addonAddress: candidate.addonAddress
                title: candidate.title
                rawType: candidate.rawType
                metas: metas
            })
        end if
    end for
    m.rows = rows
    RenderRows()
    if prevCount = 0 and m.rows.Count() > 0
        m.results.jumpToRowItem = [0, 0]
        RestoreSearchFocus()
    end if
end sub

' The rendered indexes and selection indexes must use the same filtered list.
' A malformed provider record cannot be bound to typed ContentNode fields.
function SearchUsableMetas(items as dynamic) as object
    result = []
    if Type(items) <> "roArray" then return result
    for each meta in items
        if Type(meta) <> "roAssociativeArray" then continue for
        if SearchText(meta.id) = "" or SearchText(meta.type) = "" or SearchText(meta.name) = "" then continue for
        clean = {}
        for each key in meta
            clean[key] = meta[key]
        end for
        clean.id = SearchText(meta.id)
        clean.type = SearchText(meta.type)
        clean.name = SearchText(meta.name)
        for each key in ["poster", "posterShape", "description", "background", "logo", "releaseInfo", "imdbRating"]
            if clean[key] <> invalid then clean[key] = SearchText(clean[key])
        end for
        kind = Type(clean.runtime)
        if clean.runtime <> invalid and kind <> "String" and kind <> "roString" and kind <> "Integer" and kind <> "roInt" and kind <> "roInteger" and kind <> "Float" and kind <> "roFloat" and kind <> "Double" and kind <> "roDouble" then clean.Delete("runtime")
        result.Push(clean)
    end for
    return result
end function

function SearchText(value as dynamic) as string
    if Type(value) = "String" or Type(value) = "roString" then return value.Trim()
    return ""
end function

' Rebuild the whole grid from m.rows. Every row carries only landed metas, so
' there is nothing to render while a catalog is still resolving — the status
' line says what is happening.
sub RenderRows()
    content = CreateObject("roSGNode", "ContentNode")
    sizes = []
    for each row in m.rows
        rowNode = content.CreateChild("ContentNode")
        rowNode.title = row.title
        for each meta in row.metas
            entry = rowNode.CreateChild("TileContent")
            name = meta.name
            if name = invalid then name = ""
            entry.title = name
            poster = meta.poster
            if poster <> invalid and poster <> "" then entry.hdPosterUrl = poster
            glyph = ""
            if m.stores <> invalid then glyph = m.stores.library.callFunc("LibraryWatchedGlyph", meta.id, meta.type)
            entry.watchedGlyph = glyph
        end for
        ' Each result catalog sizes its own row to its posterShape (folded from
        ' the metas), so a landscape catalog lands wide rows even among 2:3 ones;
        ' falls back to the content type when no shape ships.
        sizes.Push(SearchCellSize(row.rawType, TilePosterShape(row.metas)))
    end for
    m.results.content = content
    m.results.rowItemSize = sizes
    ' Per-row slot heights so a landscape/square catalog row sits tight instead of
    ' inheriting the 2:3 itemSize height and leaving a phantom gap (see
    ' TileRowHeights).
    m.results.rowHeights = TileRowHeights(sizes)
    m.results.numRows = SearchVisibleRows(m.rows.Count())
end sub

' Preserve poster aspect ratios while fitting two complete rows and controls
' within the TV viewport. PosterTile follows these width/height fields.
function SearchCellSize(metaType as dynamic, posterShape as dynamic) as object
    size = TileCellSize(metaType, posterShape)
    return [Int(size[0] * 0.8), Int(size[1] * 0.8)]
end function

' numRows is the viewport height, not the number of content rows. All results
' remain in content and Roku scrolls them through these two visible slots.
function SearchVisibleRows(count as integer) as integer
    if count < 0 then return 0
    if count > 2 then return 2
    return count
end function

' The status line: "Searching…" while any add-on is still resolving; once all
' settle, clears when results exist, names the failure when every catalog failed,
' or says there were no matches.
sub UpdateSearchStatus()
    if m.searchTasks = invalid then return
    pending = 0
    for each key in m.searchTasks
        if m.searchTasks[key] <> invalid then pending = pending + 1
    end for
    if pending > 0
        m.status.text = "Searching…"
    else if m.rows.Count() > 0
        m.status.text = ""
    else if m.searchFailed
        m.status.text = "Search failed."
    else
        m.status.text = "No results for " + Chr(34) + m.lastQuery + Chr(34) + "."
    end if
end sub

sub CancelSearch()
    if m.searchTasks <> invalid
        for each key in m.searchTasks
            task = m.searchTasks[key]
            if task <> invalid then AsyncTask_Reap(task, m.top, true)
        end for
    end if
    m.searchTasks = invalid
end sub

' A result opens DetailsScreen through the same one-action channel Home uses for
' a catalog tile: full meta + the source add-on's address (from the row).
sub onResultSelected()
    data = m.results.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    row = data[0]
    index = data[1]
    if row < 0 or index < 0 then return
    if row >= m.rows.Count() then return
    target = m.rows[row]
    metas = target.metas
    if index >= metas.Count() then return
    m.top.pushRequest = {
        screen: "detailsScreen"
        params: {
            addonAddress: target.addonAddress
            meta: metas[index]
        }
    }
end sub

' The * (options) button reopens the query prompt, prefilled. Everything else
' falls through to the stack (Back pops, arrows move inside the results list).
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "options"
        ShowSearchDialog()
        return true
    end if
    return false
end function

sub EnsureCurrentSources()
    if m.stores = invalid or CatalogSignature() = m.sourcesSignature then return
    query = m.lastQuery
    ResetSearch()
    if GetInterface(query,"ifString") <> invalid then m.pendingQuery = query
    m.sourcesSignature = CatalogSignature()
    if m.top.visible then EnsureSources()
end sub
