' AddonSyncTask — pull the account's addon collection off the UI thread.
'
' A single addonCollectionGet through StremioApiStore and nothing else. The
' descriptors (transport URL + manifest, straight from the API) are returned
' as-is; MainScene adopts each one through AddonsStore, which stays the single
' writer for installed records. The wire format and envelope rules are the
' store's (and are unit-tested there); this worker only exists to keep the HTTP
' off the render thread.
'
' `stage` is the reason this worker carries two extra fields. The brs test
' interpreter cannot run a Task's worker thread, so NOTHING in npm test executes
' any of this — the only observer of this code is a Roku device, and for three
' separate bugs now ("result" read as invalid, iteration order, a truthiness test
' on an unassigned field) a green suite was no evidence at all. So the worker
' narrates its own progress into a field the fault strip can read: the stage at
' the moment of failure is the diagnosis, with no further round of hypotheses
' needed. It stays in permanently for the same reason.
'
' One trap this file exists to make explicit, learned on device: an alwaysNotify
' interface field notifies once at ObserveField time with its current value, and
' that notification is delivered on the event loop — i.e. AFTER the launching sub
' has returned and the worker has started. "finished" therefore arrives twice, and
' the two arrivals differ only in value. Handlers must test the value. Setting it
' last is what makes `true` mean "the worker is done"; nothing else does.

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
        ' Name the throw, then report it as a normal transport failure. The
        ' catch packet is a result like any other, so the handler has one path.
        m.top.stage = "threw"
        m.top.result = { ok: false, descriptors: [], error: e.message }
    end try
    ' LAST statement, on both paths, and deliberately after the result write:
    ' MainScene's onAddonSyncFinished may only conclude "the worker produced
    ' nothing" once this is true, and a result that landed first is always
    ' observed first.
    m.top.finished = true
end sub