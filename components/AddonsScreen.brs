' AddonsScreen — installed add-on manager.
'
' One column of PrefRows: an "Add add-on" row on top (installs by fetching a
' manifest URL through a system KeyboardDialog), then one row per add-on from
' AddonsStore.GetAll(). Removing any add-on — including a shipped built-in —
' requires a confirmation dialog; the builtin flag is passed to
' AddonsStore.Uninstall so a same-id mirror and its shipped seed are told
' apart. The list is rebuilt after every install/remove so it always reflects
' the store.
'
' The scene owns manifest installation off the render thread. Keyboard and
' browser submissions share its single import slot and its result summary.

sub init()
    m.title = m.top.FindNode("addonsTitle")
    m.sub = m.top.FindNode("addonsSub")
    m.status = m.top.FindNode("addonsStatus")
    m.list = m.top.FindNode("addonsList")

    ' One-time browser setup panel; daily playback uses the Roku remote.
    m.companionPlate = m.top.FindNode("companionPlate")
    m.companionTitle = m.top.FindNode("companionTitle")
    m.companionCaption = m.top.FindNode("companionCaption")
    m.setupHint = m.top.FindNode("setupHint")
    m.setupUrl = m.top.FindNode("setupUrl")

    t = Theme()
    m.title.color = t.accent
    m.sub.color = t.textSecondary
    m.status.color = t.accent
    m.companionPlate.color = t.tileFace
    m.companionTitle.color = t.accent
    m.companionCaption.color = t.textSecondary
    m.setupHint.color = t.textSecondary
    m.setupUrl.color = t.accent

    m.list.ObserveField("rowItemSelected", "onRowSelected")

    m.rows = []
end sub

' Address of the local setup page, forwarded from the Scene at launch. The two
' labels are born hidden so this screen never flashes an address that has not
' been published yet.
sub SetSetupAddress(url as dynamic)
    if url = invalid then return
    if url = "" then return
    m.setupUrl.text = url
    m.setupHint.visible = true
    m.setupUrl.visible = true
end sub

' The scene calls this after a browser import so the still-open list updates.
sub RefreshInstalledRows()
    m.status.text = ""
    BuildRows()
end sub

function OnEnter(params as object) as void
    ' Returning from a keyboard or confirmation dialog must not erase current
    ' installation progress or the operation's result.
    if m.rows.Count() = 0 then m.status.text = ""
    BuildRows()
    m.list.callFunc("SetListFocus")
end function

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

' Rebuild the list: the add row first, then every installed add-on.
sub BuildRows()
    m.rows = []
    hasStreamSource = false
    m.rows.Push({
        action: "add"
        title: "Add add-on"
        value: "Connect a source"
    })
    m.rows.Push({action:"check",title:"Check add-ons",value:"Find problems"})
    if m.stores <> invalid
        for each addon in m.stores.addons.callFunc("AddonsGetAll")
            ' Configured addresses can carry provider keys in either their path
            ' or query. Display capabilities without exposing the address.
            value = AddonCapabilityText(addon)
            if AddonAdvertises(addon, "stream") then hasStreamSource = true
            m.rows.Push({
                action: "addon"
                id: addon.id
                name: addon.name
                builtin: addon.builtin
                title: addon.name
                value: value
            })
        end for
    end if

    content = CreateObject("roSGNode", "ContentNode")
    for each row in m.rows
        entry = content.CreateChild("ContentNode")
        item = entry.CreateChild("ContentNode")
        item.title = row.title
        item.description = row.value
    end for
    m.list.content = content

    installed = m.rows.Count() - 2
    if installed < 0 then installed = 0
    quantity = installed.ToStr() + " add-ons"
    if installed = 1 then quantity = "1 add-on"
    m.sub.text = quantity + " · Select Check add-ons for a connection report"
    if not hasStreamSource and m.status.text = "" then m.status.text = "Catalogs are ready. Add a configured stream source to play movies and shows."
end sub

function AddonAdvertises(addon as object, resourceName as string) as boolean
    if Type(addon.resources) <> "roArray" then return false
    for each resource in addon.resources
        if Type(resource) = "roAssociativeArray"
            if resource.name = resourceName then return true
        else if resource = resourceName
            return true
        end if
    end for
    return false
end function

function AddonCapabilityText(addon as object) as string
    labels = []
    if AddonAdvertises(addon, "stream") then labels.Push("Streams")
    if AddonAdvertises(addon, "catalog") then labels.Push("Catalogs")
    if AddonAdvertises(addon, "meta") then labels.Push("Title details")
    if AddonAdvertises(addon, "subtitles") then labels.Push("Subtitles")
    if labels.Count() = 0 then return "Configured add-on"
    if labels.Count() > 2 then return labels[0] + " + more"
    return labels.Join(" · ")
end function

sub onRowSelected()
    data = m.list.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[0]
    if index < 0 or index >= m.rows.Count() then return
    row = m.rows[index]
    if row.action = "add"
        ShowAddDialog()
    else if row.action = "check"
        m.top.pushRequest = {screen:"addonHealthScreen",params:{}}
    else
        ShowRemoveConfirm(row)
    end if
end sub

' Install flow: a KeyboardDialog whose OK kicks AddonsInstallTask.
sub ShowAddDialog()
    if m.top.getScene().dialog <> invalid then return
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    if dialog = invalid then dialog = CreateObject("roSGNode", "KeyboardDialog")
    if dialog = invalid
        m.status.text = "Keyboard unavailable. Use the browser setup address on this screen."
        return
    end if
    ' Palette and the array-shaped message are the two things that differ from
    ' the legacy node. See the same block in SettingsScreen for why each one
    ' fails quietly rather than loudly.
    dialog.title = "Add add-on"
    if dialog.HasField("keyboardDomain")
        dialog.message = ["Paste a configured HTTPS manifest URL using the browser address on this screen, or enter it below."]
    else
        dialog.message = "Enter your configured HTTPS manifest URL"
    end if
    dialog.text = ""
    dialog.buttons = ["OK", "Cancel"]
    dialog.observeField("buttonSelected", "onAddChoice")
    ' Keep configured URLs out of voice dictation and put the caret at the end.
    ApplyAddKeyboard(dialog)
    m.top.getScene().dialog = dialog
end sub

' Configure whichever internal editor the Roku keyboard exposes.
sub ApplyAddKeyboard(dialog as object) as void
    if dialog = invalid then return
    editor = invalid
    if dialog.HasField("textEditBox")
        editor = dialog.textEditBox
    else if dialog.HasField("keyboard") and dialog.keyboard <> invalid
        editor = dialog.keyboard.textEditBox
    end if
    if editor = invalid then return

    ' Provider links may contain private keys. Movie searches use voice input;
    ' this credential-bearing setup field stays keyboard-only.
    if editor.HasField("voiceEnabled") then editor.voiceEnabled = false
    ' Caret after the text rather than at 0, so backspace and the left arrow have
    ' something to act on: a caret parked at 0 makes both of them no-ops by
    ' definition while typing still appends, which from the outside is
    ' indistinguishable from a dead keyboard.
    if editor.HasField("cursorPosition") then editor.cursorPosition = Len(dialog.text)
end sub

sub onAddChoice()
    dialog = m.top.getScene().dialog
    if dialog <> invalid
        index = dialog.buttonSelected
        address = dialog.text
        ' StandardDialog's own dismissal, and the one ConfirmExitDialog already
        ' uses: setting close makes the scene drop the node from the dialog slot
        ' by itself. Both values are read above before anything is torn down.
        if dialog.HasField("close")
            dialog.close = true
        else
            m.top.getScene().dialog = invalid
        end if
        if index = 0
            StartInstall(address.Trim())
        end if
    end if
    m.list.callFunc("SetListFocus")
end sub

' Keyboard and browser requests share the scene's one import slot.
sub StartInstall(address as string)
    if m.stores = invalid then return
    scene = m.top.getScene()
    if scene = invalid then return
    if scene.callFunc("ImportFromSetup", address.Trim())
        m.status.text = "Installing… Check the result on this screen."
    else
        m.status.text = "An add-on is already installing. Wait for its result, then try again."
    end if
end sub

' Confirm removal of any add-on. Built-ins are shipped defaults, not sacred:
' the device is the user's, so they get the same two-step confirmation and the
' builtin flag disambiguates a shipped seed from a same-id installed mirror.
sub ShowRemoveConfirm(row as object)
    scene = m.top.getScene()
    if scene = invalid or scene.dialog <> invalid then return
    m.pendingRow = row
    nodeType = "StandardMessageDialog"
    dialog = CreateObject("roSGNode", nodeType)
    standard = true
    if dialog = invalid
        standard = false
        dialog = CreateObject("roSGNode", "Dialog")
    end if
    if dialog = invalid
        m.pendingRow = invalid
        m.status.text = "Removal dialog unavailable. Your add-on is unchanged."
        return
    end if
    dialog.title = "Remove " + row.name + "?"
    message = "This removes the add-on from this Roku. You will need its configured link to add it again."
    if row.builtin = true then message = "This disables a built-in search or subtitle add-on. Its manifest link is needed to restore it."
    if standard
        dialog.message = [message]
    else
        dialog.message = message
    end if
    dialog.buttons = ["Remove", "Cancel"]
    dialog.observeField("buttonSelected", "onRemoveChoice")
    m.top.getScene().dialog = dialog
end sub

sub onRemoveChoice()
    dialog = m.top.getScene().dialog
    if dialog <> invalid
        index = dialog.buttonSelected
        m.top.getScene().dialog = invalid
        if index = 0 and m.pendingRow <> invalid
            removed = m.stores.addons.callFunc("AddonsUninstall", m.pendingRow.id, m.pendingRow.builtin)
            if removed
                m.status.text = "Removed " + m.pendingRow.name + "."
            else
                m.status.text = "Could not remove " + m.pendingRow.name + "."
            end if
            BuildRows()
        end if
    end if
    m.pendingRow = invalid
    m.list.callFunc("SetListFocus")
end sub
