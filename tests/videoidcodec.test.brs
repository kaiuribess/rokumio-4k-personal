' VideoIdCodec unit tests — the "{imdbId}:{season}:{episode}" convention's single
' translator. Build constructs the id every episode path keys on (stream lookups,
' watched state, the OrderedVideoIds list the account bitfield indexes); Parse
' reads one back so ParseLibraryItem can classify a library item exactly the way
' the id was built, without re-implementing the format. When Parse comes back
' invalid, callers distinguish a bare movie id (no colon) from malformed junk
' (contains a colon) — pinned here so the 3-part rule cannot drift.

sub Test_VideoIdCodec_Build()
    Harness_Suite("VideoIdCodec.Build constructs the {seriesId}:{season}:{episode} id")
    codec = VideoIdCodec()
    Harness_Equal(codec.Build("tt1234567", 1, 1), "tt1234567:1:1", "season 1 episode 1")
    Harness_Equal(codec.Build("tt1234567", 2, 12), "tt1234567:2:12", "multi-digit episode")
    Harness_Equal(codec.Build("tt9", 0, 0), "tt9:0:0", "zero season/episode round-trips")
end sub

sub Test_VideoIdCodec_Parse()
    Harness_Suite("VideoIdCodec.Parse reads back a 3-part id and rejects everything else")
    codec = VideoIdCodec()
    parsed = codec.Parse("tt1234567:2:12")
    Harness_Ok(parsed <> invalid, "3-part id parses")
    Harness_Equal(parsed.season, 2, "season decoded")
    Harness_Equal(parsed.episode, 12, "episode decoded")
    Harness_Equal(codec.Parse("tt5"), invalid, "a bare movie id is not an episode id")
    Harness_Equal(codec.Parse("tt2:5"), invalid, "a 2-part id is malformed")
    Harness_Equal(codec.Parse("a:b:c:d"), invalid, "a 4-part id is malformed")
    Harness_Equal(codec.Parse(""), invalid, "an empty id is not 3-part")
    Harness_Equal(codec.Parse(invalid), invalid, "invalid input yields invalid")
end sub