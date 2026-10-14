sub UpdateAudioGuide()
    if m.guide = invalid then return
    mode = "projector"
    if m.stores <> invalid and m.stores.settings.callFunc("SettingsGetAudioMode") = "surround" then mode = "surround"
    m.guide.text = AudioSetup_Guide(mode)
end sub

sub ApplyAudioSetup(mode as string)
    if mode <> "projector" and mode <> "surround" then return
    if m.stores = invalid then return
    m.stores.settings.callFunc("SettingsSetAudioMode",mode)
    if mode = "surround"
        m.status.text = "HDMI surround selected. Roku → soundbar HDMI IN → display. Set Roku digital audio Auto; volume modes Off."
    else
        m.status.text = "TV / projector speakers selected. Set Roku digital audio Stereo for compatible stereo sources."
    end if
    if m.stores.settings.callFunc("SettingsSaveFailed") then m.status.text = m.status.text + " — not saved"
    ReportSaveFault()
    BuildRows(true)
end sub

sub ShowAudioSetup()
    current = AudioSetupValue()
    ShowSettingsAudioDialog("Choose your speakers",["Current: " + current,"Choose the equipment connected to Roku. This sets the app's source preference; it does not change Roku system settings."],["TV / projector speakers","HDMI soundbar / receiver","Cancel"],"mode")
end sub

sub ShowAudioConnection()
    mode = "projector"
    if m.stores <> invalid and m.stores.settings.callFunc("SettingsGetAudioMode") = "surround" then mode = "surround"
    facts = AudioCapabilities_ReadDevice()
    report = AudioSetup_Report(facts,mode)
    ShowSettingsAudioDialog("Audio connection",[report.summary,report.advice],["Done"],"report")
end sub

sub ShowSettingsAudioDialog(title as string, message as object, buttons as object, kind as string)
    scene = m.top.getScene()
    if scene = invalid or scene.dialog <> invalid then return
    dialog = CreateObject("roSGNode","StandardMessageDialog")
    if dialog = invalid
        m.status.text = "Audio dialog unavailable. Use the setup guide on this screen."
        return
    end if
    dialog.title = title
    dialog.message = message
    dialog.buttons = buttons
    dialog.id = NextSettingsWorkerId("audioDialog")
    m.settingsAudioDialog = dialog
    m.settingsAudioDialogKind = kind
    dialog.ObserveFieldScoped("buttonSelected","onSettingsAudioChoice")
    scene.dialog = dialog
end sub

sub onSettingsAudioChoice(event as object)
    if m.settingsAudioDialog = invalid then return
    node = event.GetRoSGNode()
    if node = invalid or node.id <> m.settingsAudioDialog.id then return
    index = node.buttonSelected
    if index = invalid or index < 0 then return
    kind = m.settingsAudioDialogKind
    m.settingsAudioDialog = invalid
    node.close = true
    if kind = "mode"
        if index = 0 then ApplyAudioSetup("projector")
        if index = 1 then ApplyAudioSetup("surround")
    end if
    m.list.SetFocus(true)
end sub
