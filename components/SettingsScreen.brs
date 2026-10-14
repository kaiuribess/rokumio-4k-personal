' SettingsScreen — app preferences.
'
' Optional Stremio sync and an advanced external streaming server. Direct
' HTTPS sources do not need a server. Values are refreshed on entry without
' jumping away from the edited row when a modal closes.
'
' A hidden Network-diagnostics row sits behind NETDIAG_REVEAL_TAPS presses of
' the Test-server row. It is TEMPORARY: it exists to locate the intermittent
' outbound-connect failures (status -7) as DNS, radio, or concurrency, and it
' goes away — with NetDiagTask itself — once that is known.

' Five consecutive presses of the Test-server row reveal the hidden
' Network-diagnostics row. Test-server is the right host for the gesture: it is
' already the row about connectivity, so a diagnostic living one row below it
' reads as a continuation rather than as a stray debug affordance. The count is
' inlined at its one use because standard BrightScript has no file-scope const
' (that is a BrighterScript feature, and this is a .brs file).

sub init()
    m.title = m.top.FindNode("settingsTitle")
    m.sub = m.top.FindNode("settingsSub")
    m.status = m.top.FindNode("settingsStatus")
    m.list = m.top.FindNode("settingsList")
    m.guide = m.top.FindNode("settingsGuide")
    m.settingsAudioDialog = invalid

    t = Theme()
    m.title.color = t.accent
    m.sub.color = t.textSecondary
    m.status.color = t.accent
    m.list.focusBitmapBlendColor = t.accent
    m.top.FindNode("settingsPlate").color = t.tileFace
    m.top.FindNode("settingsGuideTitle").color = t.accent
    m.top.FindNode("settingsGuide").color = t.textSecondary

    m.list.ObserveField("rowItemSelected", "onRowSelected")

    m.rows = []
    m.heartbeatTask = invalid
    ' Component fields outlive OnEnter, so once the diagnostics row is revealed it
    ' stays revealed for the rest of the session instead of vanishing every time
    ' the screen is left and re-entered.
    m.showNetDiag = false
    m.testServerTaps = 0
    m.netDiagTask = invalid
end sub

function OnEnter(params as object) as void
    restoring = m.rows.Count() > 0
    if not restoring then m.status.text = ""
    BuildRows(restoring)
    m.list.SetFocus(true)
end function

function OnExit() as void
    CancelTestServer()
    CancelNetDiag()
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

' Rebuild the row list from the live SettingsStore values. The session row is
' first so it is the handiest action: a guest is offered the Stremio login, a
' stremio user their email + logout. The rest follow in fixed order.
sub BuildRows(preserveFocus = false as boolean)
    focusedRow = 0
    if preserveFocus
        focus = m.list.rowItemFocused
        if Type(focus) = "roArray" and focus.Count() >= 2 then focusedRow = focus[0]
    end if
    m.rows = []
    if m.stores <> invalid and m.stores.auth.callFunc("AuthGetSession") = "stremio"
        m.rows.Push({
            action: "logout"
            title: "Disconnect Stremio"
            value: SessionValue()
        })
    else
        m.rows.Push({
            action: "login"
            title: "Connect Stremio"
            value: "Optional sync"
        })
    end if
    m.rows.Push({ action: "audio", title: "Audio mode", value: AudioSetupValue() })
    m.rows.Push({ action: "audioConnection", title: "Audio connection", value: "Check speakers" })
    prefs = PlaybackPreferences(m.stores)
    quality = "4K first + 1080p"
    if prefs.fourKOnly then quality = "4K only"
    nextLabel = "On"
    if not prefs.autoNextEpisode then nextLabel = "Off"
    recoveryLabel = "On"
    if not prefs.autoSourceRetry then recoveryLabel = "Off"
    m.rows.Push({action:"quality",title:"Picture quality",value:quality})
    m.rows.Push({action:"autoplay",title:"Next episode",value:nextLabel})
    m.rows.Push({action:"recovery",title:"Source recovery",value:recoveryLabel})
    m.rows.Push({ action: "addonChecks", title: "Add-on checks", value: "Find problems" })
    m.rows.Push({
        action: "server"
        title: "Optional server"
        value: ServerValue()
    })
    m.rows.Push({
        action: "testServer"
        title: "Check optional server"
        value: "Connection check"
    })
    m.rows.Push({action:"about",title:"About",value:"Crimson Cinema"})
    ' Advanced diagnostics fit the fourth visible row without covering status.
    if m.showNetDiag
        m.rows.Push({
            action: "netdiag"
            title: "Network diagnostics"
            value: "Advanced check"
        })
    end if

    content = CreateObject("roSGNode", "ContentNode")
    for each row in m.rows
        entry = content.CreateChild("ContentNode")
        item = entry.CreateChild("ContentNode")
        item.title = row.title
        item.description = row.value
    end for
    m.list.content = content
    if focusedRow < 0 or focusedRow >= m.rows.Count() then focusedRow = 0
    m.list.jumpToRowItem = [focusedRow, 0]
    UpdateAudioGuide()
end sub

' Account state fits the row without displaying the profile's private email.
function SessionValue() as string
    if m.stores <> invalid
        if m.stores.auth.callFunc("AuthGetSession") = "stremio" then return "Signed in"
    end if
    return "Stremio account"
end function

function ServerValue() as string
    if m.stores = invalid then return "—"
    address = m.stores.settings.callFunc("SettingsGetServerAddress")
    if address = "" then return "Not needed"
    return "Configured"
end function

function AudioSetupValue() as string
    if m.stores <> invalid
        if m.stores.settings.callFunc("SettingsGetAudioMode") = "surround" then return "HDMI surround"
    end if
    return "TV / projector"
end function

sub ToggleAudioSetup()
    if m.stores = invalid then return
    value = "surround"
    if m.stores.settings.callFunc("SettingsGetAudioMode") = "surround" then value = "projector"
    ApplyAudioSetup(value)
end sub

sub onRowSelected()
    data = m.list.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[0]
    if index < 0 or index >= m.rows.Count() then return
    action = m.rows[index].action
    if action = "login"
        SignIn()
    else if action = "logout"
        SignOut()
    else if action = "server"
        EditServer()
    else if action = "audio"
        ShowAudioSetup()
    else if action = "audioConnection"
        ShowAudioConnection()
    else if action = "quality" or action = "autoplay" or action = "recovery"
        ShowPlaybackOption(action)
    else if action = "addonChecks"
        m.top.pushRequest = {screen:"addonHealthScreen",params:{}}
    else if action = "about"
        m.top.pushRequest = {screen:"aboutScreen",params:{}}
    else if action = "testServer"
        ' Counted here rather than inside TestServer so every press is counted,
        ' including the presses that TestServer itself declines to act on —
        ' a tap that gets rejected for a missing address is still a tap, and the
        ' gesture should not need the server to be configured to reach.
        m.testServerTaps = m.testServerTaps + 1
        if m.testServerTaps >= 5 and not m.showNetDiag
            m.showNetDiag = true
            BuildRows(true)
        end if
        TestServer()
    else if action = "netdiag"
        RunNetDiag()
    end if
end sub

' The session actions hand off to the Scene, the only place that owns auth.
' Publishing through pushRequest keeps this screen a pure reporter — the Scene
' runs the link-code flow or the logout confirm/teardown.
sub SignIn()
    m.top.pushRequest = { action: "login" }
end sub

sub SignOut()
    m.top.pushRequest = { action: "logout" }
end sub

' Open the streaming server editor. Empty input clears the address (clearing is
' a deliberate action); anything else is validated by SettingsStore.
sub EditServer()
    scene = m.top.getScene()
    if scene = invalid or scene.dialog <> invalid then return
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    if dialog = invalid then dialog = CreateObject("roSGNode", "KeyboardDialog")
    if dialog = invalid
        m.status.text = "Keyboard unavailable. Direct HTTPS sources still work without a server."
        return
    end if
    dialog.title = "Optional server"
    message = "For an external torrent server only. Leave empty for direct HTTPS movie sources."
    if dialog.HasField("keyboardDomain")
        dialog.message = [message]
    else
        dialog.message = message
    end if
    dialog.text = ""
    if m.stores <> invalid then dialog.text = m.stores.settings.callFunc("SettingsGetServerAddress")
    dialog.buttons = ["Save", "Cancel"]
    dialog.observeField("buttonSelected", "onServerChoice")
    ' Caret after the address rather than at 0, so editing it does not start by
    ' arrowing past the whole value. Before the dialog is shown: the internal
    ' edit box is built at CreateObject time, so this is the earliest the setting
    ' can land. See ApplyServerKeyboard.
    ApplyServerKeyboard(dialog)
    m.top.getScene().dialog = dialog
end sub

' Both Roku keyboard variants expose the editor differently. Setup addresses
' stay out of voice dictation; movie search keeps its separate voice keyboard.
sub ApplyServerKeyboard(dialog as object) as void
    if dialog = invalid then return
    editor = invalid
    if dialog.HasField("textEditBox")
        editor = dialog.textEditBox
    else if dialog.HasField("keyboard") and dialog.keyboard <> invalid
        editor = dialog.keyboard.textEditBox
    end if
    if editor = invalid then return
    if editor.HasField("voiceEnabled") then editor.voiceEnabled = false
    if editor.HasField("cursorPosition") then editor.cursorPosition = Len(dialog.text)
end sub

sub onServerChoice()
    dialog = m.top.getScene().dialog
    if dialog <> invalid
        index = dialog.buttonSelected
        chosen = dialog.text
        ' StandardDialog's own dismissal, and the one ConfirmExitDialog already
        ' uses: setting close makes the scene drop the node from the dialog slot
        ' by itself. Both values are read above before anything is torn down.
        if dialog.HasField("close")
            dialog.close = true
        else
            m.top.getScene().dialog = invalid
        end if
        if index = 0
            if chosen = invalid or chosen.Trim() = ""
                m.stores.settings.callFunc("SettingsClearServerAddress")
                m.status.text = "Server address cleared."
            else if m.stores.settings.callFunc("SettingsSetServerAddress", chosen)
                m.status.text = "Server address updated."
            else
                m.status.text = "Invalid address — use http://host[:port]"
            end if
            ' Every branch above ends in a write, so the result is the same
            ' question on all of them: did the registry take it? Asked here
            ' rather than after each setter because the store saves itself now
            ' and there is no per-setter answer to check.
            if m.stores.settings.callFunc("SettingsSaveFailed") then m.status.text = m.status.text + " — not saved"
            ReportSaveFault()
            BuildRows(true)
        end if
    end if
    m.list.SetFocus(true)
end sub

' Mirrors the store's last write result into the Scene's fault strip, clearing
' it on the next success. The status line says what just happened on this
' screen; the strip is what a refused write looks like from anywhere else in the
' app, including after the user has navigated away — which is the only place a
' setting that did not save can be noticed, since nothing about it is wrong
' until the next launch.
sub ReportSaveFault()
    if m.stores = invalid then return
    failed = m.stores.settings.callFunc("SettingsSaveFailed")
    scene = m.top.getScene()
    if scene <> invalid then scene.callFunc("ReportStoreFault", "settings could not be saved", failed)
end sub

' Report the streaming server's reachability through the status line. Verifying
' the address before trying to play a torrent stream turns a 90-second playback
' dead-end into a quick, obvious check. The heartbeat rides the default request
' timeout, so it runs through HeartbeatTask — a dead address costs the worker
' thread, not a frozen Settings screen.
sub TestServer() as void
    if m.stores = invalid then return
    address = m.stores.settings.callFunc("SettingsGetServerAddress")
    if address = ""
        m.status.text = "No server configured. Direct HTTPS movie sources do not need one."
        return
    end if
    if m.heartbeatTask <> invalid then return

    m.status.text = "Testing server…"
    task = AsyncTask_Launch(m.top, "HeartbeatTask", "onTestServerResult", { address: address }, NextSettingsWorkerId("heartbeat"))
    m.heartbeatTask = task
end sub

' The heartbeat finished. A stale result that landed after CancelTestServer is
' dropped by the m.heartbeatTask guard.
sub onTestServerResult(event as object)
    if m.heartbeatTask = invalid then return
    task = event.GetRoSGNode()
    if task = invalid or task.id <> m.heartbeatTask.id then return
    result = event.GetData()
    if Type(result) <> "roAssociativeArray" then return
    m.heartbeatTask = invalid
    AsyncTask_Reap(task, m.top, false)

    if result.alive
        m.status.text = "Server OK."
    else
        m.status.text = "Server unreachable. Check the configured address."
    end if
end sub

sub CancelTestServer()
    if m.heartbeatTask <> invalid
        task = m.heartbeatTask
        m.heartbeatTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

' TEMPORARY. Launch the four-probe HTTPS diagnostic. The server address is read
' here and handed over rather than read inside the task, because the task is
' scoped to the component and SettingsStore is not — this is the same handoff
' HeartbeatTask's "address" field exists for.
sub RunNetDiag()
    if m.netDiagTask <> invalid then return
    address = ""
    if m.stores <> invalid then address = m.stores.settings.callFunc("SettingsGetServerAddress")

    m.status.text = "Running network diagnostics…"
    m.netDiagTask = AsyncTask_Launch(m.top, "NetDiagTask", "onNetDiagResult", { serverAddress: address }, NextSettingsWorkerId("network"))
end sub

' Fires once per probe as well as once at the end, so the summary fills in
' progressively instead of appearing all at once. The done flag is what
' distinguishes the two: an alwaysNotify field with no value can notify before
' the worker has written anything, and reaping on that would pull the task out
' from under a run that is still going. An invalid result is the same case and is
' dropped for the same reason.
'
' Only the compact "A=200 B=301 C=-7 D=200" summary goes on screen. The verdict
' is a full sentence and settingsStatus is a single unfilled line, so the prose
' would be clipped; it is printed to the console instead, where the reader
' already is. C against D is readable from the summary either way.
sub onNetDiagResult(event as object)
    if m.netDiagTask = invalid then return
    task = event.GetRoSGNode()
    if task = invalid or task.id <> m.netDiagTask.id then return
    result = event.GetData()
    if Type(result) <> "roAssociativeArray" then return
    if result.done
        m.netDiagTask = invalid
        AsyncTask_Reap(task, m.top, false)
    end if
    m.status.text = result.summary
end sub

function NextSettingsWorkerId(prefix as string) as string
    if m.diagnosticSeq = invalid then m.diagnosticSeq = 0
    m.diagnosticSeq = m.diagnosticSeq + 1
    return prefix + m.diagnosticSeq.ToStr()
end function

sub CancelNetDiag()
    if m.netDiagTask <> invalid
        task = m.netDiagTask
        m.netDiagTask = invalid
        ' Best effort. STOP and RemoveChild are synchronous on this thread while
        ' the worker checks the flag on its own, so it may or may not see this
        ' before the node goes away. It is worth setting because the flag is
        ' checked BETWEEN probes, and the alternative is a reaped node running
        ' three more five-second transfers against a screen nobody is watching.
        task.cancelRequested = true
        AsyncTask_Reap(task, m.top, true)
    end if
end sub
