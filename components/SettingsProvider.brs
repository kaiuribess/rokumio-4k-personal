' Reuse the native scrolling Settings list instead of a many-button modal.
function PreferredProviderValue() as string
    if m.stores = invalid or m.stores.settings = invalid then return "Automatic"
    priority = ProviderPriority_Snapshot(m.stores.settings.callFunc("SettingsGetProviderPriority"))
    if priority.preferredProviderKey = "" then return "Automatic"
    if m.stores.addons <> invalid
        for each addon in m.stores.addons.callFunc("AddonsGetAll")
            if ProviderPriority_Key(addon) = priority.preferredProviderKey then return AddonDiagnostics_Name(addon).Left(22)
        end for
    end if
    return "Automatic"
end function

sub ShowPreferredProvider()
    if m.stores = invalid or m.stores.settings = invalid then return
    if not ReplaceSettingsList() then return
    m.settingsSection = "providers"
    m.rows = [{action:"providerChoice",title:"Automatic",value:"Last working first",providerKey:""}]
    if m.stores.addons <> invalid
        for each addon in m.stores.addons.callFunc("AddonsGetAll")
            if Type(addon) <> "roAssociativeArray" then continue for
            if m.stores.addons.callFunc("AddonsHasResource",addon.resources,"stream") <> true then continue for
            key = ProviderPriority_Key(addon)
            if key <> "" then m.rows.Push({action:"providerChoice",title:AddonDiagnostics_Name(addon),value:"Request first",providerKey:key})
        end for
    end if
    content = CreateObject("roSGNode","ContentNode")
    for each row in m.rows
        item = content.CreateChild("ContentNode").CreateChild("ContentNode")
        item.title = row.title:item.description = row.value
    end for
    m.list.content = content:m.list.jumpToRowItem = [0,0]:m.list.SetFocus(true)
    if m.title <> invalid then m.title.text = "Preferred source"
    if m.sub <> invalid then m.sub.text = "Choose which waiting provider to request first"
    if m.guideTitle <> invalid then m.guideTitle.text = "Source priority"
    if m.guide <> invalid then m.guide.text = "A preferred provider is requested first when available. Automatic prioritizes the last provider with observed English audio and advancing video/audio samples. Existing requests finish normally; this does not prove every file is compatible. Back returns to Settings."
end sub

sub ApplyPreferredProvider(key as string)
    if m.stores = invalid or m.stores.settings = invalid then return
    saved = m.stores.settings.callFunc("SettingsSetPreferredProviderKey",key)
    m.status.text = "Preferred source updated. Applies to waiting requests."
    if saved <> true then m.status.text = m.status.text + " — not saved"
    ReportSaveFault()
    ClosePreferredProvider()
end sub

sub ClosePreferredProvider()
    if not ReplaceSettingsList() then return
    m.settingsSection = ""
    BuildRows(false)
    m.list.jumpToRowItem = [5,0]:m.list.SetFocus(true)
end sub

' A fresh list gives queued selections from the previous subsection an old
' sender id. Reusing the same row indices could otherwise save another choice.
function ReplaceSettingsList() as boolean
    fresh = CreateObject("roSGNode","RowList")
    if fresh = invalid then return false
    if m.settingsListSequence = invalid then m.settingsListSequence = 0
    m.settingsListSequence = m.settingsListSequence + 1
    fresh.id = "settingsList" + m.settingsListSequence.ToStr()
    fresh.translation = [80,210]:fresh.numRows = 4
    fresh.itemSize = [1000,118]:fresh.itemSpacing = [0,8]
    fresh.rowItemSize = [[1000,110]]:fresh.showRowLabel = [false]
    fresh.drawFocusFeedback = true:fresh.itemComponentName = "PrefRow"
    fresh.vertFocusAnimationStyle = "floatingFocus"
    fresh.focusBitmapBlendColor = Theme().accent
    fresh.ObserveField("rowItemSelected","onRowSelected")
    old = m.list
    m.top.AppendChild(fresh)
    if old <> invalid
        old.UnobserveField("rowItemSelected")
        m.top.RemoveChild(old)
    end if
    m.list = fresh
    return true
end function
