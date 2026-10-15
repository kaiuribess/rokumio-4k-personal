function TestContent() as object
    return { children: [], CreateChild: function(kind as string) as object
        child = TestContent()
        m.children.Push(child)
        return child
    end function }
end function

function TestNode(fields as object) as object
    fields.HasField = function(key as string) as boolean
        return m.DoesExist(key)
    end function
    return fields
end function

sub AsyncTask_Launch(parent as object, kind as string, observer as string, args as object, id as string)
    m.launches = m.launches + 1
end sub

function NextSettingsWorkerId(prefix as string) as string
    return prefix
end function

function TestNativeDialog(kind as string) as dynamic
    m.nativeRequests.Push(kind)
    if kind = "StandardMessageDialog" and not m.standardDialogAvailable then return invalid
    if kind = "Dialog" and not m.legacyDialogAvailable then return invalid
    return {
        kind: kind
        observeField: sub(fieldName as string, observerName as string)
            m.observedField = fieldName
            m.observerName = observerName
        end sub
    }
end function

sub ResetRemovalDialogs()
    m.nativeRequests = []
    m.standardDialogAvailable = true
    m.legacyDialogAvailable = true
    m.status = { text: "" }
    m.pendingRow = invalid
    m.top = {
        scene: { dialog: invalid }
        getScene: function() as dynamic
            return m.scene
        end function
    }
end sub

sub TestRemovalDialogs()
    Harness_Suite("Production add-on removal dialog field contracts")
    row = { id: "example.addon", name: "Movie sources", builtin: false }
    ResetRemovalDialogs()
    ShowRemoveConfirm(row)
    dialog = m.top.scene.dialog
    Harness_Equal(dialog.kind, "StandardMessageDialog", "modern native dialog is preferred")
    Harness_Equal(m.nativeRequests.Count(), 1, "modern dialog avoids unnecessary fallback construction")
    Harness_Equal(Type(dialog.message), "roArray", "modern message field receives its documented string array")
    Harness_Equal(Type(dialog.message[0]), "String", "modern message array contains a plain string")
    Harness_Equal(dialog.buttons[0], "Remove", "removal requires an explicit confirmation button")
    Harness_Equal(dialog.buttons[1], "Cancel", "removal dialog provides a cancellation button")
    Harness_Equal(dialog.observedField, "buttonSelected", "confirmation observes the native selection field")
    Harness_Equal(m.pendingRow.id, row.id, "confirmation retains the exact requested row")
    ResetRemovalDialogs()
    m.standardDialogAvailable = false
    ShowRemoveConfirm(row)
    dialog = m.top.scene.dialog
    Harness_Equal(dialog.kind, "Dialog", "fallback uses the real legacy native node name")
    Harness_Equal(m.nativeRequests.Count(), 2, "legacy construction follows unavailable modern dialog")
    Harness_Equal(Type(dialog.message), "String", "legacy message field receives a string, not an array")
    Harness_Ok(dialog.message.InStr("configured link") >= 0, "legacy message explains how to restore the add-on")
    ResetRemovalDialogs()
    ShowRemoveConfirm({ id: "builtin", name: "Search", builtin: true })
    Harness_Ok(m.top.scene.dialog.message[0].InStr("built-in") >= 0, "built-in confirmation explains its different effect")
    ResetRemovalDialogs()
    m.standardDialogAvailable = false
    m.legacyDialogAvailable = false
    ShowRemoveConfirm(row)
    Harness_Equal(m.top.scene.dialog, invalid, "unavailable dialogs cannot publish a malformed node")
    Harness_Equal(m.pendingRow, invalid, "unavailable dialogs clear the pending removal")
    Harness_Ok(m.status.text.InStr("unchanged") >= 0, "unavailable confirmation leaves the add-on unchanged")
    ResetRemovalDialogs()
    m.top.scene.dialog = { title: "Already open" }
    ShowRemoveConfirm(row)
    Harness_Equal(m.nativeRequests.Count(), 0, "existing modal prevents another confirmation construction")
    Harness_Equal(m.top.scene.dialog.title, "Already open", "existing modal is retained")
    ResetRemovalDialogs()
    m.top.scene = invalid
    ShowRemoveConfirm(row)
    Harness_Equal(m.nativeRequests.Count(), 0, "missing scene safely skips dialog construction")
end sub

sub Main()
    Harness_Suite("Production setup controls")
    m.list = TestNode({ rowItemFocused: [0, 0], SetFocus: sub(value as boolean)
        m.focused = value
    end sub })
    m.status = { text: "" }
    m.rows = []
    m.showNetDiag = false
    m.stores = {
        auth: { session: "guest", callFunc: function(name as string) as dynamic
            if name = "AuthGetSession" then return m.session
            return { email: "PRIVATE_EMAIL_SHOULD_NOT_APPEAR" }
        end function }
        settings: { address: "", audioMode: "projector", callFunc: function(name as string, value = invalid as dynamic) as dynamic
            if name = "SettingsGetServerAddress" then return m.address
            if name = "SettingsGetAudioMode" then return m.audioMode
            if name = "SettingsSetAudioMode"
                m.audioMode = value
                return true
            end if
            if name = "SettingsSaveFailed" then return false
            return invalid
        end function }
    }
    OnEnter(invalid)
    Harness_Equal(m.rows.Count(), 15, "Guest sees provider, caption and playback preferences, audio and add-on checks")
    Harness_Equal(m.rows[4].value, "Start sooner", "automatic Play exposes early-start choice")
    Harness_Equal(m.rows[1].value, "TV / projector", "default preset is clearly named")
    m.top = { getScene: function() as dynamic
        return invalid
    end function }
    ToggleAudioSetup()
    Harness_Equal(m.rows[1].value, "HDMI surround", "one OK changes to future surround setup")
    Harness_Ok(m.status.text.InStr("HDMI IN") >= 0, "surround choice explains correct soundbar wiring")
    ToggleAudioSetup()
    Harness_Equal(m.rows[1].value, "TV / projector", "second OK returns to projector setup")
    Harness_Ok(m.status.text.InStr("Stereo") >= 0, "projector choice explains required Roku stereo setting")
    Harness_Equal(m.rows[0].action, "login", "Optional Stremio sync is accessible")
    Harness_Equal(m.rows[10].value, "Not needed", "Server row explains direct playback needs no server")
    Harness_Ok(m.list.focused, "Setup list receives remote focus")
    Harness_Equal(m.list.jumpToRowItem[0], 0, "First setup entry begins at first row")
    m.list.rowItemFocused = [1, 0]
    m.stores.settings.address = "https://user:SECRET@example.test/PRIVATE_PATH?token=PRIVATE_QUERY"
    m.status.text = "Server address updated."
    m.heartbeatTask = { id: "still-pending" }
    m.netDiagTask = { id: "also-pending" }
    OnEnter(invalid)
    Harness_Equal(m.list.jumpToRowItem[0], 1, "Modal restore keeps the edited row selected")
    Harness_Equal(m.status.text, "Server address updated.", "Modal restore keeps operation feedback")
    Harness_Equal(m.heartbeatTask.id, "still-pending", "Modal restore leaves heartbeat active")
    Harness_Equal(m.netDiagTask.id, "also-pending", "Modal restore leaves diagnostics active")
    Harness_Equal(m.rows[10].value, "Configured", "Configured server row hides its private URL")
    m.stores.auth.session = "stremio"
    BuildRows(true)
    Harness_Equal(m.rows[0].action, "logout", "Signed-in profile exposes disconnect")
    Harness_Equal(m.rows[0].value, "Signed in", "Account state hides private email")
    m.showNetDiag = true
    m.list.rowItemFocused = [2, 0]
    BuildRows(true)
    Harness_Equal(m.rows.Count(), 17, "Advanced diagnostics remain available after normal setup rows")
    Harness_Equal(m.list.jumpToRowItem[0], 2, "Revealing diagnostics preserves selected connection check")
    m.list.rowItemFocused = [99, 0]
    BuildRows(true)
    Harness_Equal(m.list.jumpToRowItem[0], 0, "Invalid previous focus is clamped to first row")
    standardEditor = TestNode({ voiceEnabled: true, cursorPosition: 0 })
    ApplyServerKeyboard(TestNode({ text: "https://example.test", textEditBox: standardEditor }))
    Harness_Ok(not standardEditor.voiceEnabled, "Setup server address is not dictated to voice service")
    Harness_Equal(standardEditor.cursorPosition, 20, "Standard keyboard caret follows address")
    legacyEditor = TestNode({ voiceEnabled: true, cursorPosition: 0 })
    ApplyServerKeyboard(TestNode({ text: "http://lan.test", keyboard: { textEditBox: legacyEditor } }))
    Harness_Ok(not legacyEditor.voiceEnabled, "Legacy setup keyboard also keeps voice off")
    Harness_Equal(legacyEditor.cursorPosition, 15, "Legacy keyboard caret follows address")
    ApplyServerKeyboard(TestNode({ text: "" }))
    Harness_Ok(true, "Missing internal keyboard editor is handled")
    m.stores.settings.address = ""
    m.launches = 0
    TestServer()
    Harness_Equal(m.launches, 0, "Unconfigured optional server starts no request")
    Harness_Ok(m.status.text.InStr("do not need one") >= 0, "No-server message does not block direct-source setup")
    TestRemovalDialogs()
    Harness_Finish()
end sub
