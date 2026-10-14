' PosterTile — custom list-item component used by the Home catalog rows.
'
' MarkupGrid/RowList feed each item its ContentNode through the interface field
' `itemContent` and drive focus through `itemHasFocus`/`rowHasFocus` (they never
' touch `content` or `focused`). The artwork comes from the item's
' hdPosterUrl (mapped from the addon meta's poster). A tile is either artwork or
' the artless unit (a flat face plus the title), never a blend of the two:
' ShowArtless/ShowPoster swap them as a unit on the poster's own loadStatus, so
' the face stops rendering entirely once artwork paints instead of lingering
' behind it where it still showed through on unfocused rows. No URL, a URL still
' downloading, and a URL that failed all show the title. Poster.loadStatus is
' none / loading / ready / failed — "ready" is the success value, and there is no
' "loaded"; see the Poster field reference.
'
' Artwork retains a readable title caption. Two optional overlays ride on
' itemContent: `progress` (0..1) draws the bottom continue-watching bar, and
' `watchedGlyph` ("eye" | "clock") draws the top-right badge.

sub init()
    m.artless = m.top.FindNode("artless")
    m.poster = m.top.FindNode("poster")
    m.tileBg = m.top.FindNode("tileBg")
    m.titleText = m.top.FindNode("titleText")
    m.titleCaption = m.top.FindNode("titleCaption")
    m.captionBg = m.top.FindNode("captionBg")
    m.captionText = m.top.FindNode("captionText")
    m.loadSpinner = m.top.FindNode("loadSpinner")
    m.progressTrack = m.top.FindNode("progressTrack")
    m.progressFill = m.top.FindNode("progressFill")
    m.watchedBadge = m.top.FindNode("watchedBadge")
    m.watchedPlate = m.top.FindNode("watchedPlate")
    m.watchedGlyph = m.top.FindNode("watchedGlyph")

    t = Theme()
    m.tileBg.color = t.tileFace
    m.titleText.color = t.textPrimary
    m.captionBg.color = t.screenBg
    m.captionText.color = t.textPrimary
    m.progressTrack.color = t.progressTrack
    m.progressFill.color = t.progressFill
    m.watchedPlate.color = t.glyphPlate

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")
    m.poster.ObserveField("loadStatus", "onPosterLoadStatus")

    ApplyTileSize()
end sub

' RowList writes each item's cell size into the width/height interface fields,
' one row at a time. Home gives channel/tv rows square cells, so the tile has
' to follow: resize the poster (and the caps that keep its texture bounded —
' loadWidth/loadHeight ride the node so the memory policy holds for the new
' size too), plus the artless face, the title, the progress bar and the watched
' badge, which are all laid out against the fixed 270x405 slab in XML.
'
' This must run on EVERY size change, portrait included. RowList recycles one
' tile instance across rows, so a square channel cell can be reused for a 2:3
' movie/series cell; a portrait early-return here left that recycled tile at the
' previous row's 270x270 geometry — square artwork inside a 2:3 slot, the
' progress bar stranded mid-tile, the title box scaled for a square. Rebuilding
' the whole layout every time is what heals the recycle (fresh tiles simply
' compute the same portrait numbers the XML already laid out).
'
' The artless title has equal horizontal padding in every shape. The portrait
' spinner preserves its original origin; other shapes center it within the cell.
sub ApplyTileSize()
    w = m.top.width
    h = m.top.height
    if w = invalid or h = invalid then return
    if w <= 0 or h <= 0 then return

    m.poster.width = w
    m.poster.height = h
    m.poster.loadWidth = w
    m.poster.loadHeight = h
    m.tileBg.width = w
    m.tileBg.height = h
    m.titleText.width = w - 24
    m.titleText.height = h - 16
    m.titleText.translation = [12, 8]
    m.titleCaption.translation = [0, h - 80]
    m.captionBg.width = w
    m.captionText.width = w - 24
    m.progressTrack.width = w
    m.progressTrack.translation = [0, h - 8]
    m.progressFill.translation = [0, h - 8]
    m.progressFill.width = w
    m.watchedBadge.translation = [w - 62, 8]

    if w = 270 and h = 405
        m.loadSpinner.translation = [113, 163]
    else
        m.loadSpinner.translation = [(w - 44) / 2, (h - 44) / 2]
    end if

    if m.top.itemContent <> invalid then UpdateOverlays()
end sub

' Every focus observer re-applies the whole look from the tile's current field
' values. RowList recycles item components for new cells and content swaps, and
' those observers only fire on value *changes* — on a recycle nothing may change
' except itemContent, so unless the look is rebuilt there a tile carries stale
' dimming into a fresh row on another screen/media.
sub UpdateLook()
    t = Theme()
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.8
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

' A whole row dims when its list row loses focus (user moved to another row),
' reinforcing which row the "selected" indicator sits in.
sub onRowHasFocusChanged()
    UpdateLook()
end sub

sub onItemContentChanged()
    ' A list can clear/recycle a realized cell before assigning its next title.
    ' Drop every visible label and overlay immediately, including cached artwork.
    m.captionText.text = ""
    m.titleText.text = ""
    if m.top.itemContent = invalid
        m.poster.uri = ""
        m.loadSpinner.control = "stop"
        m.loadSpinner.visible = false
        ShowArtless()
        UpdateOverlays()
        UpdateLook()
        return
    end if
    title = ""
    if GetInterface(m.top.itemContent.title, "ifString") <> invalid then title = m.top.itemContent.title
    m.titleText.text = title
    m.captionText.text = title
    loading = m.top.itemContent.loadState = "loading"
    if loading
        m.loadSpinner.visible = true
        m.loadSpinner.control = "start"
        m.poster.uri = ""
        ShowArtless()
        UpdateOverlays()
        UpdateLook()
        return
    end if

    ' Only Search sets loadState, and it defaults off here — every other screen
    ' that reuses PosterTile is unaffected. A recycled tile must not carry a
    ' spinning-but-hidden spinner into its next cell, so always stop it when not
    ' loading.
    m.loadSpinner.control = "stop"
    m.loadSpinner.visible = false

    poster = m.top.itemContent.hdPosterUrl
    if GetInterface(poster, "ifString") = invalid then poster = ""
    ' Assigned unconditionally, and that is deliberate. Re-assigning the same uri
    ' is what makes Roku re-request a texture the memory manager has evicted, so
    ' a "has this changed?" guard here would leave a recycled cell showing the
    ' artless face forever: uri matches, no new load is requested, loadStatus
    ' never re-fires, and the forced ShowArtless below never gets undone.
    m.poster.uri = poster
    UpdateOverlays()
    ' Forced rather than read back from loadStatus: the uri was just set, so
    ' this cell is artless whatever the status field still reports from the
    ' previous one.
    ShowArtless()
    ' A uri that resolves from cache can settle before the observer ever fires,
    ' so re-read the status now instead of trusting the callback alone.
    if m.poster.loadStatus = "ready" or m.poster.loadStatus = "failed" then onPosterLoadStatus()
    UpdateLook()
end sub

sub onPosterLoadStatus()
    if m.poster.loadStatus = "ready" then ShowPoster() else ShowArtless()
end sub

' The artless unit: the face plus the title. The poster is left alone on purpose
' — it is visible from the start and paints nothing until it has a bitmap, so
' there is nothing to hide here.
sub ShowArtless()
    m.artless.visible = true
    m.titleCaption.visible = false
end sub

' The artwork has painted, so the face must stop rendering rather than sit
' behind the artwork where it still shows through on unfocused rows. Only this
' group is hidden; hiding the poster itself would deadlock the load against the
' gate waiting on it.
sub ShowPoster()
    ' A ready notification from the previous URI can arrive after this cell is
    ' emptied or reused for a search placeholder. Keep that new title visible.
    if m.top.itemContent = invalid or m.poster.uri = ""
        ShowArtless()
        return
    end if
    if m.top.itemContent.loadState = "loading"
        ShowArtless()
        return
    end if
    m.artless.visible = false
    m.titleCaption.visible = m.captionText.text <> ""
end sub

' The progress bar and watched glyph are driven entirely by optional
' itemContent fields, so a tile reused without them (or recycled onto one
' without them) never shows a stale overlay.
sub UpdateOverlays()
    if m.top.itemContent = invalid
        m.progressTrack.visible = false
        m.progressFill.visible = false
        m.watchedBadge.visible = false
        m.watchedGlyph.uri = ""
        return
    end if
    progress = m.top.itemContent.progress
    if progress <> invalid and progress > 0 and progress <= 1
        m.progressFill.width = m.poster.width * progress
        m.progressTrack.visible = true
        m.progressFill.visible = true
    else
        m.progressFill.width = m.poster.width
        m.progressTrack.visible = false
        m.progressFill.visible = false
    end if

    glyph = m.top.itemContent.watchedGlyph
    if glyph = "eye" or glyph = "clock"
        m.watchedGlyph.uri = "pkg:/images/" + glyph + ".png"
        m.watchedBadge.visible = true
    else
        m.watchedBadge.visible = false
        m.watchedGlyph.uri = ""
    end if
end sub
