' LibrarySyncTask — pull the account's library items off the UI thread.
'
' A single datastoreGet through StremioApiStore and nothing else. The raw
' library item array is returned as-is; MainScene hands it to
' LibraryStore.SyncFromStremio, which owns all classification and mapping
' (continue watching / saved / stremioLibrary). The wire format and envelope
' rules are the store's (and are unit-tested there); this worker only exists to
' keep the HTTP off the render thread.

sub init()
    m.top.functionName = "sync"
end sub

sub sync()
    try
        store = StremioApiStore(Transport(), m.top.authKey)
        result = store.LibraryGet()
        m.top.result = result
    catch e
        m.top.result = { ok: false, items: [], error: e.message }
    end try
end sub