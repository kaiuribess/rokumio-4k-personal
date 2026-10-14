' HomeScreen — the stack bottom: continue watching first, then catalog rows.
'
' The body is a single RowList: Roku owns the whole grid physics — vertical row
' scrolling/clipping (no row is ever stranded past the screen edge), horizontal
' per-row tile scrolling, row labels, focus reporting and non-focused-row
' dimming. Each row item is a PosterTile (see its interface fields). OK on a
' poster publishes one pushRequest; the Scene does the stack work.
'
' Rows are served by the addon stores: a HomeCatalogsTask walks the add-ons off
' the UI thread, fetching every advertisable catalog, and republishes the row
' set after each completion so the grid fills in one row at a time instead of
' blocking startup on the whole catalog set. On top sits a Continue Watching row
' built from the (local) LibraryStore whenever the user has entries — guests
' included, since that state is local. Rows that fail to load are skipped; on
' total failure the grid stays empty so a break in the fetch pipeline is
' unambiguous.
'
' The grid tree is built lazily on first OnEnter, not in init(): init runs during
' CreateScene, before screen.Show(), and nodes created pre-Show can be dropped by
' the renderer. Rows are inserted as they arrive and the grid is assembled
' exactly once; later visits either leave the tree alone (nothing changed) or
' refresh only the Continue Watching row in place (progress was made elsewhere).
' The RowList's own scroll + focus therefore survive every trip away and back.

sub init()
    m.catalog = m.top.FindNode("catalog")
    m.catalog.ObserveField("rowItemSelected", "onRowItemSelected")
    m.rail = m.top.FindNode("rail")
    m.rail.ObserveField("rowItemSelected", "onRailItemSelected")
    m.homeSub = m.top.FindNode("homeSub")
    m.homeHint = ""
    m.catalogStatus = m.top.FindNode("homeCatalogStatus")
    m.workerSequence = 0

    t = Theme()
    m.top.FindNode("homeTitle").color = t.textPrimary
    m.top.FindNode("homeQualityPlate").color = t.accentFaint
    m.top.FindNode("homeQualityLabel").color = t.accentFocus
    m.homeSub.color = t.textSecondary
    m.catalogStatus.color = t.accent
    m.top.FindNode("homeHelp").color = t.textPrimary
    m.top.FindNode("railBg").color = t.railTint
    m.catalog.rowLabelOffset = [[0,10]]
    m.catalog.focusBitmapBlendColor = t.accentFocus

    m.catalogRowsBuilt = false
    m.catalogRows = []
    m.gridRows = []
    m.gridBuilt = false
    m.cwSignature = ""
    m.catalogSignature = ""
    m.railBuilt = false
    m.homeVisited = false
    m.returnFocus = "rail"
end sub

' Kick off the catalog walk. The walking happens off the UI thread in a
' HomeCatalogsTask (a hung add-on then costs the worker, not startup); it
' republishes the row set after every completed catalog, and onCatalogState
' slots each new row into the grid immediately. Only the plain addon descriptors
' cross the thread boundary. A no-op once started or finished.
'
' The walk records which add-on set it derived from (see CatalogSignature), which
' is the only way anything downstream can later tell that Home's rows have been
' overtaken. It records the set BEFORE branching on the empty case on purpose: a
' walk that latched on an empty registry is exactly the state that must still be
' recognised as stale once add-ons arrive, and a signature left at "" would make
' that indistinguishable from a correct empty grid.
sub StartCatalogLoad()
    if m.catalogRowsBuilt or m.catalogTask <> invalid then return
    if m.stores = invalid then
        m.catalogRowsBuilt = true
        return
    end if
    addons = []
    for each addon in m.stores.addons.callFunc("AddonsGetAll")
        addons.Push({ address: addon.address, catalogs: addon.catalogs, name: addon.name })
    end for
    m.catalogSignature = CatalogSignature()
    if addons.Count() = 0 then
        m.catalogRowsBuilt = true
        m.catalogStatus.text = "No catalog add-ons installed. Open Add-ons to connect one."
        return
    end if
    m.catalogStatus.text = "Updating movies and shows…"
    task = AsyncTask_Launch(m.top, "HomeCatalogsTask", "onCatalogState", { addons: addons }, NextHomeWorkerId("homeCatalog"))
    m.catalogTask = task
end sub

' The add-on set Home's catalog rows were derived from, as a comparable string.
' Mirrors ContinueWatchingSignature deliberately: derive from live store state,
' sort so ordering cannot make two equal sets look different, join. No network
' and no catalog walk — this is a set comparison, not a re-derivation, so it is
' cheap enough to call on every entry and after every sync.
function CatalogSignature() as string
    if m.stores = invalid then return ""
    addons = m.stores.addons.callFunc("AddonsGetAll")
    if addons = invalid then return ""
    parts = []
    for each addon in addons
        if addon.address <> invalid then parts.Push(addon.address)
    end for
    parts.Sort("i")
    return parts.Join(";")
end function

' Re-derive the grid if the add-on set has moved under it. Cheap when fresh, and
' it is the ONLY thing that can notice Home is stale.
'
' Why this exists. The add-on sync used to gate its rebuild on "at least one
' add-on was newly installed". That predicate is false on every run after the
' first: the account's add-ons are already in the registry, so none of them is
' "added", so Home was never told to re-derive. Home kept the catalog set it
' walked at launch — in a stremio session that is often just the built-in seeds,
' because a session swap replaces what AddonsGetAll returns wholesale — while the
' Add-ons screen, which reads the registry live, listed the account's add-ons
' correctly. The two views disagreed permanently, Settings-and-back changed
' nothing, and no fault ever appeared, because nothing had failed. The sync
' succeeded and simply told nobody.
'
' Comparing the add-on SET rather than a count also covers the two cases no
' count can see: a session swap (the set changes without anything being
' installed) and a walk that latched on an empty registry.
sub EnsureCurrentRows()
    if m.stores = invalid then return
    if m.catalogSignature = CatalogSignature() then return
    RebuildRows()
end sub

' Rows arrive as full result snapshots ({ rows, done }); apply only what is not
' on the grid yet. The task assigns each row a stable index, so the slot is
' cwOffset + index whether the Continue Watching row is present or not.
sub onCatalogState(event as object)
    if m.catalogRowsBuilt then return
    if m.catalogTask = invalid then return
    sender = event.GetRoSGNode()
    if sender = invalid or sender.id <> m.catalogTask.id then return
    state = event.GetData()
    if state = invalid or state.rows = invalid or Type(state.rows) <> "roArray" then return
    for each row in state.rows
        if row.index >= m.catalogRows.Count() then ApplyCatalogRow(row)
    end for
    if state.done = true then FinishCatalogLoad()
end sub

' Insert one streamed catalog row at its deterministic slot. All rows arrive in
' ascending index order, so the grid stays in task order even though each
' snapshot is a full copy.
sub ApplyCatalogRow(row as object)
    descriptor = {
        addonAddress: row.addonAddress
        title: row.title
        metaType: row.metaType
        posterShape: TilePosterShape(row.metas)
        metas: row.metas
    }
    cwOffset = 0
    if m.gridRows.Count() > 0 and m.gridRows[0].source = "library" then cwOffset = 1
    slot = cwOffset + row.index
    node = MakeRowNode(descriptor, invalid)
    if m.catalog.content <> invalid and m.catalog.content.getChildCount() > slot
        m.catalog.content.InsertChild(node, slot)
    else
        m.catalog.content.AppendChild(node)
    end if
    m.catalogRows.Push(descriptor)
    m.gridRows.Push(descriptor)
    m.catalog.numRows = HomeVisibleRows(m.gridRows.Count())
    ApplyCatalogSizes()
    ResyncRowLabels()
end sub

' Rewrite row titles so duplicated catalog names carry their type suffix; only
' interesting once a later row turns a previously-unique name into a duplicate.
' A malformed (invalid/blank) title is coerced to "" so the histogram lookup
' cannot throw — the grid degrades to a blank label instead of crashing.
sub ResyncRowLabels()
    if m.catalog.content = invalid then return
    counts = DuplicateCounts()
    for r = 0 to m.gridRows.Count() - 1
        label = m.gridRows[r].title
        if label = invalid then label = ""
        if counts[label] > 1 then label = label + " " + TypeLabel(m.gridRows[r].metaType)
        node = m.catalog.content.GetChild(r)
        if node <> invalid and node.title <> label then node.title = label
    end for
end sub

' The task finished (the walk completed or errored out): the rows already
' applied are the final row set. Tear the task node down.
sub FinishCatalogLoad()
    m.catalogRowsBuilt = true
    if m.catalogRows.Count() = 0
        m.catalogStatus.text = "Catalog unavailable. Play/Pause to retry, or use Search."
    else
        m.catalogStatus.text = ""
    end if
    if m.catalogTask <> invalid
        task = m.catalogTask
        m.catalogTask = invalid
        AsyncTask_Reap(task, m.top, false)
    end if
end sub

' Assemble the visible grid: Continue Watching (when the local library has
' entries) first, then the catalog rows as they stream in via onCatalogState.
' On first entry the content tree is created here; later visits refresh only the
' live Continue Watching row in place (see RefreshContinueWatching) so the rest
' of the grid keeps the RowList's own scroll + focus.
sub BuildRows()
    m.gridRows = []
    cw = LibraryRow()
    if cw <> invalid then m.gridRows.Push(cw)
    for each row in m.catalogRows
        m.gridRows.Push(row)
    end for

    counts = DuplicateCounts()

    content = CreateObject("roSGNode", "ContentNode")
    for r = 0 to m.gridRows.Count() - 1
        content.AppendChild(MakeRowNode(m.gridRows[r], counts))
    end for
    m.catalog.content = content
    m.catalog.numRows = HomeVisibleRows(m.gridRows.Count())
    ApplyCatalogSizes()
end sub

' Rebuild the grid from the current add-on set — called by the Scene after a
' deep-link import registered new add-ons (see MainScene FinishImport). Mirrors
' a fresh launch: drop any in-flight catalog walk first so no stale result can
' apply, clear the accumulated descriptors, rebuild the content from Continue
' Watching only, then restart the walk so imported catalogs appear without an
' app relaunch. Safe to run while Home is under a dialog: the walk re-fills the
' rows one at a time behind it, and the existing guards (gridBuilt /
' catalogRowsBuilt / catalogTask) keep later OnEnter visits consistent.
function RebuildRows() as void
    if m.catalogTask <> invalid
        ' STOP, and not a bare RemoveChild. The walk is a Task on its own thread,
        ' so removing a running Task node frees the node WITHOUT killing the
        ' worker — the trap AsyncTask.bs opens by spelling out. This walk can
        ' still be fetching when a deep-link import calls RebuildRows, so
        ' unobserved it runs to completion and lands its descriptors through
        ' onCatalogState anyway: two walks interleaving rows into a grid that has
        ' already been thrown away and rebuilt, with StartCatalogLoad below
        ' having launched a third. Reap with doStop = true, as AsyncTask.bs
        ' prescribes for a possibly-still-running task, and let the helper do the
        ' unobserving too. (FinishCatalogLoad reaps with false on purpose — by
        ' then that task has already reported in.)
        AsyncTask_Reap(m.catalogTask, m.top, true)
        m.catalogTask = invalid
    end if
    m.catalogRows = []
    m.catalogRowsBuilt = false
    m.gridRows = []
    m.gridBuilt = false
    BuildRows()
    StartCatalogLoad()
end function

' Rebuild the title histogram across the current grid rows; used to decide the
' duplicated-name type suffix. An associative array cannot be keyed by invalid,
' so malformed titles are coerced to "" before the lookup (a row without a
' usable title then just groups with the other blank-label rows).
function DuplicateCounts() as object
    counts = {}
    for each row in m.gridRows
        title = row.title
        if title = invalid then title = ""
        count = counts[title]
        if count = invalid then count = 0
        counts[title] = count + 1
    end for
    return counts
end function

' Build the ContentNode for one grid row: a titled group of poster children.
' counts carries the merged name histogram so duplicated catalog labels get
' their type suffix (it is invalid for rows streamed in before their duplicate
' arrives — ResyncRowLabels backfills the suffix then, and for a freshly
' inserted Continue Watching row the label is unique anyway).
function MakeRowNode(row as object, counts = invalid as object) as object
    node = CreateObject("roSGNode", "ContentNode")
    label = row.title
    if label = invalid then label = ""
    if counts <> invalid and counts[label] > 1 then label = label + " " + TypeLabel(row.metaType)
    node.title = label
    for each meta in row.metas
        glyph = meta.watchedGlyph
        if glyph = invalid and m.stores <> invalid then glyph = m.stores.library.callFunc("LibraryWatchedGlyph", meta.id, meta.type)
        PaintTileFields(node.CreateChild("TileContent"), meta, glyph)
    end for
    return node
end function

' The poster cell for one grid row. Channel-style add-ons (Stremio content types
' "channel"/"tv") ship 1:1 posters, so those rows get square cells; everything
' else keeps the 2:3 poster slab. A catalog-supplied posterShape (folded to the
' row's majority shape once when the row lands) overrides the type fallback, so
' a 16:9 catalog gets a wide row instead of letterboxed 2:3 cells. PosterTile
' sizes itself from the cell it is handed, so this drives both the slot and the
' tile shape.
function RowCellSize(row as object) as object
    mt = invalid
    ps = ""
    if row <> invalid then
        mt = row.metaType
        if row.posterShape <> invalid then ps = row.posterShape
    end if
    size = TileCellSize(mt, ps)
    return [Int(size[0] * 0.8), Int(size[1] * 0.8)]
end function

' Per-row item sizes, one vector2d per grid row, in grid order. Rebuilt with the
' size of m.gridRows whenever the grid changes (rows stream in one at a time and
' the Continue Watching row slots in front).
function RowSizes() as object
    sizes = []
    for each row in m.gridRows
        sizes.Push(RowCellSize(row))
    end for
    return sizes
end function

' Set both the per-row tile sizes and the matching per-row heights. RowList reads
' a row's slot height from itemSize.y (one value for every row) unless rowHeights
' overrides it per row, so a landscape/square row taller-than-its-tile case left
' phantom space under every non-2:3 row. Mirroring the tile heights fixes the gap.
sub ApplyCatalogSizes()
    sizes = RowSizes()
    m.catalog.rowItemSize = sizes
    m.catalog.rowHeights = TileRowHeights(sizes)
end sub

' Paint the shared poster-tile fields — title, hdPosterUrl, progress-bar fraction
' and watched glyph — onto an item ContentNode. Overlay fields are always
' written a concrete value (""/0 when there is none): they're typed fields on
' TileContent, and on a recycled node an "unset" is not reliably cleared by
' assigning invalid, so a tile that previously held a bar/badge would keep it
' into a cell that has none. fallbackGlyph is the store-computed glyph when the
' meta did not carry one.
sub PaintTileFields(item as object, meta as object, fallbackGlyph as dynamic)
    name = meta.name
    if name = invalid then name = ""
    item.title = name
    poster = meta.poster
    if poster = invalid then poster = ""
    item.hdPosterUrl = poster
    item.progress = 0
    if meta.progress <> invalid and meta.progress > 0 then item.progress = meta.progress
    glyph = meta.watchedGlyph
    if glyph = invalid then glyph = fallbackGlyph
    if glyph = invalid then glyph = ""
    item.watchedGlyph = glyph
end sub

' The top row when the user has watched something: one tile per local
' continue-watching entry, carrying its resume hint so Details can reopen on
' the right spot. Items are synthesized catalog metas. Each tile also carries
' the progress fraction (position/duration) and the coarse watched glyph, so a
' finished watch paints a bar/badge on the tile without reopening Details.
function LibraryRow() as dynamic
    if m.stores = invalid then return invalid
    entries = m.stores.library.callFunc("LibraryContinueWatching")
    if entries = invalid then return invalid
    if entries.Count() = 0 then return invalid
    metas = []
    for each entry in entries
        metas.Push({
            id: entry.metaId
            type: entry.metaType
            name: entry.name
            poster: entry.poster
            posterShape: entry.posterShape
            videoId: entry.videoId
            season: entry.season
            episode: entry.episode
            position: entry.position
            progress: m.stores.library.callFunc("LibraryProgressFraction", entry.metaId)
            watchedGlyph: m.stores.library.callFunc("LibraryWatchedGlyph", entry.metaId, entry.metaType)
        })
    end for
    return { source: "library", title: "Continue Watching", metaType: "", posterShape: TilePosterShape(metas), metas: metas }
end function

function ContinueWatchingSignature() as string
    if m.stores = invalid then return ""
    entries = m.stores.library.callFunc("LibraryContinueWatching")
    if entries = invalid or entries.Count() = 0 then return ""
    parts = []
    for each entry in entries
        position = entry.position
        if position = invalid then position = 0
        duration = entry.duration
        if duration = invalid then duration = 0
        glyph = m.stores.library.callFunc("LibraryWatchedGlyph", entry.metaId, entry.metaType)
        parts.Push(entry.metaId + "|" + entry.videoId + "|" + entry.season.toStr() + "|" + entry.episode.toStr() + "|" + position.toStr() + "|" + duration.toStr() + "|" + glyph)
    end for
    parts.Sort("i")
    return parts.Join(";")
end function

' Live-update the Continue Watching row after progress was made elsewhere,
' without touching the rest of the grid. The catalog rows' nodes stay bit-for-bit
' intact, so the RowList's own scroll + focus survive the visit; only the top
' row's posters/titles change. A row appearing (first watch) or disappearing
' (history cleared) is handled by inserting/removing precisely that one row —
' which may clamp focus to the top, an acceptable reset confined to those rare
' transitions.
sub RefreshContinueWatching()
    if m.catalog.content = invalid then return
    content = m.catalog.content
    haveCw = m.gridRows.Count() > 0 and m.gridRows[0].source = "library"
    live = LibraryRow()
    if live <> invalid
        if haveCw
            SyncContinueWatchingRow(content.GetChild(0), live.metas)
            m.gridRows[0] = live
        else
            content.InsertChild(MakeRowNode(live, invalid), 0)
            m.gridRows.Unshift(live)
            m.catalog.numRows = HomeVisibleRows(m.gridRows.Count())
            ApplyCatalogSizes()
        end if
    else if haveCw
        content.RemoveChildIndex(0)
        m.gridRows.Delete(0)
        m.catalog.numRows = HomeVisibleRows(m.gridRows.Count())
        ApplyCatalogSizes()
    end if
end sub

' Refresh a row node's poster children to match a fresh meta list, reusing the
' existing child nodes by index so the RowList sees no structural change in the
' common case: no flicker, and focus holds even when entries reorder (a watched
' title rises to the front). Surplus children are trimmed from the tail.
sub SyncContinueWatchingRow(node as object, metas as object)
    existing = node.getChildCount()
    for c = 0 to metas.Count() - 1
        item = invalid
        if c < existing
            item = node.GetChild(c)
        else
            item = node.CreateChild("TileContent")
        end if
        PaintTileFields(item, metas[c], metas[c].watchedGlyph)
    end for
    while node.getChildCount() > metas.Count()
        node.RemoveChildIndex(node.getChildCount() - 1)
    end while
end sub

' Where the meta for a library-sourced tile comes from. The library records no
' addon origin, so the Cinemeta built-in (the meta authority) is the default.
function MetaAddress() as string
    if m.stores = invalid then return ""
    addon = m.stores.addons.callFunc("AddonsGet", "com.linvo.cinemeta")
    if addon = invalid then return ""
    return addon.address
end function

' Row-label suffix for duplicated catalog names.
function TypeLabel(metaType as string) as string
    if metaType = "movie" then return "Movies"
    if metaType = "series" then return "Series"
    return metaType
end function

' numRows controls the visible viewport. The complete catalog is retained in
' content, even when installed add-ons produce many more rows than fit on TV.
function HomeVisibleRows(count as integer) as integer
    if count < 0 then return 0
    if count > 2 then return 2
    return count
end function

function OnEnter(params as object) as void
    if not m.railBuilt then BuildRail()
    StartCatalogLoad()
    sig = ContinueWatchingSignature()
    if not m.gridBuilt
        BuildRows()
        m.gridBuilt = true
    else if sig <> m.cwSignature
        RefreshContinueWatching()
    end if
    m.cwSignature = sig
    ' After the Continue Watching reconciliation, and deliberately last: it is the
    ' catalog set that a sync can invalidate while the grid is already "built", and
    ' StartCatalogLoad above is a no-op once the walk has latched. Running it here
    ' as well means leaving for another screen and coming back repairs a stale
    ' grid, instead of the staleness being permanent until a relaunch.
    EnsureCurrentRows()
    if not m.homeVisited
        m.returnFocus = "rail"
        m.rail.SetFocus(true)
        m.homeVisited = true
    else if m.returnFocus = "rail" or m.gridRows.Count() = 0
        ' Keep the selected menu item on return. An empty catalog cannot take
        ' meaningful focus, so the remote always has a usable navigation target.
        m.returnFocus = "rail"
        m.rail.SetFocus(true)
    else
        m.catalog.SetFocus(true)
    end if
end function

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

' Remember where the grid sits when another screen takes focus. ScreenStack
' calls BlurFocus on every push; nothing needs saving because the content tree
' is never replaced after first entry, so the RowList keeps its own scroll +
' focus across every trip away and back. A Continue-Watching open still in
' flight is cancelled: the user moved on, so its Details push must not land on
' the next screen.
sub BlurFocus()
    if m.rail.IsInFocusChain()
        m.returnFocus = "rail"
    else if m.catalog.IsInFocusChain()
        m.returnFocus = "catalog"
    end if
    CancelOpen()
end sub

' The left rail: a fixed one-column icon menu. Built once (nodes created in init
' can be dropped pre-Show, so it happens on first OnEnter like the catalog). The
' last row is a modal (the support dialog), so its entry carries dialog = true
' and onRailItemSelected routes it through the pushRequest contract the same
' way; MainScene picks it up and shows the native dialog instead of pushing a
' stack screen.
sub BuildRail()
    entries = [
        { glyph: "pkg:/images/search.png", label: "Search", screen: "searchScreen" }
        { glyph: "pkg:/images/discover.png", label: "Browse", screen: "discoverScreen" }
        { glyph: "pkg:/images/library.png", label: "My list", screen: "libraryScreen" }
        { glyph: "pkg:/images/puzzle.png", label: "Add-ons", screen: "addonsScreen" }
        { glyph: "pkg:/images/settings.png", label: "Settings", screen: "settingsScreen" }
        { glyph: "pkg:/images/support.png", label: "About", screen: "aboutScreen" }
    ]
    m.railEntries = entries
    content = CreateObject("roSGNode", "ContentNode")
    for each entry in entries
        row = content.CreateChild("ContentNode")
        item = row.CreateChild("ContentNode")
        item.title = entry.glyph
        item.description = entry.label
    end for
    m.rail.content = content
    m.rail.numRows = entries.Count()
    m.railBuilt = true
end sub

' OK on a rail icon: an action request the Scene routes. Stack screens publish
' screen + params; the support modal adds dialog = true, which must survive into
' the pushRequest or the Scene would push the dialog node as a bogus stack
' screen and hide Home instead of showing the native dialog over it.
sub onRailItemSelected()
    data = m.rail.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    row = data[0]
    if row < 0 or m.railEntries = invalid or row >= m.railEntries.Count() then return
    entry = m.railEntries[row]
    request = {
        screen: entry.screen
        params: {}
    }
    if entry.dialog = true then request.dialog = true
    m.top.pushRequest = request
end sub

' Cross-focus between the rail and the catalog grid. Left from the grid enters
' the rail; Right from the rail enters the grid. Whether a RowList at its left
' edge lets Left bubble here is device-dependent — if the grid swallows it, the
' fallback is starting Home focus on the rail. Verify on-device.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "play"
        CancelOpen()
        m.returnFocus = "rail"
        m.rail.SetFocus(true)
        RebuildRows()
        return true
    else if key = "right" and m.rail.HasFocus()
        if m.gridRows.Count() = 0 then return true
        m.returnFocus = "catalog"
        m.catalog.SetFocus(true)
        return true
    else if key = "left" and m.catalog.HasFocus()
        m.returnFocus = "rail"
        m.rail.SetFocus(true)
        return true
    else if key = "options"
        if m.catalog.HasFocus()
            m.returnFocus = "rail"
            m.rail.SetFocus(true)
            return true
        else if m.rail.HasFocus()
            if m.gridRows.Count() = 0 then return true
            m.returnFocus = "catalog"
            m.catalog.SetFocus(true)
            return true
        end if
    end if
    return false
end function

' rowItemSelected is a field observer, so this receives the roSGNodeEvent. Its
' data is a [row, itemIndex] pair; the selected name comes from the row's own
' data (the tiles only know their parsed label). A catalog tile opens Details
' for its meta. A Continue-Watching tile adds the resume hint and, like any
' other tile, needs its full meta from the Cinemeta built-in by id (the local
' record stores only what the Home row shows — id, name, poster, resume) so
' Details renders the same full hero as a catalog-opened title; that fetch now
' runs off the UI thread (OpenContinueWatching) so the grid stays interactive
' while it answers, and on failure the slim record falls back so the row still
' opens.
sub onRowItemSelected(event as object)
    data = event.GetData()
    if data = invalid or data.Count() < 2 then return
    row = data[0]
    index = data[1]
    if row < 0 or index < 0 or m.stores = invalid then return
    if row >= m.gridRows.Count() then return
    metas = m.gridRows[row].metas
    if index >= metas.Count() then return

    item = metas[index]
    if m.gridRows[row].source = "library"
        OpenContinueWatching(item)
    else
        m.top.pushRequest = {
            screen: "detailsScreen"
            params: {
                addonAddress: m.gridRows[row].addonAddress
                meta: item
            }
        }
    end if
end sub

' Begin opening a Continue-Watching tile. The full meta is fetched off the UI
' thread so Home stays interactive (Back, rail and other tiles keep working);
' the hint line shows "Loading…" meanwhile. A newer tile press or any
' navigation away cancels the pending open (CancelOpen); when the meta lands
' Details is pushed with the full hero, or the slim record on failure.
sub OpenContinueWatching(item as object)
    address = MetaAddress()
    CancelOpen()
    m.pendingOpen = {
        address: address
        meta: {
            id: item.id
            type: item.type
            name: item.name
            poster: item.poster
        }
        resume: {
            videoId: item.videoId
            season: item.season
            episode: item.episode
            position: item.position
        }
    }
    ShowHomeBusy(true)

    task = AsyncTask_Launch(m.top, "MetaLoaderTask", "onContinueWatchingLoaded", {
        addonAddress: address
        metaType: item.type
        metaId: item.id
    }, NextHomeWorkerId("continueWatchingLoader"))
    m.openTask = task
end sub

' Stop a pending Continue-Watching open: tear down any in-flight task, clear the
' pending context and restore the hint. Called on blur (navigating away cancels
' the open) and when another tile supersedes it. STOP is the real cancel — merely
' removing a running Task node does not kill its worker thread (see MainScene) —
' and dropping the observer means its result can never land afterwards.
sub CancelOpen()
    if m.openTask <> invalid
        task = m.openTask
        m.openTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
    m.pendingOpen = invalid
    ShowHomeBusy(false)
end sub

' The full meta arrived (or failed). CancelOpen dropped any superseded task's
' result before it could fire, so the pending context here is still the one that
' started this task. Push Details with the full meta, or the slim record on
' failure so the row still opens.
sub onContinueWatchingLoaded(event as object)
    if m.openTask = invalid then return
    sender = event.GetRoSGNode()
    if sender = invalid or sender.id <> m.openTask.id then return
    if sender.result = invalid then return
    task = m.openTask
    m.openTask = invalid
    result = task.result
    AsyncTask_Reap(task, m.top, false)

    pending = m.pendingOpen
    m.pendingOpen = invalid
    ShowHomeBusy(false)
    if pending = invalid then return

    meta = pending.meta
    if result <> invalid and result.ok and result.meta <> invalid then meta = result.meta
    m.top.pushRequest = {
        screen: "detailsScreen"
        params: {
            addonAddress: pending.address
            meta: meta
            resume: pending.resume
        }
    }
end sub

function NextHomeWorkerId(prefix as string) as string
    if m.workerSequence = invalid then m.workerSequence = 0
    m.workerSequence = m.workerSequence + 1
    return prefix + m.workerSequence.ToStr()
end function

' A brief "Loading…" on the hint line while the Continue-Watching meta is
' fetched; the original hint text comes back when the open resolves or cancels.
sub ShowHomeBusy(show as boolean)
    if m.homeSub = invalid then return
    if show
        if m.homeSub.text <> "Loading…"
            m.homeHint = m.homeSub.text
            m.homeSub.text = "Loading…"
        end if
    else
        if m.homeHint <> invalid and m.homeHint <> "" then m.homeSub.text = m.homeHint
        m.homeHint = ""
    end if
end sub
