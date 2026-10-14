' StoreHost — the single owner of the app's data layer.
'
' Every store instance in this app is built HERE, once, and nowhere else. The
' store classes are plain bsc classes: an instance is an roAssociativeArray
' whose members are function references, and Roku copies that array the moment
' it crosses a component boundary — as a callFunc argument, a callFunc return
' or a declared interface field — dropping every function member. That is why
' screens could never hold a store: the copy arrived data-only and the first
' method call died with &hf4 "Member function not found".
'
' So nothing here is ever handed out. What crosses is this NODE, which Roku
' passes by reference, and what comes back over callFunc is plain data only:
' strings, numbers, booleans, arrays and assoc arrays of records. The classes
' are unchanged and still unit-tested in source/stores; this file only
' re-exports the surface the components actually use, one line per entry point.
'
' The pattern is the one the task components already use (see
' AddonsInstallTask.xml): include the store sources into the component that
' needs them and call them there. Those tasks can afford their own instance
' because they are stateless per-request wrappers; the session-aware stores
' below are not, which is exactly why they live in one place and are handed
' around as a node.

sub init()
    http = Transport()
    ' The session type is settled from the auth store BEFORE the facade is
    ' built, because the two session-aware stores below are constructed for one
    ' concrete session and must never see a blank one.
    ' The locals are named away from the classes and the function they collide
    ' with: BrightScript identifiers are case-insensitive, so a local called
    ' authStore IS the class AuthStore to the compiler, and a local called
    ' sessionType IS the function EffectiveSessionType below.
    auth = AuthStore(CreateObject("roRegistrySection", "auth"))
    bootSession = "guest"
    if auth.GetSession() = "stremio" then bootSession = "stremio"

    m.stores = {
        transport: http
        settings: SettingsStore(CreateObject("roRegistrySection", "settings"))
        auth: auth
        addons: AddonsStore(http, CreateObject("roRegistrySection", "addons"), bootSession)
        catalog: CatalogStore(http)
        episodes: EpisodesStore(http)
        library: LibraryStore(CreateObject("roRegistrySection", "library"), bootSession)
        playback: PlaybackStore(http)
        time: TimeUtil()
        watch: WatchStateBuffer()
    }

    ' The session-aware stores. Long-lived — never reconstructed, only
    ' re-targeted by SwitchSession — so a new session-aware store joins this one
    ' list and every auth flow reconciles it automatically.
    m.sessionAware = [m.stores.addons, m.stores.library]
    ' Only fixed labels and counts: never print configured addresses or credentials.
    savedProviders = 0
    for each addon in m.stores.addons.GetAll()
        if m.stores.addons.HasResource(addon.resources, "stream") then savedProviders = savedProviders + 1
    end for
    print "[setup] restored stream providers: "; savedProviders; " audio preset: "; m.stores.settings.GetAudioMode()
end sub

' The store session derives from the persisted auth session: guest when logged
' out or in a guest session, stremio for an account session. Never blank — the
' session-aware stores always act on a concrete session's data. This is the only
' place the answer is computed; the Scene and the stores all read it from here.
'
' The name is EffectiveSessionType and not SessionType for a reason that cost a
' build: every script in a component shares one function namespace and
' BrightScript identifiers are case-insensitive, so a function called
' SessionType here made every store's `sessionType` parameter collide with it,
' and bsc reported BS1104 in AddonsStore.bs — four files from the cause.
function EffectiveSessionType() as string
    if m.stores.auth.GetSession() = "stremio" then return "stremio"
    return "guest"
end function

' The one place a session change reaches the session-aware stores, so login,
' logout and guest-continuation can never leave one of them on the old session.
sub SwitchSession(newSession as string)
    for each store in m.sessionAware
        store.SwitchSession(newSession)
    end for
end sub

' LibraryStore keeps its session type as state rather than deriving it, so a
' screen that needs it asks here instead of reaching into the instance.
function LibrarySessionType() as string
    return m.stores.library.sessionType
end function

' addons.Get
function AddonsGet(id as string) as dynamic
    return m.stores.addons.Get(id)
end function

' addons.GetAll
function AddonsGetAll() as object
    return m.stores.addons.GetAll()
end function

' addons.HasResource
function AddonsHasResource(resources as dynamic, name as string) as boolean
    return m.stores.addons.HasResource(resources, name)
end function

' addons.HasType
function AddonsHasType(types as dynamic, metaType as string) as boolean
    return m.stores.addons.HasType(types, metaType)
end function

' addons.SupportsResource — the stream provider gate. Only the fields the
' matcher needs cross the boundary; the record's catalogs stay behind.
function AddonsSupportsResource(resources as dynamic, types as dynamic, idPrefixes as dynamic, name as string, metaType as string, id as string) as boolean
    return m.stores.addons.SupportsResource(resources, types, idPrefixes, name, metaType, id)
end function

' addons.CatalogCapabilities
function AddonsCatalogCapabilities(catalog as dynamic) as object
    return m.stores.addons.CatalogCapabilities(catalog)
end function

' addons.CatalogTitle
function AddonsCatalogTitle(catalog as dynamic, addonName as dynamic) as string
    return m.stores.addons.CatalogTitle(catalog, addonName)
end function

' addons.IsBuiltin
'
' Rank providers on this, never on a record's builtin flag: the account sync
' stamps every record it adopts with builtin: false, so on a stremio session the
' flag is a constant while the id is not.
function AddonsIsBuiltin(id as string) as boolean
    return m.stores.addons.IsBuiltin(id)
end function

' addons.InstallFromDescriptor
function AddonsInstallFromDescriptor(transportUrl as dynamic, manifest as dynamic) as object
    return m.stores.addons.InstallFromDescriptor(transportUrl, manifest)
end function

' addons.Register
function AddonsRegister(record as object) as boolean
    return m.stores.addons.Register(record)
end function

' addons.Uninstall
function AddonsUninstall(id as string, builtin = false as boolean) as boolean
    return m.stores.addons.Uninstall(id, builtin)
end function

' auth.GetAuthKey
function AuthGetAuthKey() as string
    return m.stores.auth.GetAuthKey()
end function

' auth.GetSession
function AuthGetSession() as string
    return m.stores.auth.GetSession()
end function

' auth.GetUser
function AuthGetUser() as dynamic
    return m.stores.auth.GetUser()
end function

' auth.IsLoggedIn
function AuthIsLoggedIn() as boolean
    return m.stores.auth.IsLoggedIn()
end function

' auth.LoginGuest
function AuthLoginGuest() as object
    return m.stores.auth.LoginGuest()
end function

' auth.LoginStremio
function AuthLoginStremio(authKey as string, user as dynamic) as object
    return m.stores.auth.LoginStremio(authKey, user)
end function

' auth.Logout
function AuthLogout() as void
    m.stores.auth.Logout()
end function

' episodes.EpisodesForSeason
function EpisodesEpisodesForSeason(meta as object, season as integer) as object
    return m.stores.episodes.EpisodesForSeason(meta, season)
end function

function EpisodesFirstEpisode(meta as dynamic) as dynamic
    return m.stores.episodes.FirstEpisode(meta)
end function

' episodes.MergeMeta
function EpisodesMergeMeta(provided as object, fetched as object) as object
    return m.stores.episodes.MergeMeta(provided, fetched)
end function

' episodes.NeedsMetaFetch
function EpisodesNeedsMetaFetch(meta as object) as boolean
    return m.stores.episodes.NeedsMetaFetch(meta)
end function

' episodes.OrderedSeasons
function EpisodesOrderedSeasons(allSeasons as object) as object
    return m.stores.episodes.OrderedSeasons(allSeasons)
end function

' episodes.OrderedVideoIds
function EpisodesOrderedVideoIds(seriesId as string, meta as object) as object
    return m.stores.episodes.OrderedVideoIds(seriesId, meta)
end function

' episodes.ResolveVideoId
function EpisodesResolveVideoId(seriesId as string, season as integer, episode as integer, meta = invalid as dynamic) as string
    return m.stores.episodes.ResolveVideoId(seriesId, season, episode, meta)
end function

' episodes.Seasons
function EpisodesSeasons(meta as object) as object
    return m.stores.episodes.Seasons(meta)
end function

' library.AddSaved
function LibraryAddSaved(metaId as string, metaType as string, name as string, poster = "" as string, posterShape = "" as string, metadataProviderKey = "" as string) as boolean
    return m.stores.library.AddSaved(metaId, metaType, name, poster, posterShape, metadataProviderKey)
end function

' library.BuildLibraryChangeItem
function LibraryBuildLibraryChangeItem(metaId as string, metaType as string, name as string, poster as string, added as boolean, now = "" as string) as dynamic
    return m.stores.library.BuildLibraryChangeItem(metaId, metaType, name, poster, added, now)
end function

' library.BuildWatchStateItem
function LibraryBuildWatchStateItem(packet as dynamic, now = "" as string) as dynamic
    return m.stores.library.BuildWatchStateItem(packet, now)
end function

' library.BuildWatchedStateItem
function LibraryBuildWatchedStateItem(packet as dynamic, now = "" as string) as dynamic
    return m.stores.library.BuildWatchedStateItem(packet, now)
end function

' library.ContinueWatching
function LibraryContinueWatching() as object
    return m.stores.library.ContinueWatching()
end function

' library.EpisodeMark
function LibraryEpisodeMark(metaId as string, season as integer, ep as object, orderedEpisodes as object, nowIso as dynamic) as object
    return m.stores.library.EpisodeMark(metaId, season, ep, orderedEpisodes, nowIso)
end function

' library.IsSaved
function LibraryIsSaved(metaId as string) as boolean
    return m.stores.library.IsSaved(metaId)
end function

' library.LibraryView
function LibraryLibraryView(typeFilter as string, sort as string) as object
    return m.stores.library.LibraryView(typeFilter, sort)
end function

' library.MarkAllIfDone
function LibraryMarkAllIfDone(metaId as string, anyRegular as boolean, allDone as boolean) as void
    m.stores.library.MarkAllIfDone(metaId, anyRegular, allDone)
end function

' library.MarkEpisodeUnwatched
function LibraryMarkEpisodeUnwatched(metaId as string, videoId as string) as void
    m.stores.library.MarkEpisodeUnwatched(metaId, videoId)
end function

' library.MarkEpisodeWatched
function LibraryMarkEpisodeWatched(metaId as string, videoId as string) as void
    m.stores.library.MarkEpisodeWatched(metaId, videoId)
end function

' library.MarkUpToUnwatched
function LibraryMarkUpToUnwatched(metaId as string, orderedEpisodeIds as object, lastIndex as integer) as void
    m.stores.library.MarkUpToUnwatched(metaId, orderedEpisodeIds, lastIndex)
end function

' library.MarkUpToWatched
function LibraryMarkUpToWatched(metaId as string, orderedEpisodeIds as object, lastIndex as integer) as void
    m.stores.library.MarkUpToWatched(metaId, orderedEpisodeIds, lastIndex)
end function

' library.MarkWatchedIfFinished
function LibraryMarkWatchedIfFinished(metaId as string, videoId as string, position as integer, duration as integer) as void
    m.stores.library.MarkWatchedIfFinished(metaId, videoId, position, duration)
end function

' library.ProgressFraction
function LibraryProgressFraction(metaId as string) as dynamic
    return m.stores.library.ProgressFraction(metaId)
end function

' library.RemoveSaved
function LibraryRemoveSaved(metaId as string) as boolean
    return m.stores.library.RemoveSaved(metaId)
end function

' library.ResumeFor
function LibraryResumeFor(metaId as string) as dynamic
    return m.stores.library.ResumeFor(metaId)
end function

' library.IsChannelType
function LibraryIsChannelType(metaType as string) as boolean
    return m.stores.library.IsChannelType(metaType)
end function

' library.SetPosition
function LibrarySetPosition(videoId as string, metaId as string, metaType as string, season as integer, episode as integer, name as string, poster = "" as string, position = 0 as integer, duration = 0 as integer, posterShape = "" as string, metadataProviderKey = "" as string) as void
    m.stores.library.SetPosition(videoId, metaId, metaType, season, episode, name, poster, position, duration, posterShape, metadataProviderKey)
end function

' library.SyncFromStremio
function LibrarySyncFromStremio(items as dynamic) as void
    m.stores.library.SyncFromStremio(items)
end function

' library.WatchedGlyph
function LibraryWatchedGlyph(metaId as string, metaType as string) as string
    return m.stores.library.WatchedGlyph(metaId, metaType)
end function

' settings.ClearServerAddress
function SettingsClearServerAddress() as void
    m.stores.settings.ClearServerAddress()
end function

' settings.GetLanguage
function SettingsGetLanguage() as string
    return m.stores.settings.GetLanguage()
end function

function SettingsGetAudioMode() as string
    return m.stores.settings.GetAudioMode()
end function

function SettingsGetPlaybackOptions() as object
    return m.stores.settings.GetPlaybackOptions()
end function

function SettingsGetProviderPriority() as object
    return m.stores.settings.GetProviderPriority()
end function

function SettingsSetPreferredProviderKey(value as string) as boolean
    return m.stores.settings.SetPreferredProviderKey(value)
end function

function SettingsRecordWorkingProviderKey(value as string) as boolean
    return m.stores.settings.RecordWorkingProviderKey(value)
end function

function SettingsSetPlaybackOption(optionName as string, value as boolean) as boolean
    return m.stores.settings.SetPlaybackOption(optionName,value)
end function

function SettingsSetAudioMode(value as string) as boolean
    return m.stores.settings.SetAudioMode(value)
end function

' settings.GetServerAddress
function SettingsGetServerAddress() as string
    return m.stores.settings.GetServerAddress()
end function

' settings.SaveFailed
function SettingsSaveFailed() as boolean
    return m.stores.settings.SaveFailed()
end function

' settings.SetLanguage
function SettingsSetLanguage(value as string) as boolean
    return m.stores.settings.SetLanguage(value)
end function

' settings.SetServerAddress
function SettingsSetServerAddress(url as string) as boolean
    return m.stores.settings.SetServerAddress(url)
end function

' time.NowIso
function TimeNowIso() as string
    return m.stores.time.NowIso()
end function

' time.AirDateLabel — the one-line air date for an episode ("Aired Aug 5, 2026"
' or "Premieres Sep 30, 2026", "" when the record has none).
function TimeAirDateLabel(ep as object) as string
    return m.stores.time.AirDateLabel(ep)
end function

' watch.Latest
function WatchLatest() as dynamic
    return m.stores.watch.Latest()
end function

' watch.Record
function WatchRecord(packet as dynamic) as void
    m.stores.watch.Record(packet)
end function
