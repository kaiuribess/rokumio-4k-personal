' AddonSyncTask — pull the account's addon collection off the UI thread.
'
' A single addonCollectionGet through StremioApiStore and nothing else. The
' descriptors (transport URL + manifest, straight from the API) are returned
' as-is; MainScene adopts each one through AddonsStore, which stays the single
' writer for installed records. The wire format and envelope rules are the
' store's (and are unit-tested there); this worker only exists to keep the HTTP
' off the render thread.
'
' Integration tests execute this worker with a deterministic transport factory;
' native Task threading and network timing still need device validation.
' Stage values are fixed diagnostic labels. No URL, credential or raw exception
' is included in the worker failure packet.
'
' Both fields alwaysNotify. Ignore initial empty/false notifications; when a
' true finished notification arrives, consume any available result before
' reporting a missing-result failure. Observer dispatch order is not assumed.

sub init()
    m.top.functionName = "sync"
    m.top.stage = "init"
end sub

sub sync()
    m.top.stage = "entered-sync"
    try
        store = StremioApiStore(Transport(), m.top.authKey)
        m.top.stage = "request-started"
        result = store.AddonCollectionGet()
        m.top.result = result
        m.top.stage = "result-written"
    catch e
        ' A fixed error avoids reflecting private data from an exception.
        m.top.stage = "threw"
        m.top.result = { ok: false, descriptors: [], error: "Could not sync account add-ons" }
    end try
    ' LAST statement, on both paths, and deliberately after the result write:
    ' MainScene checks the result from either observer, independent of order.
    m.top.finished = true
end sub