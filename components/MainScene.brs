' Thin orchestrator.
'
' MainScene owns exactly three things and nothing else:
'   1. the ScreenStack,
'   2. Back routing (top screen first; the stack pops when it declines),
'   3. store instantiation and action dispatch.
'
' Zero business logic lives here. Everything else is in a screen or a store.
sub init()
    m.stack = ScreenStack(m.top)
    m.top.palette = AppPalette()

    m.homeScreen = m.top.FindNode("homeScreen")
    m.homeScreen.ObserveField("pushRequest", "onHomeAction")

    ' AuthScreen publishes the first-run choice (continue as guest, or log in
    ' with Stremio). The Scene signs the session in, points the session-aware
    ' stores at the right data and pops the gate — or starts the link-code flow.
    m.authScreen = m.top.FindNode("authScreen")
    m.authScreen.ObserveField("pushRequest", "onAuthAction")

    ' LinkStremioScreen publishes the pairing outcome: completeLogin (authKey +
    ' user) or cancelLogin (user backed out). The Scene owns the LinkStremioTask
    ' lifecycle; LinkStremioScreen only observes it and reports.
    m.linkStremioScreen = m.top.FindNode("linkStremioScreen")
    m.linkStremioScreen.ObserveField("pushRequest", "onLinkCodeAction")

    ' Details pushes its own actions (episode selection, movie Play) up through
    ' the same one-action channel Home uses.
    m.detailsScreen = m.top.FindNode("detailsScreen")
    m.detailsScreen.ObserveField("pushRequest", "onDetailsAction")
    ' Add/remove toggles from Details report through libraryChange; see
    ' onLibraryChange for the write-back pipeline.
    m.detailsScreen.ObserveField("libraryChange", "onLibraryChange")

    ' EpisodesScreen (the series episode browser) reports episode selections
    ' through the same one-action channel.
    m.episodesScreen = m.top.FindNode("episodesScreen")
    m.episodesScreen.ObserveField("pushRequest", "onEpisodesAction")
    ' Watched-status edits from the episode browser report through watchedChange;
    ' see onWatchedChange for the write-back pipeline.
    m.episodesScreen.ObserveField("watchedChange", "onWatchedChange")

    ' StreamsScreen reports the player push after a stream is resolved; the
    ' player itself never pushes — Back pops it. The player reports the positions
    ' it reaches through watchStateUpdate, so the Scene watches that one field;
    ' its own pushes are its business (it declines and the stack pops).
    m.streamsScreen = m.top.FindNode("streamsScreen")
    m.streamsScreen.ObserveField("pushRequest", "onStreamsAction")
    m.playerScreen = m.top.FindNode("playerScreen")
    m.playerScreen.ObserveField("watchStateUpdate", "onWatchStateUpdate")
    m.playerScreen.ObserveField("nextEpisodeRequest", "onNextEpisodeRequest")
    m.playerScreen.ObserveField("sourceRecoveryRequest","onSourceRecoveryRequest")

    ' SettingsScreen, AddonsScreen and SearchScreen are content-focused (no
    ' pushes of their own; Search pushes Details like the others). SearchScreen
    ' reports its pushes through its own channel. The exception is Settings'
    ' session rows: a guest can start the Stremio login from here, and a stremio
    ' user can log out — both are auth flows the Scene owns, so Settings reports
    ' them through its own channel too.
    m.settingsScreen = m.top.FindNode("settingsScreen")
    m.settingsScreen.ObserveField("pushRequest", "onSettingsAction")
    m.addonsScreen = m.top.FindNode("addonsScreen")
    m.addonsScreen.ObserveField("pushRequest","onAddonsAction")
    m.addonHealthScreen = m.top.FindNode("addonHealthScreen")
    m.aboutScreen = m.top.FindNode("aboutScreen")
    m.searchScreen = m.top.FindNode("searchScreen")
    m.searchScreen.ObserveField("pushRequest", "onSearchAction")
    m.discoverScreen = m.top.FindNode("discoverScreen")
    m.discoverScreen.ObserveField("pushRequest", "onDiscoverAction")
    m.libraryScreen = m.top.FindNode("libraryScreen")
    m.libraryScreen.ObserveField("pushRequest", "onLibraryAction")
    m.uiRoot = m.top.FindNode("uiRoot")
    m.top.FindNode("background").color = Theme().screenBg

    ' "Is an account write-back worker in flight" for the single stremio pump.
    ' It MUST be initialized here, not lazily, and this is not a style
    ' preference: a field that was never assigned reads back as invalid, and
    ' Roku refuses a truthiness test on invalid with &h18 ("Invalid is used in
    ' IF-clause") on the render thread. The pump reads it on its first line,
    ' before anything writes it, so an uninitialized flag is a guaranteed crash
    ' the first time a push runs.
    '
    ' The brs test interpreter treats `if invalid` as false, so the suite is
    ' structurally blind to this and a green run is not evidence either way. That
    ' is what made the missing initialization survive review: it presented on
    ' device as an unrecoverable app-wide hang when the player published a
    ' position on pause or on leave, because the throw landed inside the player's
    ' Video "state" observer and could not even paint a debugger prompt.
    InitAccountWork()
    m.pushingLibraryWrite = false

    ' The watch-state push is launched off a timer, not off the publisher that
    ' reports it: the publisher is the player's Video "state" observer, and a
    ' node created on that stack wedges the player (see ScheduleWatchStatePush).
    m.watchStatePump = m.top.FindNode("watchStatePump")
    m.watchStatePump.ObserveField("fire", "onWatchStatePumpFire")
    m.persistenceTick = m.top.FindNode("persistenceTick")
    m.persistenceTick.ObserveField("fire","onPersistenceTick")
    m.persistenceTick.control = "start"
    ' Settings can start the link-code flow; logout reuses the pairing worker.
    ' Both flags are session-flow state with no store counterpart.
    m.loginFromSettings = false
    m.logoutTask = invalid
    m.pendingLogout = false
    ' A library sync asked for while the add-on sync is still running is deferred
    ' to that sync's completion: both are launched together at startup and the
    ' device refuses too many NEW concurrent connections. See StartLibrarySync.
    ' Initialized here for the same &h18 reason as the flags above.
    m.pendingLibrarySync = false
    ' A revoked-account bounce fires at most once per login: both launch-time
    ' pulls (library + addon) fail together on a dead authKey, and only the
    ' first one tears the session down.
    m.revokedSessionHandled = false

    ' Bottom-of-stack Back opens the native exit dialog through the Scene's dialog
    ' field (a StandardDialog) rather than using the ScreenStack.
    '
    ' Both custom dialogs are BUILT HERE rather than declared as children in the
    ' markup. The three StandardMessageDialogs (delete add-on, ECP sent, session
    ' revoked) are created in code and every one of them renders. The two custom
    ' ones declared as Scene children dimmed the background and took focus —
    ' blind OK on the Exit button still fired buttonSelected — but painted
    ' nothing at all, which rules out a broken component: their side card, QR
    ' and palette are the same code either way. The declaration was the only
    ' thing that differed. Keep the reference: a CreateObject'd node that
    ' nothing holds can be collected while it is on screen.
    m.confirmExit = CreateObject("roSGNode", "ConfirmExitDialog")
    m.confirmExit.id = "confirmExitDialog"
    m.confirmExit.ObserveFieldScoped("wasClosed", "onExitDialogClosed")

    ' The support modal is another native dialog; the Scene owns it and decides
    ' which platform to show. Both dialogs dismiss through wasClosed.
    m.supportDialog = CreateObject("roSGNode", "SupportDialog")
    m.supportDialog.id = "supportDialog"
    m.supportDialog.ObserveFieldScoped("wasClosed", "onSupportDialogClosed")

    ' The whole data layer lives in ONE component — StoreHost — which builds
    ' every store instance exactly once and never lets one leave. A bsc class
    ' instance is an roAssociativeArray whose members are function references,
    ' and Roku copies that array the moment it crosses a component boundary (as
    ' a callFunc argument, a callFunc return or a declared interface field),
    ' dropping every function member — so a screen handed a store held a
    ' data-only copy and its first method call died with &hf4 "Member function
    ' not found". Three architectures failed on that one fact before this one.
    '
    ' What crosses instead is the StoreHost NODE, which Roku passes by reference
    ' — the same mechanism the pairing task already uses through the declared
    ' taskNode field — and what comes back over callFunc is plain data only:
    ' strings, numbers, booleans, arrays and assoc arrays of records. A screen
    ' asks for a value and receives a value; no store instance is ever in
    ' flight, so there is nothing left to strip.
    '
    ' This is the pattern the task components already follow (see
    ' AddonsInstallTask.xml): include the store sources into the component that
    ' needs them and call them there. Those can afford a private instance
    ' because they are stateless per-request wrappers; the session-aware stores
    ' cannot, which is why they are built once, here, and shared as a node.
    '
    ' Created before the binds below and never replaced: a session switch
    ' re-targets the session-aware stores in place through SwitchSession.
    m.storeHost = CreateObject("roSGNode", "StoreHost")
    m.top.AppendChild(m.storeHost)

    ' The store-fault strip: a red bar plus its label, both flat children of the
    ' Scene, created once up front and updated in place. No nesting, no
    ' FindNode after an append, no string join — every way the first version
    ' could come up with a blank label while the bar itself still painted. A
    ' screen that cannot reach the data layer reports the failing hop here (see
    ' Screen.brs's SetStores) rather than leaving an empty grid and a
    ' "0 add-ons" that reads like an empty catalog. 0 is impossible with a live
    ' store: a guest session's GetAll() returns the two built-in seeds.
    m.faultBar = CreateObject("roSGNode", "Rectangle")
    m.faultBar.width = 1920
    m.faultBar.height = 80
    m.faultBar.translation = [0, 1000]
    m.faultBar.color = Theme().danger
    m.faultBar.visible = false
    m.top.AppendChild(m.faultBar)

    m.faultText = CreateObject("roSGNode", "Label")
    m.faultText.translation = [40, 1020]
    m.faultText.width = 1840
    m.faultText.height = 44
    m.faultText.font = "font:MediumBoldSystemFont"
    m.faultText.color = Theme().textWhite
    m.faultText.visible = false
    m.top.AppendChild(m.faultText)

    ' The keys the last add-on sync published into the strip. Held so a later
    ' sync can retract exactly what it published: the reason strings carry the
    ' transport's error text, so a clear-by-same-text would leave a stale line
    ' up whenever the wording changed.
    m.addonSyncFaults = []
    RestoreAccountWrites()

    m.homeScreen.callFunc("SetStores", m.storeHost, m.top)
    m.authScreen.callFunc("SetStores", m.storeHost, m.top)
    m.linkStremioScreen.callFunc("SetStores", m.storeHost, m.top)
    m.detailsScreen.callFunc("SetStores", m.storeHost, m.top)
    m.episodesScreen.callFunc("SetStores", m.storeHost, m.top)
    m.streamsScreen.callFunc("SetStores", m.storeHost, m.top)
    m.settingsScreen.callFunc("SetStores", m.storeHost, m.top)
    m.addonsScreen.callFunc("SetStores", m.storeHost, m.top)
    m.addonHealthScreen.callFunc("SetStores", m.storeHost, m.top)
    m.aboutScreen.callFunc("SetStores", m.storeHost, m.top)
    m.searchScreen.callFunc("SetStores", m.storeHost, m.top)
    m.discoverScreen.callFunc("SetStores", m.storeHost, m.top)
    m.libraryScreen.callFunc("SetStores", m.storeHost, m.top)
    m.playerScreen.callFunc("SetStores", m.storeHost, m.top)
end sub

' A screen whose store bind came up short reports it here, and the Scene paints
' it. Every way that hand-off can fail looks identical from the outside — an
' empty grid, a "0 add-ons" subtitle, no crash, nothing in the device log — and
' that silence is what hid two shipping bugs (the callFunc argument that arrived
' without its methods, then getScene() returning invalid because init() runs
' before Show()). The Scene owns the strip because it owns the cross-cutting UI
' and has the palette; a screen that painted its own would need a color literal
' it deliberately does not depend on.
'
' Faults are keyed by reason, not by screen: the four failures are exactly the
' things worth reading, and a dozen screens hitting the same one should not
' produce a dozen identical lines. active=false clears.
sub ReportStoreFault(reason as string, active as boolean)
    if reason = "" then return
    if m.storeFaults = invalid then m.storeFaults = {}
    if active then
        m.storeFaults[reason] = true
    else
        m.storeFaults.Delete(reason)
    end if
    RefreshStoreFaultStrip()
end sub

' One bar and one label, both created in init() and updated in place, so this
' only ever writes two fields on nodes the Scene already holds. Sorted so the
' same set of faults always reads the same way — an unordered key walk would
' shuffle the lines between binds.
'
' The first version shipped one line that did all three of the things this
' avoids: strip.FindNode("storeFaultText").text = reasons.Join("     ") — a
' strip built lazily, a Label written through a FindNode after the append, and
' the line joined. On device the bar painted and the label stayed blank. Which
' of the three was at fault was never isolated, so none of the three shapes
' come back. m.linkLabel.text = link in LinkStremioScreen is the shape known to
' work here, so this is that shape.
sub RefreshStoreFaultStrip()
    line = ""
    if m.storeFaults <> invalid
        reasons = []
        for each key in m.storeFaults
            reasons.Push(key)
        end for
        reasons.Sort()
        for each reason in reasons
            if line <> "" then line = line + "     "
            line = line + reason
        end for
    end if
    if line = "" then
        m.faultBar.visible = false
        m.faultText.visible = false
        return
    end if
    m.faultText.text = line
    m.faultText.visible = true
    m.faultBar.visible = true
end sub

' The only action channel from Home: one push request, dispatched by the stack.
' Dialogs (the support modal) are a special case routed through scene.dialog
' instead. No business logic — the Scene stays a thin orchestrator.
sub onHomeAction()
    request = m.homeScreen.pushRequest
    if request = invalid or request.screen = invalid then return
    if request.dialog = true
        ShowSupportDialog()
        return
    end if
    m.stack.push(request.screen, request.params)
end sub

' Details' action channel; same one-action routing.
sub onDetailsAction()
    request = m.detailsScreen.pushRequest
    if request = invalid or request.screen = invalid then return
    m.stack.push(request.screen, request.params)
end sub

' EpisodesScreen's action channel; same one-action routing.
sub onEpisodesAction()
    request = m.episodesScreen.pushRequest
    if request = invalid or request.screen = invalid then return
    m.stack.push(request.screen, request.params)
end sub

' SearchScreen's action channel; same one-action routing.
sub onSearchAction()
    request = m.searchScreen.pushRequest
    if request = invalid or request.screen = invalid then return
    m.stack.push(request.screen, request.params)
end sub

sub onAddonsAction()
    request = m.addonsScreen.pushRequest
    if Type(request) <> "roAssociativeArray" then return
    if request.screen = "addonHealthScreen" then m.stack.push("addonHealthScreen",request.params)
end sub

' DiscoverScreen's action channel; same one-action routing.
sub onDiscoverAction()
    request = m.discoverScreen.pushRequest
    if request = invalid or request.screen = invalid then return
    m.stack.push(request.screen, request.params)
end sub

' LibraryScreen's action channel; same one-action routing.
sub onLibraryAction()
    request = m.libraryScreen.pushRequest
    if request = invalid or request.screen = invalid then return
    m.stack.push(request.screen, request.params)
end sub

' SettingsScreen's session rows route here: the linked login is the same
' link-code flow as the AuthScreen start, while logout goes through a confirm
' dialog then the teardown in DoLogout. No business logic — the Scene stays a
' thin orchestrator.
sub onSettingsAction()
    request = m.settingsScreen.pushRequest
    if Type(request) = "roAssociativeArray"
        if request.screen = "addonHealthScreen" or request.screen = "aboutScreen"
            m.stack.push(request.screen,request.params)
            return
        end if
    end if
    if request = invalid or request.action = invalid then return
    if request.action = "retryDeviceSaves" then RetryDeviceSaves():return
    if request.action = "retryAccountWrites" then RetryAccountWrites():return
    if request.action = "login"
        m.loginFromSettings = true
        StartLinkCodeFlow()
    else if request.action = "logout"
        ShowLogoutConfirm()
    end if
end sub

' StreamsScreen's action channel; same one-action routing as every other screen.
sub onStreamsAction()
    request = m.streamsScreen.pushRequest
    if request = invalid or request.screen = invalid then return
    m.stack.push(request.screen, request.params)
end sub

' Replace the existing episode's source list instead of growing the stack with
' duplicate static Player/Streams nodes on every episode. Fired from a Timer.
sub onNextEpisodeRequest()
    request = m.playerScreen.nextEpisodeRequest
    if Type(request) <> "roAssociativeArray" or Type(request.params) <> "roAssociativeArray" then return
    shown = m.stack.top()
    if shown = invalid or shown.id <> "playerScreen" then return
    if request.params.metaType <> "series" then return
    if m.playerScreen.callFunc("CanAdvanceEpisode", request.videoId) <> true then return
    if not m.stack.pop() then return
    shown = m.stack.top()
    if shown <> invalid and shown.id = "streamsScreen"
        shown.node.callFunc("OnEnter", request.params)
    else
        m.stack.push("streamsScreen", request.params)
    end if
end sub

' The player published a position update (pause or leave) through
' watchStateUpdate. It is one of the three account edits MainScene funnels into
' the single write-back pump (see PumpLibraryWrites). Here: gate on a stremio
' session (guest never touches the API), drop a repeat of the last accepted
' update (same video, same position — nothing new), and record the rest in the
' per-item queue. The packet is read from the shared watch-state buffer, not the
' player node, so the deferred pump can still build after the player is popped.
sub onWatchStateUpdate()
    if m.storeHost = invalid then return
    if m.storeHost.callFunc("AuthGetSession") <> "stremio" then return
    packet = m.storeHost.callFunc("WatchLatest")
    if packet = invalid then return
    videoId = packet.videoId
    if videoId = invalid or videoId = "" then return
    if packet.position = invalid then return
    key = videoId + "|" + packet.position.ToStr()
    if m.lastPacketKey = key then return
    if not QueueAccountEdit("watchState",packet) then return
    m.lastPacketKey = key
    ScheduleWatchStatePush()
end sub

' The watch-state push is the one account edit the PLAYER triggers from inside a
' Video "state" observer: pausing reports "paused", leaving reports through
' SavePosition, and both end up writing the watchStateUpdate field that wakes
' this handler. So the stack under this call is the OS's own playback
' transition, and nothing that touches the SceneGraph may run on it.
'
' It used to. onWatchStateUpdate called the pump directly, which built a worker
' with CreateObject + AppendChild + control = "RUN" — inserting a node under a
' Video node mid-transition, on the render thread. The app stopped answering the
' remote entirely, and never recovered: pausing froze it, backing out of a
' frozen pause froze it the same way, and the only way out was killing the
' channel. It looked like a media or stream fault and was not one at all — it
' reproduced on a stream from the user's own server, and never in a guest
' session, because a guest session returns at the AuthGetSession gate above and
' never reaches the launch. Only a stremio session got far enough to wedge.
'
' So the packet is RECORDED here and the push starts one tick later, off the
' timer, after the transition has settled. That is safe to defer: the pump reads
' the packet out of the scene-owned queue, which lives past the player node, so a
' pump that fires after the player was already torn down still has what it needs.
sub ScheduleWatchStatePush()
    if m.watchStatePump = invalid then
        ' No timer to defer onto. Push inline rather than never — a missing timer
        ' is a wiring mistake, not a reason to drop the user's watch state.
        PumpLibraryWrites()
        return
    end if
    m.watchStatePump.control = "stop"
    m.watchStatePump.control = "start"
end sub

sub onWatchStatePumpFire()
    PumpLibraryWrites()
end sub

' The Details screen published an add/remove toggle through libraryChange.
sub onLibraryChange()
    if m.storeHost = invalid then return
    if m.storeHost.callFunc("AuthGetSession") <> "stremio" then return
    change = m.detailsScreen.libraryChange
    if change = invalid then return
    if not QueueAccountEdit("libraryChange",change) then return
    PumpLibraryWrites()
end sub

' The episode browser published a watched-mark/unmark edit through
' watchedChange. Each change carries the ordered episode-id list plus the meta
' identity, so the store can re-author the full bitfield and land a well-formed
' entry for a series the account has never seen.
sub onWatchedChange()
    if m.storeHost = invalid then return
    if m.storeHost.callFunc("AuthGetSession") <> "stremio" then return
    change = m.episodesScreen.watchedChange
    if change = invalid then return
    if not QueueAccountEdit("watched",change) then return
    PumpLibraryWrites()
end sub

' AccountWork.brs owns generation checks, the durable outbox and write pump.

' The exit dialog signals dismissal through wasClosed (Back, Home, or its own
' close field). Clear the Scene's dialog slot so the next Back presents it
' fresh, and hand focus back to Home. Only clear when the dialog is still
' the one shown.
sub onExitDialogClosed()
    if m.top.dialog <> invalid and m.top.dialog.id = "confirmExitDialog"
        m.top.dialog = invalid
    end if
    RestoreActiveScreenFocus()
end sub

' Present the support modal: pick the platform by the device's store region
' (Argentina → Cafecito, everywhere else → Buy Me a Coffee), configure the
' dialog, then show it through the Scene's dialog field.
sub ShowSupportDialog()
    m.supportDialog.callFunc("Configure", SupportPlatform())
    m.top.dialog = m.supportDialog
end sub

function SupportPlatform() as string
    device = CreateObject("roDeviceInfo")
    if device <> invalid and device.GetCountryCode() = "AR" then return "cafecito"
    return "buymeacoffee"
end function

sub onSupportDialogClosed()
    if m.top.dialog <> invalid and m.top.dialog.id = "supportDialog"
        m.top.dialog = invalid
    end if
    RestoreActiveScreenFocus()
end sub

' Focusing a screen's Group alone does not focus its interactive child. Each
' screen's declared OnEnter contract restores the appropriate list/keyboard.
' A different modal may have replaced the one whose close observer is firing;
' leave that modal's focus untouched. Playback must not be restarted here.
sub RestoreActiveScreenFocus()
    if m.top.dialog <> invalid or m.top.exitApp = true then return
    if m.stack = invalid then return
    active = m.stack.top()
    if active = invalid or active.node = invalid then return
    active.node.SetFocus(true)
    if active.id = "playerScreen"
        video = active.node.FindNode("video")
        if video <> invalid then video.SetFocus(true)
    else
        active.node.callFunc("OnEnter", invalid)
    end if
end sub

' Bootstrap the stack once the roSGScreen is shown. A field observer would not
' work here: Scene.visible is born true and never reassigned, so observing it
' never fires. Start() is deterministic, and pushing after Show() guarantees the
' tree is renderable when focus is handed out. The stack always rests on a
' bottom home screen; a not-logged-in launch parks the auth gate on top, so
' "Continue as guest" simply pops it to reveal the guest home.
sub Start()
    m.stack.push("homeScreen")
    if not m.storeHost.callFunc("AuthIsLoggedIn")
        m.stack.push("authScreen")
    else if EffectiveSessionType() = "stremio"
        ' Relaunched stremio session. Both pulls run every launch, for the same
        ' reason: the library is re-pulled because only the continue-watching
        ' stack persists, and the addon collection is re-pulled because a
        ' session whose stremio_addons key is empty has no catalogs at all —
        ' AddonsStore hides the built-in seeds for a stremio session, so nothing
        ' renders until the collection lands. See StartAddonSync for how a
        ' single failed login-time sync used to make that state permanent.
        StartAddonSync()
        StartLibrarySync()
    end if
end sub

' The store session derives from the persisted auth session: guest when logged
' out or in a guest session, stremio for an account session. Never blank — the
' session-aware stores always act on a concrete session's data. The host owns
' the auth store, so it owns the answer; asking for it here keeps one derivation
' instead of a second registry read in the Scene that could disagree.
function EffectiveSessionType() as string
    if m.storeHost <> invalid and m.storeHost.callFunc("EffectiveSessionType") = "stremio" then return "stremio"
    return "guest"
end function

' The one place a session change reaches the session-aware stores: the type is
' derived from the auth authority (never a call-site literal), so it always
' matches the session the store/service were just pivoted to, and every session
' gets the same switch. The host holds that list, so login, logout and
' guest-continuation cannot leave one of its stores on the old session by
' forgetting a fan-out here. Guest and stremio stay under separate registry keys
' with a clear-and-reload swap, so the two sessions never mix.
sub ReconcileSession()
    ResetAccountWork()
    if m.storeHost <> invalid then m.storeHost.callFunc("SwitchSession", EffectiveSessionType())
    RestoreAccountWrites()
    if m.homeScreen <> invalid then m.homeScreen.callFunc("RebuildRows")
end sub

' The AuthScreen published its first-run choice.
sub onAuthAction()
    request = m.authScreen.pushRequest
    if request = invalid then return
    if request.action = "continueGuest"
        if m.storeHost <> invalid then m.storeHost.callFunc("AuthLoginGuest")
        ReconcileSession()
        if m.stack.top() <> invalid and m.stack.top().id = "authScreen"
            m.stack.pop()
        end if
    else if request.action = "startLogin"
        StartLinkCodeFlow()
    end if
end sub

' Build the pairing worker, hand it to the LinkStremioScreen and start it. The
' task is created dynamically (like the player) so it lives exactly as long as
' the flow; teardown on success, Back or failure is handled in
' CleanupStremioPairTask. Publishes the fresh node through taskNode so the
' screen can (re)bind, resetting its spinner and countdown.
function NewPairingTask() as object
    task = CreateObject("roSGNode", "LinkStremioTask")
    task.id = NextAccountWorkerId("linkStremio")
    m.top.AppendChild(task)
    m.linkStremioTask = task
    m.linkStremioScreen.taskNode = task
    task.control = "RUN"
    return task
end function

' Start the link-code pairing: spawn the worker task, then push the pairing
' screen on top of whatever presented it (AuthScreen or Settings).
sub StartLinkCodeFlow()
    NewPairingTask()
    m.stack.push("linkStremioScreen")
end sub

' Request a new code while the pairing screen is already up: clear the old worker
' (freeing its thread and observer) and swap in a fresh one. No stack push — the
' screen stays put and rebinds through the taskNode field change.
sub RefreshLinkCode()
    CleanupStremioPairTask()
    NewPairingTask()
end sub

' The LinkStremioScreen published its outcome. completeLogin carries the paired
' authKey + user: persist the stremio session, repoint the session-aware stores
' and drop back to Home, cleaning up the flow. cancelLogin just washes out.
sub onLinkCodeAction()
    request = m.linkStremioScreen.pushRequest
    if request = invalid then return
    if request.action = "refreshCode"
        ' The screen stays up; only the worker is replaced.
        RefreshLinkCode()
        return
    end if
    if request.action = "completeLogin"
        if m.linkStremioTask = invalid or request.taskIdentity <> m.linkStremioTask.id then return
        if m.storeHost <> invalid
            login = m.storeHost.callFunc("AuthLoginStremio", request.authKey, request.user)
            if Type(login) = "roAssociativeArray" and login.persisted <> true then ReportStoreFault("Login is active for this session; device save failed.",true)
        end if
        ReconcileSession()
        m.revokedSessionHandled = false
        StartAddonSync()
        StartLibrarySync()
        if m.stack.top() <> invalid and m.stack.top().id = "linkStremioScreen"
            m.stack.pop()
        end if
        if m.stack.top() <> invalid and m.stack.top().id = "authScreen"
            m.stack.pop()
        end if
        if m.loginFromSettings and m.stack.top() <> invalid and m.stack.top().id = "settingsScreen"
            m.stack.pop()
        end if
        m.loginFromSettings = false
    end if
    CleanupStremioPairTask()
    if request.action = "cancelLogin" and m.stack.top() <> invalid and m.stack.top().id = "linkStremioScreen"
        m.stack.pop()
    end if
    if request.action = "cancelLogin" then m.loginFromSettings = false
end sub

' Reap the task: stop the worker, drop references and remove it from the tree.
' The STOP signal is the real cancel — the read-poll loop watches control and
' exits mid-sleep — because removing a running Task node does NOT kill its
' worker thread (a removed-but-running puller keeps polling, which showed up as
' the old link code being read alongside the new one after a refresh). Keep the
' removal too so the node is freed once the thread exits.
sub CleanupStremioPairTask()
    task = m.linkStremioTask
    m.linkStremioTask = invalid
    if task = invalid then return
    task.control = "STOP"
    if task.getParent() <> invalid then m.top.RemoveChild(task)
end sub

' Confirm before leaving the account: the confirm dialog is a StandardMessageDialog
' through the Scene's dialog field, mirroring the deep-link import dialog's close
' path (buttons only set buttonSelected; the dialog's own close field funnels into
' wasClosed so the Scene clears the slot).
sub ShowLogoutConfirm()
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.id = "logoutConfirmDialog"
    dialog.title = "Log out?"
    dialog.message = ["This signs the Stremio account out of this device. Account caches are removed from this device. Your Stremio library stays on your account; guest data stays separate."]
    dialog.buttons = ["Log out", "Cancel"]
    dialog.observeField("buttonSelected", "onLogoutChoice")
    dialog.observeField("wasClosed", "onLogoutDialogClosed")
    m.top.dialog = dialog
end sub

sub onLogoutChoice()
    if m.top.dialog <> invalid and m.top.dialog.id = "logoutConfirmDialog"
        ' Record the intent and let the dialog dismiss first: acting while the
        ' dialog still owns scene.dialog loses the focus race — a screen pushed
        ' now would render unfocused (the SceneGraph restores focus to the
        ' pre-dialog node when the slot finally clears). DoLogout runs in
        ' onLogoutDialogClosed, after the dialog is gone.
        m.pendingLogout = m.top.dialog.buttonSelected = 0
        m.top.dialog.close = true
    end if
end sub

' The logout dialog dismissed (Log out, Cancel, Back or Home). Clear the Scene's
' dialog slot, then act: a confirmed logout runs the teardown now that no dialog
' competes for focus (DoLogout's pushes land focused); otherwise focus returns to
' Settings.
sub onLogoutDialogClosed()
    if m.top.dialog <> invalid and m.top.dialog.id = "logoutConfirmDialog"
        m.top.dialog = invalid
    end if
    wasPending = m.pendingLogout
    m.pendingLogout = false
    if wasPending
        DoLogout()
    else if m.stack.top() <> invalid and m.stack.top().id = "settingsScreen"
        m.settingsScreen.SetFocus(true)
    end if
end sub

' The actual logout, on confirm: flush the account key at the API (best-effort,
' never gating), then the same teardown the revoked-session bounce runs. The
' server call is fire-and-forget — the user is logged out here regardless of its
' outcome.
sub DoLogout()
    if m.storeHost <> invalid and m.storeHost.callFunc("AuthGetAuthKey") <> ""
        task = AsyncTask_Launch(m.top, "LogoutTask", "onLogoutResult", {
            authKey: m.storeHost.callFunc("AuthGetAuthKey")
        }, "logoutTask")
        m.logoutTask = task
    end if

    ResetToAuthGate()
end sub

' Clear the local session, repoint the session-aware stores at the guest data,
' then walk the stack back to Home and park the auth gate on top so the user can
' pick their next session. Shared by the manual logout and the revoked-session
' bounce; the manual logout additionally flushes the authKey at the API first
' (see DoLogout).
sub ResetToAuthGate()
    if m.storeHost <> invalid then m.storeHost.callFunc("AuthLogout")
    ReconcileSession()

    ' Pop all the way down to Home — every screen gets its normal OnExit/BlurFocus
    ' teardown, so transient tasks cancel and no stale focus survives.
    while m.stack.count() > 1
        m.stack.pop()
    end while
    if m.homeScreen <> invalid then m.homeScreen.callFunc("RebuildRows")
    m.stack.push("authScreen")
end sub

' A launch-time pull reported that the account session no longer exists (it was
' deleted from the account's session list, or expired). The local authKey is
' dead, so there is no server logout to flush — drop to the guest gate exactly
' like the manual logout, and explain why. Guarded so the racing library/addon
' pulls can only bounce once.
sub HandleRevokedSession()
    if m.revokedSessionHandled then return
    m.revokedSessionHandled = true
    ' The session is being torn down; a launch-time library sync deferred behind
    ' the add-on sync has nothing left to pull.
    m.pendingLibrarySync = false
    ResetToAuthGate()
    ShowSessionRevokedDialog()
end sub

' Present the revoked-session dialog over the auth gate: one OK button down to
' choosing the next session, mirroring the deep-link import dialog's wiring.
sub ShowSessionRevokedDialog()
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.id = "sessionRevokedDialog"
    dialog.title = "Account session ended"
    dialog.message = ["Your Stremio account session was signed out from another device, you'll need to log back in."]
    dialog.buttons = ["OK"]
    dialog.observeField("buttonSelected", "onSessionRevokedButtonSelected")
    dialog.observeField("wasClosed", "onSessionRevokedDialogClosed")
    m.top.dialog = dialog
end sub

sub onSessionRevokedButtonSelected()
    if m.top.dialog <> invalid and m.top.dialog.id = "sessionRevokedDialog"
        m.top.dialog.close = true
    end if
end sub

sub onSessionRevokedDialogClosed()
    if m.top.dialog <> invalid and m.top.dialog.id = "sessionRevokedDialog"
        m.top.dialog = invalid
    end if
    if m.stack.top() <> invalid and m.stack.top().id = "authScreen"
        m.authScreen.SetFocus(true)
    end if
end sub

' The server logout settled. Reap the worker; the local session is already
' cleared, nothing to gate on.
sub onLogoutResult()
    task = m.logoutTask
    m.logoutTask = invalid
    if task = invalid then return
    AsyncTask_Reap(task, m.top, false)
end sub

' Kick the account addon sync for a stremio session. The API answers with the
' full collection incl. each manifest, so no per-addon fetches follow — the task
' returns the descriptors and MainScene adopts them through AddonsStore (the
' single writer for installed records). Created per sync like the pairing task.
'
' Runs at BOTH login and relaunch. It used to run only at login, on the strength
' of "a relaunched stremio session skips this (its addons are already in the
' stremio_addons registry key from the login that synced them)" — a claim about
' persisted state that nothing checked and that a single failed login-time sync
' made permanently false. The consequence was severe and silent: AddonsStore
' deliberately shows no built-in seeds for a stremio session, so an empty
' stremio_addons meant no Cinemeta, which meant every AddonsGet("com.linvo.
' cinemeta") caller got invalid — including MetaAddress(), so the Continue
' Watching row's Details fetch went out with an empty addon address and rendered
' a title with no poster and no description. The only recovery was to log out
' and re-pair the account. One idempotent GET is now the recovery.
sub StartAddonSync()
    if m.addonSyncTask <> invalid or m.storeHost = invalid then return
    if m.storeHost.callFunc("AuthGetSession") <> "stremio" then return
    fields = {accountGeneration:AccountGeneration()}
    if m.storeHost <> invalid then fields.authKey = m.storeHost.callFunc("AuthGetAuthKey")
    task = AsyncTask_Launch(m.top, "AddonSyncTask", "onAddonSyncResult", fields, NextAccountWorkerId("addonSync"), "onAddonSyncFinished")
    m.addonSyncTask = task
    m.addonSyncStatus = {state:"loading",text:"Syncing Stremio add-ons…",complete:false}
    RefreshAddonStatus()
end sub

' Reconcile one validated account snapshot, preserving the last usable state
' on failure. Changed configurations, removals and ordering apply together.
'
' An empty result is NOT one of those outcomes, and treating it as one is what
' broke first login. `result` is alwaysNotify with no value, so it can notify
' before the worker has written anything, and the handler cannot tell "not yet"
' from "the worker produced nothing" by looking at result alone. This sub used to
' call AsyncTask_Reap on an empty result — which unobserves the field and removes
' the node — and CleanupStremioPairTask's own header records that removing a
' running Task does NOT kill its worker thread. So the real result landed on a
' node nobody was watching, the account's add-ons were silently dropped, `added`
' stayed 0, RebuildRows never ran, and Home went on rendering the pre-login rows
' as though nothing had happened. The app looked healthy and was not.
'
' So an empty result is declined here and the node is left alone. The authority
' on whether the worker really finished without one is onAddonSyncFinished, which
' can only fire once the task's sentinel says the worker is done.
sub onAddonSyncResult(event = invalid as dynamic)
    task = m.addonSyncTask
    if not AccountResultCurrent(task,event) then return
    if task = invalid then return
    result = task.result
    if result = invalid then return
    if Type(result) <> "roAssociativeArray" then result = {ok:false}

    m.addonSyncTask = invalid
    AsyncTask_Reap(task, m.top, false)

    ClearAddonSyncFaults()

    ' Compared, not truthiness-tested: a result packet without the key reads
    ' back invalid, and `if invalid` is a hard &h18 crash on device.
    if result.revokedSession = true
        HandleRevokedSession()
        return
    end if

    if Type(result) <> "roAssociativeArray" or result.ok <> true
        m.addonSyncStatus = {state:"failed",text:"Stremio add-ons could not sync. Retry in Add-ons.",complete:false}
        AddAddonSyncFault(m.addonSyncStatus.text)
        RefreshAddonStatus()
        PumpPendingLibrarySync()
        return
    end if
    outcome = m.storeHost.callFunc("AddonsReconcileAccount",result.descriptors)
    if Type(outcome) <> "roAssociativeArray" then outcome = {applied:false,complete:false}
    m.addonSyncStatus = outcome
    m.addonSyncStatus.state = "failed"
    m.addonSyncStatus.text = "No usable account snapshot. Retry in Add-ons."
    if outcome.applied = true
        m.addonSyncStatus.state = "partial"
        m.addonSyncStatus.text = "Imported " + outcome.imported.ToStr() + " of " + outcome.received.ToStr() + " account entries"
        if outcome.complete = true
            m.addonSyncStatus.state = "complete"
            m.addonSyncStatus.text = m.addonSyncStatus.text + ". Sync complete."
            if outcome.received = 0 then m.addonSyncStatus.state = "empty":m.addonSyncStatus.text = "Your Stremio account has no add-ons."
        else
            m.addonSyncStatus.text = m.addonSyncStatus.text + ". Partial: " + outcome.unsupported.ToStr() + " unsupported, " + outcome.invalid.ToStr() + " invalid, " + outcome.limited.ToStr() + " over limits. Retry in Add-ons."
        end if
        if outcome.duplicates > 0 then m.addonSyncStatus.text = m.addonSyncStatus.text + " Duplicates skipped: " + outcome.duplicates.ToStr() + "."
        if outcome.persisted <> true then m.addonSyncStatus.state="unsaved":m.addonSyncStatus.text=m.addonSyncStatus.text+" Loaded for this session; device save failed."
        NotifyAddonChanges()
    end if
    if m.addonSyncStatus.state <> "complete" and m.addonSyncStatus.state <> "empty" then AddAddonSyncFault(m.addonSyncStatus.text)
    RefreshAddonStatus()
    PumpPendingLibrarySync()
end sub

' The worker's sentinel fired. The VALUE of the sentinel decides what that means,
' and that distinction is the entire reason this sub exists.
'
' An alwaysNotify field notifies once at ObserveField time, carrying whatever the
' field holds then — and field notifications are dispatched on the event loop, not
' at the moment the observer is attached. So the first "finished" notification is
' queued while AsyncTask_Launch is still on the stack (the slot is not even filled
' yet, so that first one is harmless) and is DELIVERED afterwards, by which time
' the worker is running. An alwaysNotify "result" field behaves the same way; the
' difference is only that this handler and onAddonSyncResult disagree about how to
' read it.
'
' Concretely, what this sub was doing wrong: it treated the arrival of a
' "finished" notification as proof the worker was done, reaped the node and
' reported a fault — while the worker was still blocked inside its HTTP call, on
' its very first run, every single time. On device that read as
'   addon sync: the worker finished with no result (stage: request-started)
' with a stage taken from a task still in flight. Gating on the sentinel's value
' instead of its arrival is the fix: the real notification carries true, the
' spurious one carries false, and only the former may conclude anything.
'
' Once the value IS true, the worker has run sync() to completion, so an absent
' result is a real fault and this is the only place that reports it. The stage it
' stopped at is the diagnosis: "request-started" means the worker is genuinely
' still in the request or was killed mid-request; "entered-sync" or "init" means
' sync() effectively did not run; "threw" means the catch path ran but even its
' error packet never landed. It is written into the fault text AND printed,
' because the strip is what a fault found later is read from while the print is
' what a fault being watched for is caught by.
sub onAddonSyncFinished(event = invalid as dynamic)
    task = m.addonSyncTask
    if not AccountResultCurrent(task,event) then return
    if task = invalid then return

    ' The spurious alwaysNotify notification. The worker has not finished; its
    ' real notification is still to come. Touch nothing — reaping here is what
    ' destroyed the real result.
    if task.finished <> true then return
    if Type(task.result) = "roAssociativeArray"
        onAddonSyncResult(event)
        return
    end if

    m.addonSyncTask = invalid

    stage = "unknown"
    if task.stage <> invalid and task.stage <> "" then stage = task.stage
    AsyncTask_Reap(task, m.top, false)

    ClearAddonSyncFaults()
    m.addonSyncStatus = {state:"failed",text:"Stremio add-on sync ended without a result. Retry in Add-ons.",complete:false}
    AddAddonSyncFault(m.addonSyncStatus.text)
    RefreshAddonStatus()
    PumpPendingLibrarySync()
end sub

' Retract exactly the lines the last add-on sync published. Clearing by text
' would not work: the reasons embed the transport's error string, so a retry
' that failed differently would leave the previous line up forever.
sub ClearAddonSyncFaults()
    if m.addonSyncFaults <> invalid
        for each key in m.addonSyncFaults
            ReportStoreFault(key, false)
        end for
    end if
    m.addonSyncFaults = []
end sub

sub AddAddonSyncFault(reason as string)
    ReportStoreFault(reason, true)
    m.addonSyncFaults.Push(reason)
end sub

' Kick the account library sync. Runs on every stremio launch — a fresh login
' and a relaunched session alike — because only the continue-watching stack
' persists, so the full library must be re-pulled from the account in the
' background each time. The task returns the raw library item array; MainScene
' passes it to LibraryStore.SyncFromStremio, the single mapping authority.
' Launch the library sync unless the add-on sync is still running; if it is,
' remember to run it when that settles. Both pull in the background at launch,
' and the device refuses NEW concurrent connections past a low ceiling (~4-6),
' so serializing the two account syncs keeps the launch burst under it. Whatever
' still slips through is caught by Transport's bounded retry.
sub StartLibrarySync()
    if m.addonSyncTask <> invalid
        m.pendingLibrarySync = true
        return
    end if
    LaunchLibrarySync()
end sub

' The actual launch, split out so the deferred path can reuse it unchanged.
sub LaunchLibrarySync()
    if m.librarySyncTask <> invalid or m.storeHost = invalid then return
    if m.storeHost.callFunc("AuthGetSession") <> "stremio" then return
    fields = {accountGeneration:AccountGeneration()}
    if m.storeHost <> invalid then fields.authKey = m.storeHost.callFunc("AuthGetAuthKey")
    task = AsyncTask_Launch(m.top, "LibrarySyncTask", "onLibrarySyncResult", fields, NextAccountWorkerId("librarySync"))
    m.librarySyncTask = task
end sub

' Run the library sync that was deferred behind an in-flight add-on sync. Called
' from every place the add-on sync node is torn down — except revocation, which
' is dropping the session and has nothing to sync.
sub PumpPendingLibrarySync()
    if m.pendingLibrarySync <> true then return
    m.pendingLibrarySync = false
    LaunchLibrarySync()
end sub

' One library sync settled. Reconcile the store with the remote collection and
' update Home's Continue Watching row in place — the persisted cache (if any)
' keeps rendering until then. Failures are non-fatal: on a login the CW row
' just stays empty, on a relaunch the persisted cache keeps rendering.
sub onLibrarySyncResult(event = invalid as dynamic)
    task = m.librarySyncTask
    if not AccountResultCurrent(task,event) then return
    if task = invalid then return
    result = task.result
    if Type(result) <> "roAssociativeArray" then return
    m.librarySyncTask = invalid
    AsyncTask_Reap(task, m.top, false)

    ' A dead account session (revoked/expired server-side) is authoritative:
    ' drop to the guest gate instead of silently limping on a key that can no
    ' longer sync.
    if result <> invalid and result.revokedSession = true
        HandleRevokedSession()
        return
    end if

    if result.ok <> true or Type(result.items) <> "roArray"
        ReportStoreFault("Account library could not sync. Retry saved changes in Settings.",true)
        return
    end if
    ReportStoreFault("Account library could not sync. Retry saved changes in Settings.",false)
    if m.storeHost = invalid then return
    if m.pushingLibraryWrite = true or (m.accountLibraryReady = true and Type(m.accountWrites) = "roArray" and m.accountWrites.Count() > 0) then return
    m.storeHost.callFunc("LibrarySyncFromStremio", result.items)
    m.accountLibraryReady = true
    for each job in m.accountWrites
        if job.kind = "libraryChange"
            change = job.payload
            if change.added = true
                m.storeHost.callFunc("LibraryAddSaved",change.metaId,change.metaType,change.name,change.poster)
            else
                m.storeHost.callFunc("LibraryRemoveSaved",change.metaId)
            end if
        else if job.kind = "watchState"
            packet = job.payload
            season = 0:episode = 0
            if packet.season <> invalid then season = packet.season
            if packet.episode <> invalid then episode = packet.episode
            checkpoint = {videoId:packet.videoId,metaId:packet.metaId,metaType:packet.metaType,season:season,episode:episode,name:packet.name,poster:packet.poster,position:packet.position,duration:packet.duration}
            m.storeHost.callFunc("LibrarySetPosition",checkpoint)
        end if
    end for
    ScheduleWatchStatePush()
    if m.homeScreen <> invalid then m.homeScreen.callFunc("RefreshContinueWatching")
    ' The relaunched-session case can land the sync while the Library screen is
    ' already up: poke its grid so the freshly synced saved set appears without
    ' a re-entry (guest sessions never reach this path). Same idempotent rebuild
    ' as the LibraryScreen's own OnEnter.
    if m.stack.top() <> invalid and m.stack.top().id = "libraryScreen" and m.libraryScreen <> invalid
        m.libraryScreen.callFunc("RefreshRows")
    end if
end sub

' Voice playback commands target the active native Video only. Other transport
' commands remain unhandled so Roku's native player can apply its defaults.
function HandleVoiceTransport(info as object) as object
    if m.stack = invalid then return { status: "unhandled" }
    active = m.stack.top()
    if active = invalid or active.id <> "playerScreen" then return { status: "unhandled" }
    if m.playerScreen = invalid then return { status: "error.no-media" }
    video = m.playerScreen.FindNode("video")
    if video = invalid then return { status: "error.no-media" }

    decision = VoicePlaybackDecision(info, {
        state: video.state
        position: video.position
        duration: video.duration
    })
    ' Roku defaults autoplayAfterSeek to true, so a paused seek otherwise
    ' resumes implicitly. Apply the flag before seeking and restore it when
    ' play/resume is requested so normal remote trickplay remains available.
    if decision.autoplayAfterSeek <> invalid then video.autoplayAfterSeek = decision.autoplayAfterSeek
    if decision.seek <> invalid then video.seek = decision.seek
    if decision.control <> invalid then video.control = decision.control
    return { status: decision.status }
end function

' An ECP deep link arrived with launch args or input. Run imports sequentially
' with background add-on workers; a second import is dropped while one runs.
sub HandleDeepLink(args as object)
    if args = invalid
        return
    end if
    if m.import <> invalid
        return
    end if

    keys = ""
    for each key in args
        if keys <> "" then keys = keys + ","
        keys = keys + key
    end for

    parse = DeepLinkStore().Parse(args)

    if parse.kind = "none"
        return
    end if
    if parse.kind = "unknown"
        ShowImportDialog("Add-on import", ["Unsupported request: " + parse.error + "."])
        return
    end if
    if not parse.ok
        ShowImportDialog("Add-on import", ["Could not import: " + parse.error + "."])
        return
    end if

    BeginImport(parse.addons, parse.settings)
end sub

' Start an add-on import: seed the single import slot and pump it. Both deep
' links (above) and the local setup page (ImportFromSetup) land here, so there
' can never be two import pipelines with two sets of counters and two dialogs
' racing for the same add-on. Callers guard m.import <> invalid first — the
' slot holds exactly one import at a time.
sub BeginImport(addons as object, settings as dynamic)
    m.import = {
        pending: []
        added: 0
        skipped: 0
        failed: 0
        failures: []
        task: invalid
        settings: settings
        requested: addons.Count()
    }
    for each url in addons
        m.import.pending.Push(url)
    end for
    PumpImport()
end sub

' The local setup page (source/util/SetupPage.brs) hands off one manifest URL.
' Returns whether it was queued: the page answers 200 with a "watch the TV"
' page, or 409 with a "busy" page — never a dialog on this side (the import
' summary that lands in ShowImportDialog is the TV's own confirmation).
function ImportFromSetup(url as dynamic) as boolean
    ' Local-network requests may change the add-on registry only while the
    ' user has explicitly opened Add-ons on the Roku.
    if m.stack = invalid then return false
    active = m.stack.top()
    if active = invalid then return false
    if active.id <> "addonsScreen" then return false
    if m.import <> invalid then return false
    if url = invalid then return false
    if url = "" then return false
    BeginImport([url], invalid)
    return true
end function

' Address of the local setup page, published by main() at launch. Stored here
' and pushed to the Add-ons screen, where the install workflow actually lives.
sub ShowSetupAddress(url as dynamic)
    if url = invalid then return
    if url = "" then return
    m.setupAddress = url
    if m.addonsScreen <> invalid then m.addonsScreen.callFunc("SetSetupAddress", url)
end sub

' Start the next queued manifest fetch, or finish when the queue is empty.
sub PumpImport()
    if m.import = invalid then return
    if m.import.task <> invalid then return
    if m.import.pending.Count() > 0
        url = m.import.pending.Shift()
        task = AsyncTask_Launch(m.top, "AddonsInstallTask", "onImportTaskResult", { address: url, accountGeneration:AccountGeneration(), allowLocalHttp:m.storeHost.callFunc("SettingsGetPlaybackOptions").allowLocalHttp = true }, NextAccountWorkerId("deepLinkInstall"))
        m.import.task = task
        return
    end if
    FinishImport()
end sub

' One manifest fetch settled. The task validated against a registry-less store,
' so an already-installed id still comes back ok — the real duplicate gate runs
' here, in AddonsStore.Register. That orders the counts: added, skipped
' (duplicate/built-in), or failed.
sub onImportTaskResult(event = invalid as dynamic)
    if m.import = invalid then return
    task = m.import.task
    if not AccountResultCurrent(task,event) then return
    if task = invalid then return
    result = task.result
    if Type(result) <> "roAssociativeArray" then return
    m.import.task = invalid
    AsyncTask_Reap(task, m.top, false)

    resultId = ""
    resultError = ""
    if result <> invalid
        if result.id <> invalid then resultId = result.id
        if result.error <> invalid then resultError = result.error
    end if

    if result <> invalid and result.ok and result.record <> invalid
        registered = false
        if m.storeHost <> invalid
            registered = m.storeHost.callFunc("AddonsRegister", result.record)
        end if
        if registered
            m.import.added = m.import.added + 1
        else
            m.import.skipped = m.import.skipped + 1
        end if
    else
        m.import.failed = m.import.failed + 1
        line = resultError
        if line = "" then line = "could not be installed"
        if resultId <> "" then line = resultId + ": " + line
        m.import.failures.Push(line)
    end if
    PumpImport()
end sub

' All manifest fetches are done. Apply the settings through the same path the
' Settings screen uses (invalid values are rejected, not stored), then report
' the outcome in one dialog — the channel is the authority on the result; ECP
' only ever said "delivered".
sub FinishImport()
    if m.import = invalid then return


    blocks = []
    bullets = []

    if m.import.requested > 0
        if m.import.failed = 0
            if m.import.added = 0
                blocks.Push("Add-ons already installed.")
            else
                blocks.Push(m.import.added.ToStr() + " " + AddonWord(m.import.added) + " added.")
            end if
        else if m.import.added = 0
            if m.import.failed = 1
                blocks.Push("Add-on import failed.")
            else
                blocks.Push(m.import.failed.ToStr() + " add-ons could not be installed.")
            end if
            for each line in m.import.failures
                bullets.Push(line)
            end for
        else
            blocks.Push(m.import.added.ToStr() + " " + AddonWord(m.import.added) + " added, " + m.import.failed.ToStr() + " failed.")
            for each line in m.import.failures
                bullets.Push(line)
            end for
        end if
    end if

    if m.import.settings <> invalid and m.import.settings.serverAddress <> invalid
        if m.storeHost <> invalid
            ' This is the ECP entry point for the streaming server, and it used
            ' to set the address and stop there. The value was live for the rest
            ' of the session and gone on the next launch, because nothing had
            ' ever written it to the registry — a wipe with no symptom until the
            ' relaunch, and no line anywhere saying the value was never saved.
            ' The store saves itself now, so the only thing left to do here is
            ' notice when it could not.
            if m.storeHost.callFunc("SettingsSetServerAddress", m.import.settings.serverAddress)
                if m.storeHost.callFunc("SettingsSaveFailed") then
                    blocks.Push("Server linked, but the address could not be saved.")
                    ReportStoreFault("settings could not be saved", true)
                else
                    blocks.Push("Server linked.")
                    ReportStoreFault("settings could not be saved", false)
                end if
            else
                blocks.Push("Invalid server address was ignored.")
            end if
        end if
    end if

    if blocks.Count() = 0 then blocks.Push("No changes requested.")

    ShowImportDialog("Add-on import", blocks, bullets)
    if m.addonsScreen <> invalid then m.addonsScreen.callFunc("RefreshInstalledRows")

    ' New add-ons may have landed: Home's grid was built from the pre-import
    ' catalog set, so let it re-derive if its add-on set actually moved. Same
    ' predicate as the add-on sync, for the same reason — "the import added
    ' something" is not the question, "is Home's grid current" is, and an import
    ' that only re-registers what is already there still leaves Home showing
    ' whatever it walked before. The fill happens off the UI thread behind the
    ' summary dialog; nothing to block on here.
    NotifyAddonChanges()

    m.import = invalid
end sub

' Singular/plural for the add-on count in the import summary.
function AddonWord(count as integer) as string
    if count = 1 then return "add-on"
    return "add-ons"
end function

sub ShowImportDialog(title as string, blocks as object, bullets = invalid as object)
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.id = "deepLinkImportDialog"
    dialog.title = title
    dialog.message = blocks
    if bullets <> invalid and bullets.Count() > 0
        dialog.bulletText = bullets
    end if
    dialog.buttons = ["OK"]
    dialog.observeField("buttonSelected", "onImportButtonSelected")
    dialog.observeField("wasClosed", "onImportDialogClosed")
    m.top.dialog = dialog
end sub

' A button press does not dismiss a StandardMessageDialog on its own — it only
' sets buttonSelected. Mirror ConfirmExitDialog: close through the dialog's own
' close field, which funnels into the same wasClosed path the scene uses to
' clear the slot and hand focus back to Home.
sub onImportButtonSelected()
    if m.top.dialog <> invalid and m.top.dialog.id = "deepLinkImportDialog"
        m.top.dialog.close = true
    end if
end sub

' The import dialog dismissed (OK, Back or Home). Clear the Scene's dialog slot
' by id — roSGNode references cannot be compared with "=" — then give focus
' back to Home.
sub onImportDialogClosed()
    if m.top.dialog <> invalid and m.top.dialog.id = "deepLinkImportDialog"
        m.top.dialog = invalid
    end if
    RestoreActiveScreenFocus()
end sub

' Back routing: the top screen gets first crack; if it declines and more screens
' remain, pop. On the bottom Home screen, Back opens the exit dialog.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "back"
        if m.stack.onBackPressed() then return true
        if m.stack.count() > 1 then return m.stack.pop()
        m.top.dialog = m.confirmExit
        return true
    end if

    return false
end function

sub onSourceRecoveryRequest()
    request = m.playerScreen.sourceRecoveryRequest
    if Type(request) <> "roAssociativeArray" then return
    shown = m.stack.top()
    if shown = invalid or shown.id <> "playerScreen" then return
    if m.playerScreen.callFunc("CanRecoverSources",request.videoId) <> true then return
    if m.streamsScreen.callFunc("PrepareSourceRecovery",request) <> true then return
    m.stack.pop()
end sub
