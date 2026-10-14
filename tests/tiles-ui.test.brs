sub ResetChip()
    m.top = { itemContent: invalid, itemHasFocus: false, rowHasFocus: false }
    m.face = { width: 800, height: 800 }
    m.text = { text: "Previous title", width: 780, height: 780 }
end sub

sub ResetPoster()
    m.top = { itemContent: invalid, itemHasFocus: false, rowHasFocus: false, width: 216, height: 324 }
    m.artless = { visible: false }
    m.poster = { uri: "https://example.invalid/old.jpg", width: 270, height: 405, loadStatus: "ready" }
    m.tileBg = {}
    m.titleText = { text: "Previous artless title" }
    m.titleCaption = { visible: true }
    m.captionBg = {}
    m.captionText = { text: "Previous caption" }
    m.loadSpinner = { visible: true, control: "start" }
    m.progressTrack = { visible: true }
    m.progressFill = { visible: true }
    m.watchedBadge = { visible: true }
    m.watchedGlyph = { uri: "pkg:/images/eye.png" }
end sub

Harness_Suite("Chip cell padding and content recycling")
ResetChip()
Chip_onItemContentChanged()
Harness_Equal(m.text.text, "", "empty recycled chip clears its former label")
Harness_Equal(m.face.width, 232, "missing chip dimensions reset the default face width")
Harness_Equal(m.text.width, 224, "missing chip dimensions reset the default text width")
Harness_Equal(m.face.height, 48, "missing chip dimensions reset the default face height")
Harness_Equal(m.text.height, 40, "missing chip dimensions reset the default text height")
m.top.itemContent = { title: "Choose stream", width: 260, height: 56 }
m.top.itemHasFocus = true
m.top.rowHasFocus = true
Chip_onItemContentChanged()
Harness_Equal(m.text.text, "Choose stream", "replacement chip displays its own label")
Harness_Equal(m.face.width, 252, "four pixel face inset fits inside the entire cell")
Harness_Equal(m.text.width, 244, "eight pixel text inset leaves equal left/right padding")
Harness_Equal(m.face.height, 48, "content.height controls the inset face")
Harness_Equal(m.text.height, 40, "content.height controls the inset text")
Harness_Equal(m.top.opacity, 1.0, "focused chip row stays fully readable")
Harness_Equal(m.face.color, Theme().itemFace, "selected chip uses the selected face")
m.top.itemContent = { title: "Larger action", width: 420, height: 72 }
Chip_onItemContentChanged()
Harness_Equal(m.face.width, 412, "wider recycled chip resizes its face")
Harness_Equal(m.text.height, 56, "taller recycled chip resizes its text")
m.top.itemContent = { title: "Default action", width: 0, height: 0 }
m.top.itemHasFocus = false
m.top.rowHasFocus = false
Chip_onItemContentChanged()
Harness_Equal(m.face.width, 232, "native zero-value dimensions safely restore default geometry")
Harness_Equal(m.top.opacity, 0.8, "unfocused chip remains legible")
Harness_Equal(m.face.color, Theme().tileFace, "recycled unfocused chip clears selected appearance")

Harness_Suite("Poster caption geometry follows every tile shape")
ResetPoster()
Poster_ApplyTileSize()
Harness_Equal(m.poster.width, 216, "poster follows the actual compact cell width")
Harness_Equal(m.poster.loadHeight, 324, "decode cap follows the actual compact cell height")
Harness_Equal(m.titleCaption.translation[1], 244, "caption fits above the progress strip")
Harness_Equal(m.captionBg.width, 216, "caption plate spans the compact cell")
Harness_Equal(m.captionText.width, 192, "caption leaves equal twelve pixel padding")
Harness_Equal(m.titleText.translation[0], 12, "artless label uses symmetric left padding")
m.top.width = 480
m.top.height = 270
Poster_ApplyTileSize()
Harness_Equal(m.captionBg.width, 480, "landscape caption grows with its cell")
Harness_Equal(m.captionText.width, 456, "landscape caption keeps equal padding")
Harness_Equal(m.titleCaption.translation[1], 190, "landscape caption stays at its own bottom")
m.top.width = 270
m.top.height = 405
Poster_ApplyTileSize()
Harness_Equal(m.titleCaption.translation[1], 325, "recycling landscape to portrait restores the caption origin")
Harness_Equal(m.progressTrack.translation[1], 397, "progress bar stays below the caption")
Harness_Equal(m.poster.loadWidth, 270, "portrait decode cap is restored")

Harness_Suite("Actual content and artwork callbacks keep titles readable")
ResetPoster()
Poster_ApplyTileSize()
Poster_onItemContentChanged()
Harness_Equal(m.captionText.text, "", "empty recycled tile drops old caption text")
Harness_Equal(m.titleText.text, "", "empty recycled tile drops old artless text")
Harness_Equal(m.poster.uri, "", "empty recycled tile drops old artwork")
Harness_Equal(m.titleCaption.visible, false, "empty tile has no stale caption plate")
Harness_Equal(m.watchedBadge.visible, false, "empty tile drops old watched badge")
Harness_Equal(m.progressTrack.visible, false, "empty tile drops old progress bar")
Harness_Equal(m.loadSpinner.control, "stop", "empty tile stops a recycled loading spinner")
m.top.itemContent = { title: "New movie", hdPosterUrl: "https://example.invalid/new.jpg", progress: 0.5, watchedGlyph: "clock" }
m.poster.loadStatus = "loading"
Poster_onItemContentChanged()
Harness_Equal(m.titleText.text, "New movie", "loading artwork still exposes the current title")
Harness_Equal(m.captionText.text, "New movie", "caption is prepared from the actual current title")
Harness_Equal(m.artless.visible, true, "artless fallback remains while artwork loads")
Harness_Equal(m.titleCaption.visible, false, "loaded-art caption remains hidden while artwork loads")
Harness_Equal(m.progressFill.width, 108, "current progress uses actual cell width")
Harness_Equal(m.watchedGlyph.uri, "pkg:/images/clock.png", "current watched overlay replaces its predecessor")
m.poster.loadStatus = "ready"
Poster_onPosterLoadStatus()
Harness_Equal(m.artless.visible, false, "ready artwork hides the loading face")
Harness_Equal(m.titleCaption.visible, true, "loaded artwork keeps the actual title readable")
Harness_Equal(m.top.opacity, 0.8, "unfocused poster rows retain readable contrast")
m.top.rowHasFocus = true
Poster_onRowHasFocusChanged()
Harness_Equal(m.top.opacity, 1.0, "focused poster rows restore full contrast")
m.top.itemContent = { title: "Next title", hdPosterUrl: "https://example.invalid/next.jpg" }
m.poster.loadStatus = "failed"
Poster_onItemContentChanged()
Harness_Equal(m.captionText.text, "Next title", "recycling updates caption even after an image failure")
Harness_Equal(m.titleText.text, "Next title", "failed image fallback uses the new title")
Harness_Equal(m.titleCaption.visible, false, "failed image uses one readable artless title")
Harness_Equal(m.progressFill.visible, false, "replacement without progress drops the old bar")
Harness_Equal(m.watchedGlyph.uri, "", "replacement without a badge releases the old glyph")
m.top.itemContent = { title: "Searching…", loadState: "loading" }
m.poster.loadStatus = "ready"
Poster_onItemContentChanged()
Poster_onPosterLoadStatus()
Harness_Equal(m.loadSpinner.control, "start", "search placeholder starts its own spinner")
Harness_Equal(m.artless.visible, true, "late ready notification cannot hide a search placeholder")
Harness_Equal(m.titleCaption.visible, false, "search placeholder does not expose an artwork caption")
m.top.itemContent = { title: "No image" }
Poster_onItemContentChanged()
Poster_onPosterLoadStatus()
Harness_Equal(m.loadSpinner.control, "stop", "nonloading replacement stops the former spinner")
Harness_Equal(m.artless.visible, true, "cached ready notification cannot erase a title without artwork")

Harness_Finish()
if m.failed > 0
    bad = invalid
    x = bad.poison
end if
