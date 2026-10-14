' StreamTile — wide stream card for StreamsScreen's list.
'
' RowList feeds each item its ContentNode through `itemContent` and drives focus
' through `itemHasFocus`/`rowHasFocus`. The primary line is the stream name
' (e.g. "4k DV | HDR10+"); the lines below are the stream title split
' at its embedded line feeds (release / file / peers-size / languages). The
' description field carries the whole multi-line title, split right here into
' however many rows the card fits — never pre-mapped onto fixed fields.
'
' The title sits outside the scroll and truncates with an ellipsis. The five
' description lines live in `cardContent`, which sits inside `cardClip` — a
' window that never moves. If any single line overflows 1022 px, `cardContent`
' slides left as one unit while the card holds focus (0.6s dwell before the first
' slide, 80 px/s, 1s dwell at the end, then snaps back). Unfocused cards stay
' pinned at x=0. Each line is an EmojiLabel (text in Open Sans, emoji as inline
' Twemoji posters). Measuring each line on its own keeps the block's vertical
' alignment intact.

sub init()
    m.border = m.top.FindNode("tileBorder")
    m.face = m.top.FindNode("tileFace")
    m.content = m.top.FindNode("cardContent")
    m.measureTimer = m.top.FindNode("measureTimer")
    m.scrollTimer = m.top.FindNode("scrollTimer")

    m.title = m.top.FindNode("tileTitle")
    m.quality = m.top.FindNode("tileQuality")
    m.lines = []
    for i = 1 to 3
        m.lines.Push(m.top.FindNode("tileLine" + i.ToStr()))
    end for

    t = Theme()
    m.title.color = t.textPrimary
    m.quality.color = t.accentInfo
    m.lines[0].color = t.textPrimary
    for i = 1 to m.lines.Count() - 1
        m.lines[i].color = t.textSecondary
    end for

    SetCardFont()

    ' Scroll parameters: speed in pixels per second; dwell in seconds; interval
    ' matches the scrollTimer's duration (the tick counter turns seconds into
    ' ticks). 0.6 s start dwell to be easy to read, especially for the first
    ' glimpse of a newly focused card.
    m.speed = 80.0
    m.startHold = 0.6
    m.endHold = 1.5
    m.interval = 0.03
    ' Slide this far past the end of the text, so the last glyph clears the card
    ' edge with a little air instead of sitting flush against it. Two characters
    ' at the body size is roughly 30 px (Open Sans averages ~0.55 em advance).
    m.tailPad = 30.0

    m.overflow = 0.0
    m.travel = 0.0
    m.tick = 0
    m.step = 0.0
    m.startTicks = 0.0
    m.travelTicks = 0.0
    m.endTicks = 0.0

    m.measureTimer.observeField("fire", "onMeasureTick")
    m.scrollTimer.observeField("fire", "onScrollTick")

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")
end sub

' Create one shared Font node per card size — title (32 bold) and body lines
' (27 regular) — from the bundled Open Sans faces and hang them on the lines.
' Two nodes cover all six; assigning the same Font to several labels is fine,
' and keeping them as children holds them for the tile's lifetime. Latin text
' runs inside each EmojiLabel use these; emoji get drawn as posters instead.
sub SetCardFont()
    titleSize = 32
    bodySize = 27
    m.cardTitleFont = CreateObject("roSGNode", "Font")
    m.cardTitleFont.uri = "pkg:/fonts/OpenSans-Bold.ttf"
    m.cardTitleFont.size = titleSize
    m.cardBodyFont = CreateObject("roSGNode", "Font")
    m.cardBodyFont.uri = "pkg:/fonts/OpenSans-Regular.ttf"
    m.cardBodyFont.size = bodySize
    m.top.AppendChild(m.cardTitleFont)
    m.top.AppendChild(m.cardBodyFont)
    m.title.font = m.cardTitleFont
    for each line in m.lines
        line.font = m.cardBodyFont
    end for
end sub

' Park the block at its start and stop burning ticks.
sub stopScroll()
    m.scrollTimer.control = "stop"
    m.tick = 0
    m.content.translation = [0, 0]
end sub

' Every inbound field change re-applies the whole look from the tile's current
' field values. RowList recycles item components for new cells and content
' swaps, and rowHasFocus/itemHasFocus only fire on value *changes* — on a
' recycle nothing may change except itemContent, so unless the look is rebuilt
' there a tile carries stale dimming (opacity 0.55) into a fresh RowList on
' another screen/media.
sub UpdateLook()
    t = Theme()
    if m.top.itemHasFocus
        m.border.color = t.accentFocus
        m.face.color = t.itemFace
    else
        m.border.color = t.accentClear
        m.face.color = t.tileFace
    end if
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.82

    if m.top.itemHasFocus
        m.measureTimer.control = "start"
    else
        m.measureTimer.control = "stop"
        stopScroll()
    end if
end sub

sub onItemContentChanged()
    if m.top.itemContent = invalid
        m.title.text = ""
        m.quality.text = ""
        for each line in m.lines
            line.text = ""
        end for
        m.measureTimer.control = "stop"
        stopScroll()
        return
    end if
    m.title.text = m.top.itemContent.title
    m.quality.text = m.top.itemContent.qualityBadge
    if m.quality.text = invalid or m.quality.text = "" then m.quality.text = "Resolution not supplied"
    description = m.top.itemContent.description
    if description = invalid then description = ""
    pieces = description.Split(chr(10))
    for i = 0 to m.lines.Count() - 1
        text = ""
        if pieces <> invalid and i < pieces.Count() then text = pieces[i]
        m.lines[i].text = text
    end for
    stopScroll()
    m.measureTimer.control = "start"
    UpdateLook()
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

sub onRowHasFocusChanged()
    UpdateLook()
end sub

sub onMeasureTick()
    ' Widest of the five scrolling lines. Summing each line's own reported width
    ' is more robust than asking a LayoutGroup for a single bounding rectangle.
    ' The title is not measured: it does not scroll, it truncates.
    widest = 0
    measured = false

    for each line in m.lines
        lw = line.callFunc("contentWidth")
        if lw > 0 then
            measured = true
            if lw > widest then widest = lw
        end if
    end for

    ' If not one line reported a width while lines do carry text, the laid-out
    ' measurement is not available on this device — estimate from the character
    ' count instead of concluding that nothing overflows. A short line drifting a
    ' little is cosmetic; a line that never scrolls is the bug this replaced, and
    ' both silent failures look identical from the sofa.
    if measured = false
        widest = EstimateContentWidth()
    end if

    ' Lines are inset 18 px and the window is 1022 px wide, so 18 + widest - 1022
    ' is the travel that puts the last glyph fully inside the card edge.
    widthCap = 1004
    m.overflow = widest - widthCap

    if m.overflow <= 0
        stopScroll()
        return
    end if

    ' Slide past the end by a couple of characters so the last glyph clears the
    ' card edge with air around it instead of stopping flush against it. Two
    ' characters at the body size is about 30 px (0.55 em average advance).
    m.travel = m.overflow + m.tailPad

    m.step = m.speed * m.interval
    m.startTicks = m.startHold / m.interval
    m.travelTicks = int(m.travel / m.step) + 1
    if m.travelTicks < 1 then m.travelTicks = 1
    m.endTicks = m.endHold / m.interval

    if m.top.itemHasFocus
        m.tick = 0
        m.content.translation = [0, 0]
        m.scrollTimer.control = "start"
    end if
end sub

sub onScrollTick()
    if m.top.itemHasFocus = false or m.overflow <= 0
        stopScroll()
        return
    end if

    m.tick = m.tick + 1

    if m.tick <= m.startTicks
        m.content.translation = [0, 0]
        return
    end if

    if m.tick <= m.startTicks + m.travelTicks
        x = m.step * (m.tick - m.startTicks)
        if x > m.travel then x = m.travel
        m.content.translation = [-x, 0]
        return
    end if

    ' Sit at the far end long enough to actually read the tail before the block
    ' jumps back to its start.
    if m.tick <= m.startTicks + m.travelTicks + m.endTicks
        m.content.translation = [-m.travel, 0]
        return
    end if

    m.tick = 0
    m.content.translation = [0, 0]
end sub

' Width fallback used only when no line reported a laid-out width. Average
' Open Sans advance of 0.55 em per character, at the body text size.
function EstimateContentWidth() as float
    widest = 0
    for each line in m.lines
        w = EstimateLineWidth(line.text, 27)
        if w > widest then widest = w
    end for
    return widest
end function

function EstimateLineWidth(text as string, fontSize as float) as float
    if text = invalid or text = "" then return 0.0
    return len(text) * fontSize * 0.55
end function
