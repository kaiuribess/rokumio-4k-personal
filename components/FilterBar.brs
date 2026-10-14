' FilterBar — see FilterBar.xml for the interface and ownership split. The
' chips row and the dropdown are rebuilt from {raw,label} entries the screen
' hands over; the active chip is remembered so SetChips can preserve focus and
' ShowMenu hangs under the right chip. All geometry lives here so it cannot
' drift between the two screens that embed this component.
sub init()
    m.chips = m.top.FindNode("chips")
    m.menuGroup = m.top.FindNode("menuGroup")
    m.menuBackdrop = m.top.FindNode("menuBackdrop")
    m.menu = m.top.FindNode("menu")

    t = Theme()
    m.menuBackdrop.color = t.dropdownBg
    m.menu.focusBitmapBlendColor = t.accentFocus
    m.chips.focusBitmapBlendColor = t.accentFocus

    m.chips.ObserveField("rowItemSelected", "onChipPressed")
    m.menu.ObserveField("rowItemSelected", "onMenuPressed")

    m.chipPitch = 272
    m.menuY = 68
    m.entries = []
    m.activeChip = 0
end sub

' Rebuild the chip row from {raw,label} entries, keeping the focused chip within
' range. Focus is untouched — the screen decides where focus lands.
sub SetChips(entries as object)
    m.entries = entries
    if m.activeChip >= entries.Count() then m.activeChip = entries.Count() - 1

    content = CreateObject("roSGNode", "ContentNode")
    row = content.CreateChild("ContentNode")
    for each entry in entries
        item = row.CreateChild("ChipContent")
        item.title = entry.label
        item.width = m.chips.rowItemSize[0][0]
        item.height = m.chips.rowItemSize[0][1]
    end for
    m.chips.content = content
    m.chips.jumpToRowItem = [0, m.activeChip]
end sub

' OK on a chip: publish the activated chip; the screen answers with ShowMenu.
sub onChipPressed()
    data = m.chips.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    chip = data[1]
    if chip < 0 or chip >= m.entries.Count() then return
    m.activeChip = chip
    m.top.chipActivated = chip
end sub

' The screen packed the chip's options and the index of the current value; the
' dropdown opens under the activating chip and pre-scrolls so whatever is
' focused is the value OK will commit.
sub ShowMenu(options as object, currentIndex as integer)
    content = CreateObject("roSGNode", "ContentNode")
    for each option in options
        row = content.CreateChild("ContentNode")
        item = row.CreateChild("ChipContent")
        item.title = option.label
        item.width = m.menu.rowItemSize[0][0]
        item.height = m.menu.rowItemSize[0][1]
    end for
    m.menu.content = content

    shown = options.Count()
    if shown > 9 then shown = 9
    m.menu.numRows = shown
    m.menuBackdrop.height = shown * 56 + (shown - 1) * 6 + 4

    ' Hang the menu under the activating chip, not always the first one.
    m.menuGroup.translation = [m.activeChip * m.chipPitch, m.menuY]

    m.menuGroup.visible = true
    m.menu.jumpToRowItem = [currentIndex, 0]
    m.menu.SetFocus(true)
end sub

' OK inside the dropdown: publish {chip, index} so the screen commits its own
' effect (the re-pick-current-value rule lives with the screen, which knows the
' current raw values).
sub onMenuPressed()
    data = m.menu.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[0]
    if index < 0 then return
    m.top.optionPicked = { chip: m.activeChip, index: index }
end sub

' Dismiss the dropdown and hand focus back to the chips.
sub HideMenu()
    m.menuGroup.visible = false
    m.chips.SetFocus(true)
end sub

sub FocusChips()
    m.chips.SetFocus(true)
end sub

function FocusIsOnChips() as boolean
    return m.chips.HasFocus()
end function

function IsMenuOpen() as boolean
    return m.menuGroup.visible
end function

' Menu open: Back/options dismisses (nothing changes) and the arrow keys are
' kept inside the dropdown instead of leaking to the screen/Scene. With the
' menu closed, keys fall through to the embedding screen.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if m.menuGroup.visible
        if key = "back"
            HideMenu()
            return true
        end if
        if key = "options"
            HideMenu()
            return true
        end if
        if key = "up" or key = "down" or key = "left" or key = "right"
            return true
        end if
        return false
    end if
    return false
end function
