' DetailsScreen — one screen for both content kinds.
'
' Movies render a hero (poster, name, type/year/rating, description) plus a chip
' row (Play, and an "add to library" toggle backed by LibraryStore) and push a
' stream selection on Play. Series render the same hero, then a chip row: a
' Resume chip for the saved position (falling back to "Play S1E1" when nothing
' is saved), the same "add to library" toggle, and an "Episodes" chip that
' pushes the dedicated EpisodesScreen.
'
' One shared chips RowList serves both kinds — the chips differ, the plumbing
' doesn't. Each chip ContentNode maps to a stored action id, and a single
' selection observer dispatches on that id.
'
' Params: { addonAddress, meta } for a hero rendered from the catalog data
' immediately, plus an optional resume hint { videoId, season, episode, position }
' from the Continue-Watching row. CW tiles fetch their own full meta by id
' before this screen opens, so the hero there matches a catalog-opened title.
' Search and Discover catalog metas are slim ({ id, type, name }) — those top up
' their missing fields with a MetaLoaderTask fetch merged into the passed-in
' record, so the caller's own values always win. When no resume hint arrives,
' the local LibraryStore supplies the most recent position for the meta, so a
' catalog-opened show still offers to pick up where the user left off.

sub init()
    m.heroPoster = m.top.FindNode("heroPoster")
    m.bgPoster = m.top.FindNode("bgPoster")
    m.detailName = m.top.FindNode("detailName")
    m.detailType = m.top.FindNode("detailType")
    m.detailDesc = m.top.FindNode("detailDesc")
    m.chipsRow = m.top.FindNode("chipsRow")

    t = Theme()
    m.top.FindNode("detailsBg").color = t.screenBg
    m.top.FindNode("bgScrim").color = t.scrim
    m.detailName.color = t.textPrimary
    m.detailType.color = t.accent
    m.detailDesc.color = t.textSecondary
    m.top.FindNode("detailSourceHint").color = t.textSecondary
    m.top.FindNode("detailHelp").color = t.textSecondary
    m.chipsRow.focusBitmapBlendColor = t.accentFocus

    m.chipsRow.ObserveField("rowItemSelected", "onChipSelected")
    m.metaTaskSequence = 0
    m.loadTask = invalid
    m.prefetchTimer = m.top.FindNode("detailsPrefetchDelay")
    m.prefetchTimer.ObserveField("fire", "onDetailsPrefetch")
    m.prefetchContext = invalid
    m.prefetchHandOff = false
    m.prefetchClock = CreateObject("roTimespan")
    m.prefetchClock.Mark()
    m.prefetchDeadline = 0
end sub

function OnEnter(params as object) as void
    ' Re-entry after a push (EpisodesScreen, streams, …): params is invalid and
    ' the screen Group (not a focus target) was handed focus by the stack. The
    ' chip RowList must take it back, or nothing inside is reachable.
    if params = invalid
        RestoreFocus()
        ScheduleDetailsPrefetch()
        return
    end if
    m.params = params
    if params.meta = invalid then return
    meta = params.meta
    m.addonAddress = params.addonAddress
    m.meta = meta

    ' Resume hint: the Continue-Watching row passes its own; otherwise the local
    ' library stands in (catalog-opened shows still know where you stopped).
    m.resume = params.resume
    if m.resume = invalid and m.stores <> invalid
        m.resume = m.stores.library.callFunc("LibraryResumeFor", meta.id)
    end if

    m.metaRefreshed = false
    RenderHero(meta)

    if meta.type = "series"
        ShowSeries()
    else
        ShowMovie()
    end if
    MaybeRefreshMeta()
    ScheduleDetailsPrefetch()
end function

sub ScheduleDetailsPrefetch()
    if m.prefetchTimer = invalid then return
    m.prefetchTimer.control = "stop"
    m.prefetchHandOff = false
    SourcePrefetch_Cancel(m.top, m.prefetchContext)
    m.prefetchContext = invalid
    if Type(m.meta) = "roAssociativeArray" and m.meta.type = "movie" and m.top.screenActive
        if m.prefetchClock <> invalid then m.prefetchDeadline = m.prefetchClock.TotalMilliseconds() + 500
        m.prefetchTimer.duration = 0.5
        m.prefetchTimer.control = "start"
    end if
end sub

function DetailsPrefetchParams() as dynamic
    if Type(m.meta) <> "roAssociativeArray" or m.meta.type <> "movie" then return invalid
    return {addonAddress:m.addonAddress, metaType:m.meta.type, metaId:m.meta.id, videoId:m.meta.id}
end function

sub onDetailsPrefetch()
    if not m.top.screenActive then return
    if not SourcePrefetch_DelayReady(m.prefetchTimer, m.prefetchClock, m.prefetchDeadline) then return
    m.prefetchContext = SourcePrefetch_Context(m.stores, DetailsPrefetchParams())
    SourcePrefetch_Prepare(m.top, m.prefetchContext)
end sub

' Fill the hero chrome from a meta: title, the {type · release · rating} line,
' poster, background and description. Called on entry with the catalog meta, and
' again when a deferred meta fetch returns a fuller record — the passed-in
' values always win, fetched fields only top up the gaps.
sub RenderHero(meta as object)
    if meta = invalid then return

    name = meta.name
    if name = invalid then name = ""
    m.detailName.text = name

    RenderKind(meta)
    ApplyHeroSize(meta.type)

    poster = meta.poster
    if poster = invalid then poster = ""
    m.heroPoster.uri = poster

    ' Cinemeta catalog metas carry a `background` artwork URL; fill the screen
    ' behind everything. Missing background leaves the flat theme base showing.
    bg = meta.background
    if bg = invalid then bg = ""
    m.bgPoster.uri = bg

    desc = meta.description
    if GetInterface(desc, "ifString") <> invalid and desc.Trim() <> ""
        m.detailDesc.text = desc
    else
        m.detailDesc.text = "No synopsis available."
    end if
end sub

' Search and Discover hand over slim catalog metas ({ id, type, name }) whose
' hero fields are missing. Fetch the full Cinemeta record off the UI thread when
' that is the case, then MergeMeta it into m.meta — the caller's non-empty
' values stay put, the fetch only fills the blanks. Already-complete metas,
' metas with nothing fetchable, and metas without an add-on to ask skip the trip
' entirely.
sub MaybeRefreshMeta()
    if m.stores = invalid then return
    if m.meta = invalid or m.meta.id = invalid or m.meta.type = invalid then return
    if m.addonAddress = invalid or m.addonAddress = "" then return
    if m.metaRefreshed then return

    CancelMetaLoad()

    if not m.stores.episodes.callFunc("EpisodesNeedsMetaFetch", m.meta) then return

    m.metaTaskSequence = m.metaTaskSequence + 1
    task = AsyncTask_Launch(m.top, "MetaLoaderTask", "onMetaLoaded", {
        addonAddress: m.addonAddress
        metaType: m.meta.type
        metaId: m.meta.id
    }, "detailsMetaLoader" + m.metaTaskSequence.ToStr())
    m.loadTask = task
end sub

' Tear down an in-flight meta refresh. A newer entry supersedes it, and leaving
' this screen drops it too. STOP is the real cancel — merely removing a running
' Task node does not kill its worker thread — and dropping the observer means
' its result can never land.
sub CancelMetaLoad()
    if m.loadTask <> invalid
        task = m.loadTask
        m.loadTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

' The full meta came back. Merge it into what the caller handed in (their values
' win), remember we are done, and re-render the hero. A failed or mismatched
' fetch changes nothing — the screen keeps the catalog record it already shows.
sub onMetaLoaded(event as object)
    if m.stores = invalid then return
    if m.loadTask = invalid then return
    task = event.GetRoSGNode()
    if task = invalid then return
    if task.id <> m.loadTask.id then return
    result = task.result
    if result = invalid then return
    m.loadTask = invalid
    AsyncTask_Reap(task, m.top, false)

    if result.ok <> true or Type(result.meta) <> "roAssociativeArray" then return
    if result.meta.id <> invalid and m.meta <> invalid and result.meta.id <> m.meta.id then return

    m.meta = m.stores.episodes.callFunc("EpisodesMergeMeta", m.meta, result.meta)
    m.metaRefreshed = true
    RenderHero(m.meta)
end sub

' Re-entry: the shared chip RowList just needs focus back. m.meta/m.resume
' survive the push/pop, so a rebuild is not needed.
sub RestoreFocus()
    if m.meta = invalid then return
    m.chipsRow.SetFocus(true)
end sub

' Channel-family metas (Stremio "channel"/"tv", one family — the same rule
' TileCellSize uses for grid rows) ship 1:1 artwork; every other type ships the
' 2:3 poster slab. The node must take the source's shape or limitSize decodes an
' off-ratio bitmap smaller than its node and leaves an uncovered strip. The load
' caps ride the node so the memory policy holds for both shapes, exactly as
' PosterTile does for a square cell. Called on every render, so a screen reused
' across entries always resets to the type it is showing now.
sub ApplyHeroSize(metaType as dynamic)
    w = 340
    h = 510
    if metaType <> invalid and metaType <> ""
        lower = LCase(metaType)
        if lower = "channel" or lower = "tv"
            w = 420
            h = 420
        end if
    end if
    m.heroPoster.width = w
    m.heroPoster.height = h
    m.heroPoster.loadWidth = w
    m.heroPoster.loadHeight = h
end sub

' The second header line: "{type} · {releaseInfo} · ★ {imdbRating}", with the
' movie runtime appended when the meta carries it (Cinemeta does).
sub RenderKind(meta as object)
    kind = TypeLabel(meta.type)
    if meta.releaseInfo <> invalid and meta.releaseInfo <> "" then kind = kind + " · " + meta.releaseInfo
    if meta.imdbRating <> invalid and meta.imdbRating <> "" then kind = kind + " · ★ " + meta.imdbRating
    if meta.runtime <> invalid and meta.type <> "series"
        runtime = FormatRuntime(meta.runtime)
        if runtime <> "" then kind = kind + " · " + runtime
    end if
    m.detailType.text = kind
end sub

' Runtime echoed straight from the meta JSON — Cinemeta ships plain minutes, so
' no parsing and no "2h 5m" conversion. Per-component function scope: duplicated
' from StreamsScreen, since Roku does not share globals across components.
function FormatRuntime(runtime as dynamic) as string
    if runtime = invalid then return ""
    return runtime.ToStr().Trim()
end function

' Series chips: Resume for the saved spot when there is one, otherwise a "Play
' S1E1" stand-in (the episode list itself loads on EpisodesScreen; the optional
' hero refresh above only tops up missing catalog fields), then the same
' "add to library" toggle the movie row carries, then "Episodes".
sub ShowSeries()
    actions = []
    if m.resume <> invalid and m.resume.season <> invalid and m.resume.episode <> invalid
        actions.Push({ action: "resume", title: "Resume S" + m.resume.season.ToStr() + "E" + m.resume.episode.ToStr() })
    else
        actions.Push({ action: "play", title: "First episode" })
    end if
    actions.Push({ action: "episodes", title: "Episodes" })
    actions.Push({ action: "library", title: LibraryActionLabel() })
    ShowChips(actions)
end sub

sub ShowMovie()
    actions = []
    actions.Push({ action: "play", title: "Play movie" })
    actions.Push({ action: "library", title: LibraryActionLabel() })
    ShowChips(actions)
end sub

' Fill the shared chips row and remember the action id per chip so the single
' selection observer can dispatch.
sub ShowChips(actions as object)
    m.chips = actions
    root = CreateObject("roSGNode", "ContentNode")
    row = root.CreateChild("ContentNode")
    for each chip in actions
        item = row.CreateChild("ChipContent")
        item.title = chip.title
        item.width = m.chipsRow.rowItemSize[0][0]
        item.height = m.chipsRow.rowItemSize[0][1]
    end for
    m.chipsRow.content = root
    m.chipsRow.jumpToRowItem = [0, 0]
    if m.top.screenActive then m.chipsRow.SetFocus(true)
end sub

sub onChipSelected()
    data = m.chipsRow.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[1]
    if m.chips = invalid or index < 0 or index >= m.chips.Count() then return
    action = m.chips[index].action
    if action = "resume"
        ResumeEpisode()
    else if action = "play"
        PlayMedia()
    else if action = "episodes"
        OpenEpisodes()
    else if action = "library"
        ToggleLibrary()
    end if
end sub

' Resume sends the user into stream selection for the saved episode. The Streams
' screen is the picker; this push carries the full context for it.
sub ResumeEpisode()
    if m.resume = invalid or m.stores = invalid then return
    videoId = m.stores.episodes.callFunc("EpisodesResolveVideoId", m.meta.id, m.resume.season, m.resume.episode, m.meta)
    if GetInterface(m.resume.videoId, "ifString") <> invalid and m.resume.videoId <> "" then videoId = m.resume.videoId
    m.top.pushRequest = {
        screen: "streamsScreen"
        params: {
            autoPlay: true
            seriesMeta: m.meta
            addonAddress: m.addonAddress
            metaType: m.meta.type
            metaId: m.meta.id
            videoId: videoId
            season: m.resume.season
            episode: m.resume.episode
            position: ResumePosition()
            name: m.meta.name
            poster: m.meta.poster
            posterShape: m.meta.posterShape
            logo: m.meta.logo
            background: m.meta.background
        }
    }
end sub

' The generic Play action: for a movie it is the only play path; for a series it
' covers the no-resume "Play S1E1" fallback. Both push stream selection.
sub PlayMedia()
    if m.stores = invalid then return
    if m.meta.type = "series"
        first = m.stores.episodes.callFunc("EpisodesFirstEpisode", m.meta)
        if first = invalid
            ' Sparse catalog records have no episode ids yet. Let the episode
            ' screen fetch them rather than inventing a possibly nonexistent id.
            OpenEpisodes()
            return
        end if
        m.top.pushRequest = {
            screen: "streamsScreen"
            params: {
            autoPlay: true
            seriesMeta: m.meta
                addonAddress: m.addonAddress
                metaType: m.meta.type
                metaId: m.meta.id
                videoId: m.stores.episodes.callFunc("EpisodesResolveVideoId", m.meta.id, first.season, first.episode, m.meta)
                season: first.season
                episode: first.episode
                position: ResumePosition()
            name: m.meta.name
            poster: m.meta.poster
            posterShape: m.meta.posterShape
            logo: m.meta.logo
            background: m.meta.background
            }
        }
    else
        ' Explicit Play owns the handoff; an unfinished source lookup continues
        ' in the Scene coordinator rather than being duplicated in Streams.
        m.prefetchContext = SourcePrefetch_Context(m.stores, DetailsPrefetchParams())
        SourcePrefetch_Prepare(m.top, m.prefetchContext)
        m.prefetchHandOff = true
        m.top.pushRequest = {
            screen: "streamsScreen"
            params: {
            autoPlay: true
            seriesMeta: m.meta
                addonAddress: m.addonAddress
                metaType: m.meta.type
                metaId: m.meta.id
                videoId: m.meta.id
                position: ResumePosition()
                name: m.meta.name
                poster: m.meta.poster
                posterShape: m.meta.posterShape
                logo: m.meta.logo
                background: m.meta.background
                description: m.meta.description
                runtime: m.meta.runtime
            }
        }
    end if
end sub

sub OpenEpisodes()
    m.top.pushRequest = {
        screen: "episodesScreen"
        params: {
            addonAddress: m.addonAddress
            meta: { id: m.meta.id, type: m.meta.type, name: m.meta.name, poster: m.meta.poster, posterShape: m.meta.posterShape, background: m.meta.background, logo: m.meta.logo }
            resume: m.resume
        }
    }
end sub

' Keep an accurate resume for the current meta: the saved position when the user
' came back from a spot, else zero (a brand-new start).
function ResumePosition() as integer
    if m.resume <> invalid and m.resume.position <> invalid then return m.resume.position
    return 0
end function

sub ToggleLibrary()
    if m.stores = invalid then return
    ' A meta from an add-on that ships no shape (or no poster) leaves those fields
    ' invalid. Every library boundary here is a typed string param, and Roku
    ' refuses to cast an explicitly-passed invalid (a default only fills in when
    ' the arg is OMITTED), so normalize once and reuse for both the save and the
    ' write-back packet MainScene turns into a typed LibraryBuildLibraryChangeItem.
    poster = ""
    if m.meta.poster <> invalid then poster = m.meta.poster
    posterShape = ""
    if m.meta.posterShape <> invalid then posterShape = m.meta.posterShape
    added = false
    if m.stores.library.callFunc("LibraryIsSaved", m.meta.id)
        m.stores.library.callFunc("LibraryRemoveSaved", m.meta.id)
    else
        m.stores.library.callFunc("LibraryAddSaved", m.meta.id, m.meta.type, m.meta.name, poster, posterShape)
        added = true
    end if
    label = LibraryActionLabel()
    for i = 0 to m.chips.Count() - 1
        if m.chips[i].action = "library"
            if m.chipsRow.content <> invalid and m.chipsRow.content.GetChildCount() > 0
                row = m.chipsRow.content.GetChild(0)
                if row <> invalid and i < row.GetChildCount() then row.GetChild(i).title = label
            end if
            exit for
        end if
    end for
    ' Publish the write-back packet. An add/remove only affects the account in a
    ' stremio session — a guest's library is local-only, so it stays silent
    ' (MainScene re-gates on the session; the screen keeps the payload
    ' stremio-only). The change appears in the local LibraryStore immediately
    ' either way, so the Library screen reflects it before the account does.
    if m.stores.library.callFunc("LibrarySessionType") = "stremio"
        m.top.libraryChange = {
            metaId: m.meta.id
            metaType: m.meta.type
            name: m.meta.name
            poster: poster
            added: added
        }
    end if
end sub

function LibraryActionLabel() as string
    if m.stores <> invalid and m.stores.library.callFunc("LibraryIsSaved", m.meta.id) then return "In library"
    return "Add to library"
end function

function TypeLabel(metaType as string) as string
    if metaType = "movie" then return "Movie"
    if metaType = "series" then return "Series"
    return metaType
end function

function OnExit() as void
    CancelMetaLoad()
    SourcePrefetch_Cancel(m.top, m.prefetchContext)
    if m.prefetchTimer <> invalid then m.prefetchTimer.control = "stop"
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
    if m.prefetchTimer <> invalid then m.prefetchTimer.control = "stop"
    m.prefetchDeadline = 0
    if m.prefetchHandOff <> true then SourcePrefetch_Cancel(m.top, m.prefetchContext)
    m.prefetchHandOff = false
end sub
