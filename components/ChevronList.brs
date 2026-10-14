' ChevronList — a single-column RowList with a fixed visible window and
' chevron-up/down markers that appear when items sit hidden above or below the
' window.
'
' The window is "floatingFocus": the list does not scroll until focus passes
' the last visible row, and then it scrolls by len so the focused row lands at
' an edge. Only the visible bounds matter for the markers, so they are kept as
' state and updated only when focus actually crosses an edge; movement inside
' the window scrolls nothing and the chevrons stay put. Up shows whenever row 0
' is hidden above; down whenever the last row is hidden below.
'
' Geometry (numRows, itemWidth, rowHeight) drives both the RowList config and
' the chevron placement, so consumers only pick numbers. Replacing content
' resets the window to the top. The focused/selected [row, col] pairs are
' re-emitted on this component's own fields for consumers to observe.

sub init()
    m.rowList = m.top.FindNode("rowList")
    m.chevronUp = m.top.FindNode("chevronUp")
    m.chevronDown = m.top.FindNode("chevronDown")

    m.chevronUp.width = 48
    m.chevronUp.height = 28
    m.chevronDown.width = 48
    m.chevronDown.height = 28

    t = Theme()
    m.rowlist.focusBitmapBlendColor = t.accentFocus

    m.rowList.ObserveField("rowItemFocused", "onRowItemFocused")
    m.rowList.ObserveField("rowItemSelected", "onRowItemSelected")
    m.top.ObserveField("content", "onContent")
    m.top.ObserveField("numRows", "onGeometry")
    m.top.ObserveField("itemWidth", "onGeometry")
    m.top.ObserveField("rowHeight", "onGeometry")
    m.top.ObserveField("rowComponent", "onGeometry")

    m.firstVisible = 0
    m.lastVisible = m.top.numRows - 1
    RecomputeGeometry()
    UpdateWindow()
end sub

sub SetListFocus()
    m.rowList.SetFocus(true)
end sub

sub onContent()
    m.rowList.content = m.top.content
    m.rowList.jumpToRowItem = [0, 0]
    m.firstVisible = 0
    m.lastVisible = m.top.numRows - 1
    UpdateWindow()
end sub

sub onGeometry()
    RecomputeGeometry()
    UpdateWindow()
end sub

' Forward the focus pair and refresh the markers.
sub onRowItemFocused()
    m.top.rowItemFocused = m.rowList.rowItemFocused
    UpdateWindow()
end sub

sub onRowItemSelected()
    m.top.rowItemSelected = m.rowList.rowItemSelected
end sub

' Apply geometry to the RowList and place the chevrons around the window.
sub RecomputeGeometry()
    numVisible = m.top.numRows
    if numVisible < 1 then numVisible = 1
    rowSlot = m.top.rowHeight + 8

    m.rowList.numRows = numVisible
    m.rowList.itemSize = [m.top.itemWidth, rowSlot]
    m.rowList.itemSpacing = [0, 8]
    m.rowList.rowItemSize = [[m.top.itemWidth, m.top.rowHeight]]
    m.rowList.itemComponentName = m.top.rowComponent

    listHeight = numVisible * rowSlot + (numVisible - 1) * 8
    cx = (m.top.itemWidth - 48) / 2
    if cx < 0 then cx = 0
    m.chevronUp.translation = [cx, -28 - 8]
    m.chevronDown.translation = [cx, listHeight + 8]

    m.firstVisible = 0
    m.lastVisible = numVisible - 1
end sub

' Shift the tracked window only when focus crosses an edge, then show the
' chevrons whenever content is hidden on that side.
sub UpdateWindow()
    data = m.rowList.rowItemFocused
    index = 0
    if data <> invalid and data.Count() > 0 then index = data[0]

    total = 0
    node = m.rowList.content
    if node <> invalid then total = node.GetChildCount()
    if total < 1 then total = 1

    numVisible = m.top.numRows
    if index > m.lastVisible
        m.firstVisible = index - (numVisible - 1)
        m.lastVisible = index
    else if index < m.firstVisible
        m.firstVisible = index
        m.lastVisible = index + (numVisible - 1)
    end if
    if m.firstVisible < 0 then m.firstVisible = 0
    if m.lastVisible > total - 1 then m.lastVisible = total - 1

    if not m.top.showChevrons
        m.chevronUp.visible = false
        m.chevronDown.visible = false
        return
    end if
    m.chevronUp.visible = m.firstVisible > 0
    m.chevronDown.visible = m.lastVisible < total - 1
end sub
