' TileSize unit tests — the shared cell-size rules drive every grid row on the
' device (Home/Discover/Search), so the shape mapping cannot drift.
' PosterShapeName folds a Stremio posterShape value (the spec spells 1:0.675 as
' "regular", the SDK as "poster") to one canonical name, TileCellSize picks a
' row's cell from that shape or the content-type fallback, TilePosterShape folds
' a row of metas into a single shape by majority vote so a whole row adapts
' together, and TileColumns fits that cell across a grid row without overflow.

sub Test_TileSize_ShapeNames()
    Harness_Suite("PosterShapeName normalizes Stremio shapes")
    Harness_Equal(PosterShapeName("landscape"), "landscape", "landscape recognized")
    Harness_Equal(PosterShapeName("square"), "square", "square recognized")
    Harness_Equal(PosterShapeName("poster"), "poster", "sdk poster name recognized")
    Harness_Equal(PosterShapeName("regular"), "poster", "spec regular folds to poster")
    Harness_Equal(PosterShapeName("LANDSCAPE"), "landscape", "case-insensitive")
    Harness_Equal(PosterShapeName(""), "", "empty is not a shape")
    Harness_Equal(PosterShapeName(invalid), "", "invalid is not a shape")
    Harness_Equal(PosterShapeName(340), "", "non-string garbage is ignored")
end sub

sub Test_TileSize_CellSizes()
    Harness_Suite("TileCellSize picks the shape's slab, then the type fallback")
    size = TileCellSize("movie", "landscape")
    Harness_Equal(size[0], 480, "landscape width")
    Harness_Equal(size[1], 270, "landscape height")
    size = TileCellSize("movie", "square")
    Harness_Equal(size[0], 270, "square width")
    Harness_Equal(size[1], 270, "square height")
    size = TileCellSize("movie", "poster")
    Harness_Equal(size[0], 270, "2:3 width")
    Harness_Equal(size[1], 405, "2:3 height")
    size = TileCellSize("channel", "poster")
    Harness_Equal(size[1], 405, "shape beats the channel type fallback")
    size = TileCellSize("movie", "regular")
    Harness_Equal(size[1], 405, "regular folds to the 2:3 slab too")
    size = TileCellSize("movie", "")
    Harness_Equal(size[1], 405, "no shape falls back to 2:3 for a movie")
    size = TileCellSize("", "")
    Harness_Equal(size[1], 405, "no shape no type falls back to 2:3")
    size = TileCellSize("channel", "")
    Harness_Equal(size[0], 270, "channel falls back to square")
    size = TileCellSize(invalid, invalid)
    Harness_Equal(size[1], 405, "wholly invalid input falls back to 2:3")
end sub

sub Test_TileSize_PosterShape()
    Harness_Suite("TilePosterShape folds a row of metas into one shape")
    Harness_Equal(TilePosterShape([]), "", "an empty row has no shape")
    Harness_Equal(TilePosterShape(invalid), "", "invalid metas have no shape")
    metas = []
    metas.Push({ posterShape: "landscape" })
    metas.Push({ posterShape: "landscape" })
    metas.Push({ posterShape: "poster" })
    Harness_Equal(TilePosterShape(metas), "landscape", "majority landscape wins")
    metas = []
    metas.Push({ posterShape: "square" })
    metas.Push({ posterShape: "regular" })
    metas.Push({ posterShape: "regular" })
    Harness_Equal(TilePosterShape(metas), "poster", "regular counts toward the folding 2:3 tally")
    metas = []
    metas.Push({})
    metas.Push({ posterShape: "landscape" })
    metas.Push({ posterShape: "landscape" })
    Harness_Equal(TilePosterShape(metas), "landscape", "shape-less metas are ignored")
    metas = []
    metas.Push({ posterShape: "LANDSCAPE" })
    Harness_Equal(TilePosterShape(metas), "landscape", "case-insensitive")
    metas = []
    metas.Push({ posterShape: "weird" })
    Harness_Equal(TilePosterShape(metas), "", "unrecognized shapes are ignored")
    metas = []
    metas.Push({ posterShape: "poster" })
    metas.Push({ posterShape: "poster" })
    metas.Push({ posterShape: "landscape" })
    Harness_Equal(TilePosterShape(metas), "poster", "2:3 majority wins over a lone landscape")
end sub

sub Test_TileSize_Columns()
    Harness_Suite("TileColumns fits a grid row without overflowing it")
    Harness_Equal(TileColumns(1780, 270, 18), 6, "a 2:3 grid fits six columns")
    Harness_Equal(TileColumns(1780, 480, 18), 3, "a 16:9 grid fits three columns")
    Harness_Equal(TileColumns(1780, 270, 0), 6, "no gap still fits six")
    Harness_Equal(TileColumns(1780, 1920, 18), 1, "a cell wider than the row clamps to one")
    Harness_Equal(TileColumns(0, 270, 18), 1, "a zero-width row clamps to one")
    Harness_Equal(TileColumns(1780, 0, 18), 1, "a zero-width cell clamps to one")
end sub

sub Test_TileSize_RowHeights()
    Harness_Suite("TileRowHeights mirrors each row's tile height for RowList.rowHeights")
    heights = TileRowHeights([[270, 405]])
    Harness_Equal(heights.Count(), 1, "one height per size")
    Harness_Equal(heights[0], 405, "2:3 height")
    heights = TileRowHeights([[480, 270], [270, 405], [270, 270]])
    Harness_Equal(heights.Count(), 3, "one height per mixed row")
    Harness_Equal(heights[0], 270, "landscape row height")
    Harness_Equal(heights[1], 405, "2:3 row height")
    Harness_Equal(heights[2], 270, "square row height")
    Harness_Equal(TileRowHeights([]).Count(), 0, "empty sizes give no heights")
    Harness_Equal(TileRowHeights(invalid).Count(), 0, "invalid sizes give no heights")
end sub