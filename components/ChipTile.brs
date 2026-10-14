' ChipTile — focusable label tile for the single-row RowLists (season chips,
' movie action buttons). Same field plumbing as PosterTile: RowList feeds the
' ContentNode through itemContent and drives focus through itemHasFocus /
' rowHasFocus. Text is read from itemContent.title.

sub init()
    m.face = m.top.FindNode("chipFace")
    m.text = m.top.FindNode("chipText")

    t = Theme()
    m.text.color = t.textSecondary

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")
end sub

' Every inbound field change re-applies the whole look from the tile's current
' field values. RowList recycles item components for new cells and content
' swaps, and rowHasFocus/itemHasFocus only fire on value *changes* — on a
' recycle nothing may change except itemContent, so unless the look is rebuilt
' there a tile carries stale dimming into a fresh RowList on
' another screen/media.
sub UpdateLook()
    t = Theme()
    if m.top.itemHasFocus
        m.face.color = t.itemFace
        m.text.color = t.textPrimary
    else
        m.face.color = t.tileFace
        m.text.color = t.textSecondary
    end if
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.8
end sub

sub onItemContentChanged()
    content = m.top.itemContent
    m.text.text = ""
    w = 240
    h = 56
    if content <> invalid
        if GetInterface(content.title, "ifString") <> invalid then m.text.text = content.title
        if content.width <> invalid and content.width > 16 then w = content.width
        if content.height <> invalid and content.height > 16 then h = content.height
    end if
    ' Both insets are measured from the RowList cell, including their origins.
    ' Reapply defaults too: a recycled chip must not keep the last cell's size.
    m.face.width = w - 8
    m.text.width = w - 16
    m.face.height = h - 8
    m.text.height = h - 16
    UpdateLook()
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

sub onRowHasFocusChanged()
    UpdateLook()
end sub
