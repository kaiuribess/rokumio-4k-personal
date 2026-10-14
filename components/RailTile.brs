' RailTile — square icon tile for the Home left rail. Same field plumbing as
' every tile: RowList feeds seed the ContentNode through itemContent and drive
' focus through itemHasFocus / rowHasFocus. The glyph is read from
' itemContent.title.

sub init()
    m.border = m.top.FindNode("railBorder")
    m.glyph = m.top.FindNode("railGlyph")
    m.zoomAnim = m.top.FindNode("zoomAnim")
    m.label = m.top.FindNode("railLabel")

    m.border.color = Theme().accentClear

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
        m.zoomAnim.control = "start"
        m.glyph.blendColor = t.accent
        m.label.color = t.accentFocus
        m.border.color = t.itemFace
        m.top.opacity = 1.0
    else
        m.zoomAnim.control = "stop"
        m.glyph.scale = [1.0,1.0]
        m.glyph.blendColor = t.textSecondary
        m.label.color = t.textPrimary
        m.border.color = t.accentClear
        m.top.opacity = 0.88
    end if
end sub

sub onItemContentChanged()
    if m.top.itemContent = invalid then return
    ' Unconditional for the same reason as PosterTile: re-assigning the uri is
    ' what makes Roku re-request an evicted texture, so guarding it strands the
    ' icon blank on a recycled tile.
    m.glyph.uri = m.top.itemContent.title
    m.label.text = m.top.itemContent.description
    UpdateLook()
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

sub onRowHasFocusChanged()
    UpdateLook()
end sub
