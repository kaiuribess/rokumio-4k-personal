' WatchStateBuffer unit tests.
'
' The player → MainScene mailbox. It survives the player node's lifetime, so a
' unit test only needs the last-value stash semantics: invalid publishes are
' dropped, each valid publish wins over the previous one, and Latest never
' crashes before the first Record.

sub Test_WatchStateBuffer_StashAndLatest()
    Harness_Suite("WatchStateBuffer keeps the newest packet")
    buf = WatchStateBuffer()
    Harness_Ok(buf.Latest() = invalid, "Latest is invalid before the first Record")
    buf.Record(invalid)
    Harness_Ok(buf.Latest() = invalid, "invalid publish ignored")
    p1 = { videoId: "tt1234567:1:1", position: 100 }
    buf.Record(p1)
    Harness_Equal(buf.Latest().videoId, p1.videoId, "Latest returns the recorded packet")
    p2 = { videoId: "tt1234567:1:2", position: 200 }
    buf.Record(p2)
    Harness_Equal(buf.Latest().videoId, p2.videoId, "a later publish overwrites the earlier one")
end sub