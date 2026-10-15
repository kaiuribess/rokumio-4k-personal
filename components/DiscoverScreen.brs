' DiscoverScreen — browse every installed add-on's catalogs by three filters:
' type (derived from the catalogs' declared types), catalog (every feed-capable
' catalog of the chosen type) and genre (the chosen catalog's declared options).
' Each filter is a chip; OK opens a dropdown menu of that chip's options. The
' dropdown is a Back-friendly menu — Up/Down move, OK picks, Back dismisses
' without changing anything — so a wrong pick is an instant undo, never a full
' cycle.
'
' Sources are resolved once per installed add-on set: CatalogSourcesTask fetches
' the manifests the registry has none for (the built-in seeds ship catalogs =
' invalid until a manifest lands) and the result is cached. A filter change
' kicks DiscoverLoaderTask off the render thread against the chosen
' (add-on, catalog) pair, with the genre as an encoded "genre=" extra. Results
' are chunked into poster rows; OK on a tile pushes DetailsScreen exactly like a
' Home catalog tile. Filters + results persist across Details round-trips; entry
' re-derives only when the add-on set moved, then re-focuses the results when
' there is something to show, otherwise the chips.

sub init()
    m.status = m.top.FindNode("discoverStatus")
    m.header = m.top.FindNode("discoverHeader")
    m.filterBar = m.top.FindNode("filterBar")
    m.grid = m.top.FindNode("discoverGrid")

    t = Theme()
    m.top.FindNode("discoverTitle").color = t.accent
    m.top.FindNode("discoverSub").color = t.textSecondary
    m.status.color = t.accent
    m.header.color = t.textSecondary
    m.grid.focusBitmapBlendColor = t.accentFocus

    m.filterBar.ObserveField("chipActivated", "onChipActivated")
    m.filterBar.ObserveField("optionPicked", "onOptionPicked")
    m.grid.ObserveField("rowItemSelected", "onResultSelected")
    m.grid.ObserveField("itemFocused", "onGridFocused")

    m.chunk = 5
    ' The grid's row budget: the RowList spans x 150..1810 (translation 150 + the
    ' itemSize width 1660 in DiscoverScreen.xml), with an 18px gap between tiles
    ' (rowItemSpacing). A row of cells must fit this or the RowList scrolls that
    ' row horizontally — see UpdateGrid.
    m.rowWidth = 1660
    m.rowGap = 18
    m.sources = []
    m.sourcesSignature = ""
    m.sourcesTask = invalid
    m.selectedCatalog = invalid
    m.typeKey = ""
    m.genre = ""
    m.metas = []
    m.loaded = false
    m.allLoaded = false
    m.loadTask = invalid
    m.workerSequence = 0
    m.nextPageOffset = 0
end sub

function OnEnter(params as object) as void
    if m.filterBar.callFunc("IsMenuOpen") then m.filterBar.callFunc("HideMenu")

    ' The add-on set can move while Discover is off-screen (install/uninstall,
    ' session swap). Re-derive when it did, so the chips never describe a
    ' registry that no longer exists.
    if m.stores <> invalid and CatalogSignature() <> m.sourcesSignature then ResetDiscover()

    if Type(params) = "roAssociativeArray"
        if params.metaType <> invalid or params.catalogId <> invalid or params.focusGenres = true
            m.entryRequest = params
            if m.sources.Count() > 0 then ReadySources():return
            EnsureSources()
            return
        end if
    end if

    ' Re-entry after Details: results are still here, just take focus back.
    if m.metas.Count() > 0
        m.grid.SetFocus(true)
        return
    end if

    EnsureSources()
end function

function OnExit() as void
    CancelLoad()
    CancelSources()
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

' --- sources (which add-ons serve which catalogs) ---------------------------

' The installed add-on set the current sources were derived from, as a
' comparable string. Mirrors HomeScreen's signature: derive from live store
' state, sort so ordering cannot make two equal sets look different, join. No
' network — a set comparison, not a re-derivation.
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
        m.status.text = "Could not load catalogs. Play/Pause retries; Back returns."
        return
    end if

    signature = CatalogSignature()
    if signature = m.sourcesSignature and m.sources.Count() > 0 then
        ReadySources()
        return
    end if

    addons = m.stores.addons.callFunc("AddonsGetAll")
    if addons = invalid then addons = []

    packets = []
    allKnown = true
    for each addon in addons
        if Type(addon) <> "roAssociativeArray" then continue for
        address = DiscoverText(addon.address)
        if address = "" then continue for
        if addon.catalogs = invalid or Type(addon.catalogs) <> "roArray" then allKnown = false
        packets.Push({ address: address, name: DiscoverText(addon.name), resources: addon.resources, catalogs: addon.catalogs })
    end for

    CancelSources()
    ' A new signature is not permission to reuse the previous source array
    ' while manifests for that signature are still being fetched.
    m.sources = []
    m.sourcesSignature = signature
    if packets.Count() = 0
        m.sources = []
        ShowEmpty()
        return
    end if

    if allKnown
        m.sources = packets
        ReadySources()
        return
    end if

    m.status.text = "Loading titles…     Back cancels"
    task = AsyncTask_Launch(m.top, "CatalogSourcesTask", "onSourcesLoaded", { addons: packets }, NextDiscoverWorkerId("discoverSources"))
    m.sourcesTask = task
end sub

' A CatalogSourcesTask result landed. Dropped when it arrived after a cancel
' (m.sourcesTask was cleared) so a late manifest can never repaint a screen the
' user already left.
sub onSourcesLoaded(event as object)
    if m.sourcesTask = invalid then return
    task = event.GetRoSGNode()
    if task = invalid then return
    if task.id <> m.sourcesTask.id then return
    result = event.GetData()
    if result = invalid then return
    m.sourcesTask = invalid
    AsyncTask_Reap(task, m.top, false)

    if Type(result) <> "roAssociativeArray" or Type(result.sources) <> "roArray"
        m.status.text = "Could not load catalogs. Play/Pause retries; Back returns."
        return
    end if

    m.sources = result.sources
    ReadySources()
end sub

' Sources are in hand: pick a valid selection and fetch.
sub ReadySources()
    request = m.entryRequest
    m.entryRequest = invalid
    if Type(request) = "roAssociativeArray"
        if DiscoverText(request.metaType) <> "" then m.typeKey = TypeKey(request.metaType):m.selectedCatalog=invalid
        m.genre = DiscoverText(request.genre)
        if DiscoverText(request.addonAddress) <> "" and DiscoverText(request.catalogId) <> ""
            m.selectedCatalog={address:request.addonAddress,rawType:request.metaType,catalogId:request.catalogId}
        end if
    end if
    if not SelectDefaults()
        ShowEmpty()
        return
    end if
    if Type(request) = "roAssociativeArray" and request.focusGenres = true
        if GenreOptions().Count() = 0 then SelectGenreCatalog()
    end if
    ' A new preset owns a fresh page-zero response. Results retained from a
    ' Details round trip are only reused by OnEnter without a preset.
    ResetDiscover()
    FetchDiscover()
    SetChips()
    m.filterBar.callFunc("FocusChips")
    if Type(request) = "roAssociativeArray" and request.focusGenres = true
        if GenreOptions().Count() > 0
            m.filterBar.callFunc("FocusChips",2)
            m.filterBar.chipActivated=2
        end if
    end if
end sub

sub SelectGenreCatalog()
    oldType=m.typeKey:oldCatalog=m.selectedCatalog:oldGenre=m.genre
    for each group in TypeGroups()
        m.typeKey=group.key
        for each candidate in CatalogsForType()
            m.selectedCatalog=candidate
            if GenreOptions().Count()>0 then EnsureGenre():return
        end for
    end for
    m.typeKey=oldType:m.selectedCatalog=oldCatalog:m.genre=oldGenre
end sub

' The catalog type keys present across the sources, in a stable order: the
' three media families first, then any other declared type alphabetically.
' Only types that yield at least one feed-capable catalog are listed, so every
' type chip leads somewhere.
function TypeGroups() as object
    groups = []
    if m.stores = invalid then return groups

    seen = {}
    otherKeys = []
    for each source in m.sources
        if Type(source) <> "roAssociativeArray" then continue for
        if Type(source.catalogs) <> "roArray" then continue for
        for each descriptor in source.catalogs
            if Type(descriptor) <> "roAssociativeArray" then continue for
            caps = m.stores.addons.callFunc("AddonsCatalogCapabilities", descriptor)
            if caps = invalid or not caps.feed then continue for
            key = TypeKey(descriptor.type)
            if key = "" then continue for
            if seen.DoesExist(key) then continue for
            seen[key] = true
            if TypeOrder(key) >= 3 then otherKeys.Push(key)
        end for
    end for

    otherKeys.Sort("i")
    ordered = []
    preferred = ["movie", "series", "channels"]
    for each key in preferred
        if seen.DoesExist(key) then ordered.Push(key)
    end for
    for each key in otherKeys
        ordered.Push(key)
    end for
    for each key in ordered
        groups.Push({ key: key, label: TypeLabel(key) })
    end for
    return groups
end function

' The chip entries for the type filter ({ raw, label }).
function TypeOptions() as object
    options = []
    for each group in TypeGroups()
        options.Push({ raw: group.key, label: group.label })
    end for
    return options
end function

' A catalog type folded into a filter key. movie/series stand alone; channel and
' tv are one family (manifests use either spelling for the same content);
' anything else keeps its declared name.
function TypeKey(raw as dynamic) as string
    raw = DiscoverText(raw)
    if raw = "" then return ""
    if raw = "movie" then return "movie"
    if raw = "series" then return "series"
    if raw = "channel" or raw = "tv" then return "channels"
    return raw
end function

function TypeOrder(key as string) as integer
    if key = "movie" then return 0
    if key = "series" then return 1
    if key = "channels" then return 2
    return 3
end function

function TypeLabel(key as string) as string
    if key = "movie" then return "Movies"
    if key = "series" then return "Series"
    if key = "channels" then return "Channels"
    if key = "" then return ""
    ' A declared type is a free string ("sports", "tv", …), so this fallback is
    ' reachable. UCase is a global function, not an roString method — the chained
    ' form threw &hf4 the first time a custom type hit it.
    return UCase(key.Left(1)) + key.Mid(1)
end function

function TypeMatches(declared as dynamic, key as string) as boolean
    if declared = invalid then return false
    if key = "channels" then return declared = "channel" or declared = "tv"
    return declared = key
end function

' Every feed-capable catalog of the current type, across all sources. A catalog
' is feed-capable when nothing beyond skip/genre is required (AddonsStore owns
' that rule), which keeps odd catalogs like cinemeta's required-id last-videos
' out without any per-add-on special case.
function CatalogsForType() as object
    list = []
    if m.stores = invalid then return list
    for each source in m.sources
        if Type(source) <> "roAssociativeArray" then continue for
        if Type(source.catalogs) <> "roArray" then continue for
        for each descriptor in source.catalogs
            if Type(descriptor) <> "roAssociativeArray" then continue for
            if not TypeMatches(descriptor.type, m.typeKey) then continue for
            caps = m.stores.addons.callFunc("AddonsCatalogCapabilities", descriptor)
            if caps = invalid or not caps.feed then continue for
            sourceName = source.name
            if sourceName = invalid then sourceName = ""
            list.Push({
                address: source.address
                sourceName: sourceName
                rawType: descriptor.type
                catalogId: descriptor.id
                title: m.stores.addons.callFunc("AddonsCatalogTitle", descriptor, source.name)
                catalog: descriptor
            })
        end for
    end for
    return list
end function

' The catalog chip's options. Duplicate catalog names across add-ons are
' disambiguated with the add-on's name so two "Popular" rows are distinguishable.
function CatalogOptions() as object
    catalogs = CatalogsForType()
    options = []
    count = catalogs.Count()
    ' Indexed loops, not nested "for each" over the same array: a Roku device
    ' gives an roArray ONE internal iterator, so an inner "for each" over the
    ' same list exhausts it and the outer loop stops after the first element
    ' (the brs interpreter uses independent iterators, so tests never see it).
    for i = 0 to count - 1
        candidate = catalogs[i]
        label = candidate.title
        dupes = 0
        for j = 0 to count - 1
            other = catalogs[j]
            if other.title = candidate.title and not SameCatalog(other, candidate) then dupes = dupes + 1
        end for
        if dupes > 0 then label = label + " (" + candidate.sourceName + ")"
        options.Push({ raw: candidate.catalogId, label: label, catalog: candidate })
    end for
    return options
end function

function SameCatalog(a as dynamic, b as dynamic) as boolean
    if a = invalid or b = invalid then return false
    return a.address = b.address and a.rawType = b.rawType and a.catalogId = b.catalogId
end function

function CatalogChipLabel() as string
    if m.selectedCatalog = invalid then return ""
    for each option in CatalogOptions()
        if SameCatalog(option.catalog, m.selectedCatalog) then return option.label
    end for
    return m.selectedCatalog.title
end function

' --- selection defaults -----------------------------------------------------

' Validate the current (type, catalog, genre) against the resolved sources and
' fall back to the first available value where the old one is gone. Returns
' false only when no feed-capable catalog exists at all.
function SelectDefaults() as boolean
    groups = TypeGroups()
    if groups.Count() = 0 then return false

    typeFound = false
    for each group in groups
        if group.key = m.typeKey then typeFound = true
    end for
    if not typeFound then m.typeKey = groups[0].key

    catalogs = CatalogsForType()
    if catalogs.Count() = 0 then
        for each group in groups
            m.typeKey = group.key
            catalogs = CatalogsForType()
            if catalogs.Count() > 0 then exit for
        end for
    end if
    if catalogs.Count() = 0 then return false

    keep = false
    if m.selectedCatalog <> invalid
        for each candidate in catalogs
            if SameCatalog(candidate, m.selectedCatalog) then
                m.selectedCatalog = candidate
                keep = true
            end if
        end for
    end if
    if not keep then m.selectedCatalog = catalogs[0]

    EnsureGenre()
    return true
end function

sub ShowEmpty()
    m.status.text = "No catalog add-ons installed."
    m.filterBar.callFunc("SetChips", [])
end sub

' --- genre (the chosen catalog's filter) ------------------------------------

function SelectedCapabilities() as object
    if m.stores = invalid or m.selectedCatalog = invalid then return invalid
    return m.stores.addons.callFunc("AddonsCatalogCapabilities", m.selectedCatalog.catalog)
end function

' The genre chip's options: the catalog's declared genres, prefixed with "All"
' when a genre is optional. A catalog with no genre extra, or with no declared
' options, gets no genre chip.
function GenreOptions() as object
    options = []
    caps = SelectedCapabilities()
    if caps = invalid or not caps.genre then return options
    if caps.genreOptions = invalid or Type(caps.genreOptions) <> "roArray" or caps.genreOptions.Count() = 0 then return options
    if not caps.genreRequired then options.Push({ raw: "All", label: "All" })
    for each genre in caps.genreOptions
        options.Push({ raw: genre, label: genre })
    end for
    return options
end function

' The default genre for the chosen catalog: the current year when a genre is
' required and the year is one of its options (the "New" catalog's shape), else
' the first declared option; "All" when a genre is optional.
function DefaultGenre() as string
    caps = SelectedCapabilities()
    if caps = invalid or not caps.genre then return ""
    options = caps.genreOptions
    if options = invalid or Type(options) <> "roArray" or options.Count() = 0 then return ""
    if caps.genreRequired
        year = CreateObject("roDateTime").GetYear().ToStr()
        for each option in options
            if option = year then return year
        end for
        return options[0]
    end if
    return "All"
end function

' Keep the genre valid across a catalog/type change: leave it alone when the new
' catalog still offers it, otherwise fall back to that catalog's default.
sub EnsureGenre()
    options = GenreOptions()
    if options.Count() = 0 then m.genre = "" : return
    for each option in options
        if option.raw = m.genre then return
    end for
    m.genre = DefaultGenre()
end sub

' The genre value to send to the server, or "" for no genre filter. Required
' genres always send their value; optional ones drop the "All" sentinel.
function GenreFilter() as string
    caps = SelectedCapabilities()
    if caps = invalid or not caps.genre then return ""
    if caps.genreRequired then return m.genre
    if m.genre = "" or m.genre = "All" then return ""
    return m.genre
end function

' --- filter chips (data) ----------------------------------------------------

' The chip row itself lives in FilterBar; the screen owns the values and their
' labels. "Type · ..."-style labels make each chip's role readable; the genre
' chip is omitted when the chosen catalog has no genre filter. Rebuilt on every
' pick so the label always reflects the active value.
sub SetChips()
    entries = []
    if TypeGroups().Count() > 0
        entries.Push({ raw: m.typeKey, label: "Type · " + TypeLabel(m.typeKey) })
    end if
    if m.selectedCatalog <> invalid
        entries.Push({ raw: m.selectedCatalog.catalogId, label: "Catalog · " + CatalogChipLabel() })
    end if
    if GenreOptions().Count() > 0
        label = m.genre
        if label = "" then label = "All"
        entries.Push({ raw: m.genre, label: "Genre · " + label })
    end if
    m.filterBar.callFunc("SetChips", entries)
end sub

' The chip OK'd in the FilterBar: hand it that chip's options and the index of
' the current value, and the component opens the dropdown pre-scrolled there.
sub onChipActivated()
    chip = m.filterBar.chipActivated
    if chip < 0 then return
    options = OptionsFor(chip)
    if options.Count() = 0 then return
    m.filterBar.callFunc("ShowMenu", options, CurrentOptionIndex(chip))
end sub

function OptionsFor(chip as integer) as object
    if chip = 0 then return TypeOptions()
    if chip = 1 then return CatalogOptions()
    if chip = 2 then return GenreOptions()
    return []
end function

function CurrentOptionIndex(chip as integer) as integer
    options = OptionsFor(chip)
    if chip = 0
        for i = 0 to options.Count() - 1
            if options[i].raw = m.typeKey then return i
        end for
    else if chip = 1
        for i = 0 to options.Count() - 1
            if SameCatalog(options[i].catalog, m.selectedCatalog) then return i
        end for
    else if chip = 2
        for i = 0 to options.Count() - 1
            if options[i].raw = m.genre then return i
        end for
    end if
    return 0
end function

' An option OK'd in the FilterBar's dropdown, then re-fetches. Re-picking the
' current value just closes the menu.
sub onOptionPicked()
    pick = m.filterBar.optionPicked
    if pick = invalid or pick.chip = invalid or pick.index = invalid then return
    chip = pick.chip
    options = OptionsFor(chip)
    index = pick.index
    if index < 0 or index >= options.Count() then return
    option = options[index]

    if chip = 0
        if option.raw = m.typeKey then m.filterBar.callFunc("HideMenu") : return
        m.typeKey = option.raw
        catalogs = CatalogsForType()
        if catalogs.Count() = 0 then m.filterBar.callFunc("HideMenu") : return
        m.selectedCatalog = catalogs[0]
        EnsureGenre()
    else if chip = 1
        if SameCatalog(option.catalog, m.selectedCatalog) then m.filterBar.callFunc("HideMenu") : return
        m.selectedCatalog = option.catalog
        EnsureGenre()
    else if chip = 2
        if option.raw = m.genre then m.filterBar.callFunc("HideMenu") : return
        m.genre = option.raw
    end if

    m.filterBar.callFunc("HideMenu")
    SetChips()
    ResetDiscover()
    FetchDiscover()
end sub

' --- fetching ---------------------------------------------------------------

' A fresh filter set: start back at page 0.
sub ResetDiscover()
    CancelLoad()
    m.metas = []
    m.nextPageOffset = 0
    m.allLoaded = false
    m.loaded = false
    if m.grid <> invalid
        m.grid.content = CreateObject("roSGNode", "ContentNode")
        m.grid.numRows = 0
    end if
end sub

' Kick the chosen catalog off the render thread. A filter change supersedes
' whatever page is still in flight (its event is rejected by its unique id),
' so picks never queue behind a stale load. The wanted offset is
' captured so a page that lands after the user changed filters (or exited) is
' dropped instead of appended to the wrong list.
sub FetchDiscover()
    if m.selectedCatalog = invalid then return
    CancelLoad()

    m.status.text = "Loading titles…     Back cancels"
    task = AsyncTask_Launch(m.top, "DiscoverLoaderTask", "onDiscoverLoaded", {
        addonAddress: m.selectedCatalog.address
        metaType: m.selectedCatalog.rawType
        catalogId: m.selectedCatalog.catalogId
        genre: GenreFilter()
        pageOffset: 0
    }, NextDiscoverWorkerId("discoverLoader"))
    m.loadTask = task
end sub

' The user scrolled near the bottom of the fetched results: fetch the next page
' (skip = raw provider records consumed) and append. Silent — the grid stays up untouched
' until the page lands, so scrolling never blinks.
sub LoadMore()
    if m.selectedCatalog = invalid then return
    if m.loadTask <> invalid then return
    if m.allLoaded then return
    if m.metas.Count() = 0 then return

    task = AsyncTask_Launch(m.top, "DiscoverLoaderTask", "onDiscoverLoaded", {
        addonAddress: m.selectedCatalog.address
        metaType: m.selectedCatalog.rawType
        catalogId: m.selectedCatalog.catalogId
        genre: GenreFilter()
        pageOffset: m.nextPageOffset
    }, NextDiscoverWorkerId("discoverLoaderMore"))
    m.loadTask = task
end sub

' Near the bottom of the fetched results, pull the next page. The 3-row horizon
' means a smooth pre-load; because an append keeps the focused row anchored, one
' page lands per scroll instead of cascading to the end. itemFocused is the
' integer index of the focused row; the total row count is derived from what we
' have loaded (numRows is the visible count).
sub onGridFocused()
    row = m.grid.itemFocused
    rows = Int((m.metas.Count() + m.chunk - 1) / m.chunk)
    if rows > 0 and row >= rows - 3 then LoadMore()
end sub

' A landing may grab chips focus only when the dropdown is closed — an open
' menu keeps its focus through the landing so a load finishing can't yank the
' user out of a pick.
sub LandingChipsFocus()
    if m.top.screenActive and not m.filterBar.callFunc("IsMenuOpen")
        m.filterBar.callFunc("FocusChips")
    end if
end sub

' A catalog page came back. Stale results are dropped: a page whose offset no
' longer matches the metas already shown landed after a filter change (which
' resets the list), and the m.loadTask guard drops anything that arrived after
' CancelLoad.
sub onDiscoverLoaded(event as object)
    if m.loadTask = invalid then return
    task = event.GetRoSGNode()
    if task = invalid then return
    if task.id <> m.loadTask.id then return
    result = event.GetData()
    if result = invalid then return
    m.loadTask = invalid
    AsyncTask_Reap(task, m.top, false)

    wantedOffset = task.pageOffset
    if wantedOffset <> m.nextPageOffset then return

    label = DiscoverLabel()
    if Type(result) <> "roAssociativeArray" or result.ok <> true or Type(result.metas) <> "roArray"
        if m.metas.Count() = 0
            m.status.text = "Could not load " + Chr(34) + label + Chr(34) + ". Play/Pause retries."
            LandingChipsFocus()
        end if
        return
    end if

    usable = DiscoverUsableMetas(result.metas)
    consumed = result.metas.Count()
    if Type(result.rawCount) = "Integer" or Type(result.rawCount) = "roInteger"
        if result.rawCount >= consumed then consumed = result.rawCount
    end if
    m.nextPageOffset = wantedOffset + consumed
    if wantedOffset = 0
        m.metas = usable
        m.loaded = true
        m.header.text = label
        m.allLoaded = result.hasMore <> true or consumed = 0
        if m.metas.Count() = 0
            m.grid.content = CreateObject("roSGNode", "ContentNode")
            m.grid.numRows = 0
            m.status.text = "No results for " + Chr(34) + label + Chr(34) + "."
            LandingChipsFocus()
            return
        end if
        UpdateGrid()
        m.status.text = ""
        LandingChipsFocus()
    else
        for each meta in usable
            m.metas.Push(meta)
        end for
        m.allLoaded = result.hasMore <> true or consumed = 0
        UpdateGrid(AppendRestorePosition())
    end if
end sub

' The grid position to keep after an append: the focused row and tile, or the
' first tile of the freshly added block when the focused row already fell off
' the end. Because rowItemFocused is read before the content rebuild, the tile
' column survives, so the exact selected item keeps focus.
function AppendRestorePosition() as object
    if m.grid.rowItemFocused = invalid or m.grid.rowItemFocused.Count() < 2 then return [0, 0]
    position = [m.grid.rowItemFocused[0], m.grid.rowItemFocused[1]]
    newRows = Int((m.metas.Count() + m.chunk - 1) / m.chunk)
    if position[0] < 0 then return [0, 0]
    if position[0] >= newRows then position[0] = newRows - 1
    return position
end function

' The human summary of the current filters, e.g. "Popular · Movies · Sci-Fi".
function DiscoverLabel() as string
    if m.selectedCatalog = invalid then return ""
    label = m.selectedCatalog.title + " · " + TypeLabel(TypeKey(m.selectedCatalog.rawType))
    if m.genre <> "" and m.genre <> "All" then label = label + " · " + m.genre
    return label
end function

' Lay all loaded metas out as poster rows so the RowList clips/scrolls them
' vertically. The column count (m.chunk) is recomputed from the cell size so the
' row always fits the grid width; jumpToRow keeps the view anchored after an
' append, preserving the focused row and tile.
sub UpdateGrid(rowToShow = invalid as dynamic)
    focusIndex = invalid
    if Type(rowToShow) = "roArray" and rowToShow.Count() >= 2 then
        focusIndex = rowToShow[0] * m.chunk + rowToShow[1]
    end if
    ' Selection and rendering must share the same normalized list.
    m.metas = DiscoverUsableMetas(m.metas)
    mt = invalid
    if m.selectedCatalog <> invalid then mt = m.selectedCatalog.rawType
    ' The whole grid sizes to the catalog's posterShape (folded from its metas),
    ' the same rule Home rows use, so a 16:9 catalog gets wide tiles instead of
    ' letterboxed 2:3 cells; falls back to the content type when no shape ships.
    size = TileCellSize(mt, TilePosterShape(m.metas))
    ' A wide (16:9) cell places fewer tiles per row instead of overflowing the row
    ' into per-row horizontal scrolling (the "grid becomes a list of rows" break).
    ' All rows share one chunk so the flat index (row*chunk + col) stays honest.
    m.chunk = TileColumns(m.rowWidth, size[0], m.rowGap)

    content = CreateObject("roSGNode", "ContentNode")
    totalRows = Int((m.metas.Count() + m.chunk - 1) / m.chunk)
    for r = 0 to totalRows - 1
        row = content.CreateChild("ContentNode")
        for c = 0 to m.chunk - 1
            flat = r * m.chunk + c
            if flat >= m.metas.Count() then exit for
            meta = m.metas[flat]
            item = row.CreateChild("TileContent")
            name = meta.name
            if name = invalid then name = ""
            item.title = name
            poster = meta.poster
            if poster <> invalid and poster <> "" then item.hdPosterUrl = poster
            glyph = ""
            if m.stores <> invalid then glyph = m.stores.library.callFunc("LibraryWatchedGlyph", meta.id, meta.type)
            item.watchedGlyph = glyph
        end for
    end for
    m.grid.content = content
    m.grid.itemSize = [m.rowWidth, size[1]]
    m.grid.rowItemSize = [size]
    m.grid.numRows = DiscoverVisibleRows(totalRows, size[1])
    if focusIndex <> invalid and m.metas.Count() > 0
        if focusIndex < 0 then focusIndex = 0
        if focusIndex >= m.metas.Count() then focusIndex = m.metas.Count() - 1
        ' If the appended page changes the dominant poster shape/column count,
        ' keep the same title focused rather than the old row/column coordinates.
        m.grid.jumpToRowItem = [Int(focusIndex / m.chunk), focusIndex MOD m.chunk]
    end if
end sub

' All result rows stay in content. numRows is only the visible viewport;
' the existing y=362 grid has 650 pixels before the lower screen margin.
function DiscoverVisibleRows(totalRows as integer, rowHeight as integer) as integer
    if totalRows <= 0 then return 0
    if rowHeight <= 0 then return 1
    visible = Int((650 + 18) / (rowHeight + 18))
    if visible < 1 then visible = 1
    if visible > 2 then visible = 2
    if visible > totalRows then visible = totalRows
    return visible
end function

function NextDiscoverWorkerId(prefix as string) as string
    if m.workerSequence = invalid then m.workerSequence = 0
    m.workerSequence = m.workerSequence + 1
    return prefix + m.workerSequence.ToStr()
end function

function DiscoverText(value as dynamic) as string
    if Type(value) = "String" or Type(value) = "roString" then return value.Trim()
    return ""
end function

function DiscoverUsableMetas(items as dynamic) as object
    usable = []
    if Type(items) <> "roArray" then return usable
    for each meta in items
        if Type(meta) <> "roAssociativeArray" then continue for
        if DiscoverText(meta.id) = "" or DiscoverText(meta.type) = "" or DiscoverText(meta.name) = "" then continue for
        clean = {}
        for each key in meta
            clean[key] = meta[key]
        end for
        for each key in ["id", "type", "name", "poster", "posterShape", "description", "background", "logo", "releaseInfo", "imdbRating"]
            if clean[key] <> invalid then clean[key] = DiscoverText(clean[key])
        end for
        kind = Type(clean.runtime)
        if clean.runtime <> invalid and kind <> "String" and kind <> "roString" and kind <> "Integer" and kind <> "roInt" and kind <> "roInteger" and kind <> "Float" and kind <> "roFloat" and kind <> "Double" and kind <> "roDouble" then clean.Delete("runtime")
        usable.Push(clean)
    end for
    return usable
end function

sub CancelLoad()
    if m.loadTask <> invalid
        task = m.loadTask
        m.loadTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

sub CancelSources()
    if m.sourcesTask <> invalid
        task = m.sourcesTask
        m.sourcesTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

' --- selection --------------------------------------------------------------

' A result opens DetailsScreen through the same one-action channel Home and
' Search use for a catalog tile: full meta + the source add-on's address.
sub onResultSelected()
    if m.selectedCatalog = invalid then return
    data = m.grid.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    if data[0] < 0 or data[1] < 0 or data[1] >= m.chunk then return
    flat = data[0] * m.chunk + data[1]
    if flat < 0 or flat >= m.metas.Count() then return
    m.top.pushRequest = {
        screen: "detailsScreen"
        params: {
            addonAddress: m.selectedCatalog.address
            meta: m.metas[flat]
        }
    }
end sub

' Focus travel between the chips and the results grid. The dropdown's own keys
' are handled inside FilterBar (it owns the menu focus); with the menu closed
' Down from the chips enters the results grid and Up from the grid returns.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "play"
        if m.selectedCatalog <> invalid and m.sources.Count() > 0
            ResetDiscover()
            FetchDiscover()
        else
            m.sourcesSignature = ""
            EnsureSources()
        end if
        return true
    end if

    ' The asterisk key is a one-press escape hatch: from anywhere in the
    ' results grid it drops focus back up onto the filter chips.
    if key = "options" and m.grid.HasFocus()
        m.filterBar.callFunc("FocusChips")
        return true
    else if key = "down" and m.filterBar.callFunc("FocusIsOnChips")
        if m.metas.Count() = 0 then return true
        m.grid.SetFocus(true)
        return true
    else if key = "up" and m.grid.HasFocus()
        m.filterBar.callFunc("FocusChips")
        return true
    end if
    return false
end function

sub EnsureCurrentSources()
    if m.stores = invalid or CatalogSignature() = m.sourcesSignature then return
    CancelSources()
    ResetDiscover()
    m.sources = []:m.sourcesSignature = ""
    m.sourcesSignature = CatalogSignature()
    if m.top.visible then EnsureSources()
end sub
