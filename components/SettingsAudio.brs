sub UpdateAudioGuide()
    if m.guideTitle <> invalid then m.guideTitle.text = "Audio, made simple"
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

sub ShowPlaybackOption(kind as string)
    if kind = "quality"
        ShowSettingsAudioDialog("Picture quality",["4K first keeps 1080p alternatives available. 4K only requires labelled UHD candidates and rejects known below-UHD inspected MKV video.","Labels alone do not prove decoded resolution. The * shortcut still changes the current title's filter."],["4K first + 1080p","4K only","Cancel"],kind)
    else if kind = "autoplay"
        ShowSettingsAudioDialog("Next episode",["On starts the next known episode after a five-second countdown. Back cancels.","Off finishes the current episode and waits. Changes apply to new playback."],["On","Off","Cancel"],kind)
    else if kind = "recovery"
        ShowSettingsAudioDialog("Source recovery",["On automatically tries compatible alternatives when a source fails or stalls.","Off keeps playback on the selected source. English audio checks remain enabled. Changes apply to new playback."],["On","Off","Cancel"],kind)
    else if kind = "autoStart"
        ShowSettingsAudioDialog("Automatic Play",["Start sooner briefly compares available candidates, then starts without waiting for every provider. Later providers may have better choices.","Compare providers waits for all eligible add-ons before choosing. Your quality and English audio checks still apply."],["Start sooner","Compare providers","Cancel"],kind)
    end if
end sub

sub ApplyPlaybackOption(kind as string, index as integer)
    if index < 0 or index > 1 or m.stores = invalid then return
    key = ""
    value = index = 0
    if kind = "quality"
        key = "fourKOnly"
        value = index = 1
    else if kind = "autoplay"
        key = "autoNextEpisode"
    else if kind = "recovery"
        key = "autoSourceRetry"
    else if kind = "autoStart"
        key = "waitForProviders"
        value = index = 1
    end if
    if key = "" then return
    if m.stores.settings.callFunc("SettingsSetPlaybackOption",key,value) <> true then return
    m.status.text = "Playback preference updated. Applies to new playback."
    if m.stores.settings.callFunc("SettingsSaveFailed") then m.status.text = m.status.text + " — not saved"
    ReportSaveFault()
    BuildRows(true)
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
    if kind = "quality" or kind = "autoplay" or kind = "recovery" or kind = "autoStart" then ApplyPlaybackOption(kind,index)
    m.list.SetFocus(true)
end sub
