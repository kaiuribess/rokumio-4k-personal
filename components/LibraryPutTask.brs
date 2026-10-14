' LibraryPutTask — push one account library item to Stremio.
'
' A single datastorePut through StremioApiStore and nothing else. The full
' LibraryItem to write rides in m.top.item (built by LibraryStore's
' BuildWatchStateItem / BuildWatchedStateItem / BuildLibraryChangeItem, which
' own the resolve-clone-commit into the freshest cached copy); this worker only
' sends it off the render thread. The envelope rules are the store's (and are
' unit-tested there). One worker serves every write-back kind — player
' position, watched marks, add/remove — so the pipeline can never run two
' datastorePuts (or two nodes on the render thread) at once.

sub init()
    m.top.functionName = "push"
end sub

sub push()
    try
        store = StremioApiStore(Transport(), m.top.authKey)
        result = store.LibraryPut(m.top.item, "Could not write library item")
        m.top.result = result
    catch e
        m.top.result = { ok: false, error: e.message }
    end try
end sub
