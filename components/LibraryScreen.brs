' LibraryScreen — the saved library for the current session. Two chips drive the
' grid: a content-type filter (All/Movies/Series) and a sort order (Recently
' added/A-Z/Z-A/Watched). OK on a chip opens a dropdown menu of that chip's
' options — Up/Down move, OK picks, Back dismisses without changing anything —
' so a wrong pick is an instant undo, never a full cycle. The layout is
' DiscoverScreen's: chips + dropdown above a poster grid, but everything is
' served straight from LibraryStore, no tasks, nothing to load.
'
' The grid is re-sliced whenever a filter or sort changes and on every
' OnEnter/RefreshRows, so a save made on another screen (or a background library
' sync landing while this screen is top) shows up on the next build. A filter
' change keeps the focus on the chips (close the menu, pick a new one); with a
' non-empty view the entry re-focuses the results so OK opens Details like any
' other tile.

sub init()
    m.status = m.top.FindNode("libraryStatus")
    m.header = m.top.FindNode("libraryHeader")
    m.filterBar = m.top.FindNode("filterBar")
    m.grid = m.top.FindNode("libraryGrid")

    t = Theme()
    m.top.FindNode("libraryTitle").color = t.accent
    m.top.FindNode("librarySub").color = t.textSecondary
    m.status.color = t.accent
    m.header.color = t.textSecondary
    m.grid.focusBitmapBlendColor = t.accent

    m.filterBar.ObserveField("chipActivated", "onChipActivated")
    m.filterBar.ObserveField("optionPicked", "onOptionPicked")
    m.grid.ObserveField("rowItemSelected", "onResultSelected")

    m.chunk = 5
    m.typeFilter = "all"
    m.sort = "recent"
    m.items = []
    m.cinemetaAddress = ""
end sub

function OnEnter(params as object) as void
    if m.stores <> invalid
        addon = m.stores.addons.callFunc("AddonsGet", "com.linvo.cinemeta")
        if addon <> invalid then m.cinemetaAddress = addon.address
    end if

    if m.filterBar.callFunc("IsMenuOpen") then m.filterBar.callFunc("HideMenu")

    ' Re-slice every entry (like Addons/Settings): a save toggle on a Details
    ' screen — or a background sync landing while this screen is under another
    ' one — can change the saved set while we were away.
    SetChips()
    BuildRows()
    if m.items.Count() > 0
        m.grid.SetFocus(true)
    else
        m.filterBar.callFunc("FocusChips")
    end if
end function

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

' The Scene's poke when a background library sync lands while this screen is
' top (the relaunched-stremio-session case). Same rebuild as entry — idempotent;
' the grid content is replaced so the freshly synced saved set shows up.
' Leaving the focus where it is keeps an in-flight re-slice from stealing
' navigation.
function RefreshRows() as void
    BuildRows()
end function

' --- chips ------------------------------------------------------------------

' --- filter chips (data) ----------------------------------------------------

' The chip row itself lives in FilterBar; the screen owns the values
' (m.typeFilter/m.sort) and their labels. "Type · All"-style labels make each
' chip's role readable. Rebuilt on every pick so the label always reflects the
' active value.
sub SetChips()
    entries = [
        { raw: m.typeFilter, label: "Type · " + TypeLabel(m.typeFilter) }
        { raw: m.sort, label: "Sort · " + SortLabel(m.sort) }
    ]
    m.filterBar.callFunc("SetChips", entries)
end sub

function TypeLabel(typeFilter as string) as string
    if typeFilter = "movie" then return "Movies"
    if typeFilter = "series" then return "Series"
    if typeFilter = "channel" then return "Channels"
    return "All"
end function

function SortLabel(sort as string) as string
    if sort = "az" then return "A-Z"
    if sort = "za" then return "Z-A"
    if sort = "watched" then return "Watched"
    return "Recently added"
end function

' The chip OK'd in the FilterBar: hand it that chip's options and the index of
' the current value, and the component opens the dropdown pre-scrolled there —
' whatever is focused is the value that OK will commit, Back leaves everything
' untouched.
sub onChipActivated()
    chip = m.filterBar.chipActivated
    if chip < 0 then return
    options = OptionsFor(chip)
    if options.Count() = 0 then return
    m.filterBar.callFunc("ShowMenu", options, CurrentOptionIndex(chip))
end sub

function OptionsFor(chip as integer) as object
    options = []
    if chip = 0
        options = [
            { raw: "all", label: "All" }
            { raw: "movie", label: "Movies" }
            { raw: "series", label: "Series" }
            { raw: "channel", label: "Channels" }
        ]
    else if chip = 1
        options = [
            { raw: "recent", label: "Recently added" }
            { raw: "az", label: "A-Z" }
            { raw: "za", label: "Z-A" }
            { raw: "watched", label: "Watched" }
        ]
    end if
    return options
end function

function CurrentOptionIndex(chip as integer) as integer
    options = OptionsFor(chip)
    for i = 0 to options.Count() - 1
        if chip = 0 and options[i].raw = m.typeFilter then return i
        if chip = 1 and options[i].raw = m.sort then return i
    end for
    return 0
end function

' An option OK'd in the FilterBar's dropdown, then re-slices the grid. The raw
' value and the commit effect are the screen's; the component reports which chip
' and which row were picked. Re-picking the current value just closes the menu.
' A fresh slice (filter or sort) always rebuilds from the store, so the new
' ordering cannot be stale.
sub onOptionPicked()
    pick = m.filterBar.optionPicked
    if pick = invalid or pick.chip = invalid or pick.index = invalid then return
    chip = pick.chip
    options = OptionsFor(chip)
    index = pick.index
    if index < 0 or index >= options.Count() then return
    option = options[index]

    if chip = 0
        if option.raw = m.typeFilter then m.filterBar.callFunc("HideMenu") : return
        m.typeFilter = option.raw
    else if chip = 1
        if option.raw = m.sort then m.filterBar.callFunc("HideMenu") : return
        m.sort = option.raw
    end if

    m.filterBar.callFunc("HideMenu")
    SetChips()
    BuildRows()
end sub

' --- grid -------------------------------------------------------------------

' Re-slice the saved library through LibraryStore with the current type filter
' and sort, then lay each item out as a poster row of m.chunk tiles. The grid is
' rebuilt on entry, on RefreshRows, and on every filter/sort pick; the selection
' always reflects the active filter. An empty view shows the hint on the status
' line and entry parks focus on the chips (the grid has nothing to focus; the
' hint explains why and how to fix it).
sub BuildRows()
    if m.stores = invalid then
        m.items = []
    else
        m.items = m.stores.library.callFunc("LibraryLibraryView", m.typeFilter, m.sort)
    end if

    content = CreateObject("roSGNode", "ContentNode")
    sizes = []
    for r = 0 to (m.items.Count() - 1) / m.chunk
        row = content.CreateChild("ContentNode")
        for c = 0 to m.chunk - 1
            flat = r * m.chunk + c
            if flat >= m.items.Count() then exit for
            item = m.items[flat]
            tile = row.CreateChild("TileContent")
            name = item.name
            if name = invalid then name = ""
            tile.title = name
            poster = item.poster
            if poster <> invalid and poster <> "" then tile.hdPosterUrl = poster
            if item.metaType <> invalid and LCase(item.metaType) = "channel" then tile.watchedGlyph = ""
            TileWatchFields(tile, item.metaId, item.metaType)
        end for
        ' The library is a flat poster wall: one cell size for the whole grid from
        ' the type filter (channel -> 1:1, everything else -> 2:3), so a mixed set
        ' never goes 16:9 mid-wall and breaks the grid.
        sizes.Push(TileCellSize(m.typeFilter))
    end for
    m.grid.content = content
    m.grid.rowItemSize = sizes
    ' Per-row slot heights (see TileRowHeights): the library grid is uniform today,
    ' but this keeps the row gap honest if a filter ever mixes tile heights.
    m.grid.rowHeights = TileRowHeights(sizes)
    if m.items.Count() > 0
        ' A 405px poster row fits below the filters; content owns the full
        ' library and the native list scrolls subsequent rows into this window.
        m.grid.numRows = 1
    else
        m.grid.numRows = 0
    end if

    m.header.text = LibraryLabel()
    if m.items.Count() = 0
        if m.typeFilter = "channel"
            m.status.text = "Your library is empty. Add channels from a title's details screen."
        else
            m.status.text = "Your library is empty. Add movies and series from a title's details screen."
        end if
    else
        m.status.text = ""
    end if
end sub

' Paint the watched overlays on one saved-library tile: the continue-watching
' bar from ProgressFraction, and the coarse glyph by WatchedGlyph (eye for a
' finished movie/series, clock for an in-progress one).
sub TileWatchFields(tile as object, metaId as dynamic, metaType as dynamic)
    if m.stores = invalid then return
    fraction = m.stores.library.callFunc("LibraryProgressFraction", metaId)
    tile.progress = 0
    if fraction <> invalid then tile.progress = fraction
    glyph = m.stores.library.callFunc("LibraryWatchedGlyph", metaId, metaType)
    tile.watchedGlyph = glyph
end sub

' The human summary of the current view, e.g. "All · Recently added".
function LibraryLabel() as string
    return TypeLabel(m.typeFilter) + " · " + SortLabel(m.sort)
end function

' --- selection --------------------------------------------------------------

' A result opens DetailsScreen through the same one-action channel Home, Search
' and Discover use: the slim saved record + the Cinemeta address. The full hero
' is top-filled by DetailsScreen.MaybeRefreshMeta exactly as a Search/Discover
' slim tile would be, so a record missing its original addon still opens.
sub onResultSelected()
    data = m.grid.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    flat = data[0] * m.chunk + data[1]
    if flat < 0 or flat >= m.items.Count() then return
    item = m.items[flat]
    m.top.pushRequest = {
        screen: "detailsScreen"
        params: {
            addonAddress: m.cinemetaAddress
            meta: {
                id: item.metaId
                type: item.metaType
                name: item.name
                poster: item.poster
            }
        }
    }
end sub

' Where the meta for a saved tile comes from. The library records no addon
' origin, so the Cinemeta built-in (the meta authority) is the default,
' mirroring Home's MetaAddress.
function CinemetaAddress() as string
    if m.stores = invalid then return ""
    addon = m.stores.addons.callFunc("AddonsGet", "com.linvo.cinemeta")
    if addon = invalid then return ""
    return addon.address
end function

' Focus travel between the chips and the results grid. The dropdown's own keys
' are handled inside FilterBar (it owns the menu focus); with the menu closed
' Down from the chips enters the results grid and Up from the grid returns.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    ' The asterisk key is a one-press escape hatch: from anywhere in the
    ' results grid it drops focus back up onto the filter chips.
    if key = "options" and m.grid.HasFocus()
        m.filterBar.callFunc("FocusChips")
        return true
    else if key = "down" and m.filterBar.callFunc("FocusIsOnChips")
        m.grid.SetFocus(true)
        return true
    else if key = "up" and m.grid.HasFocus()
        m.filterBar.callFunc("FocusChips")
        return true
    end if
    return false
end function
