' PrefRow — wide focusable row for the Settings and Add-ons lists. Same field
' plumbing as every tile: RowList feeds the ContentNode through itemContent and
' drives focus through itemHasFocus / rowHasFocus. The left/bold title and the
' right/muted value come from itemContent.title / itemContent.description.

sub init()
    m.face = m.top.FindNode("rowFace")
    m.title = m.top.FindNode("rowTitle")
    m.value = m.top.FindNode("rowValue")

    t = Theme()
    m.title.color = t.textPrimary
    m.value.color = t.textSecondary

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")
end sub

' Every inbound field change re-applies the whole look from the tile's current
' field values (see StreamTile.UpdateLook: RowList recycles items, so the look
' must be rebuilt on itemContent changes too, or a recycled tile carries stale
' dimming into a fresh row).
sub UpdateLook()
    t = Theme()
    if m.top.itemHasFocus
        m.face.color = t.itemFace
        m.value.color = t.textPrimary
    else
        m.face.color = t.tileFace
        m.value.color = t.textSecondary
    end if
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.55
end sub

sub onItemContentChanged()
    if m.top.itemContent = invalid then return
    m.title.text = m.top.itemContent.title
    value = m.top.itemContent.description
    if value = invalid then value = ""
    m.value.text = value
    UpdateLook()
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

sub onRowHasFocusChanged()
    UpdateLook()
end sub
