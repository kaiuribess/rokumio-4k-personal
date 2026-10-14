' AddonsInstallTask — fetch + install an add-on manifest off the UI thread.
' The manifest fetch rides Transport's default request timeout (REQUEST_TIMEOUT_MS,
' 15s), so a hung add-on costs the worker thread, not a frozen channel. The task
' builds its own store inside the task scope — no object created on the render
' thread crosses the thread boundary. The task's store has no registry (a fresh,
' in-memory instance), so Install's duplicate check always passes here; the real
' duplicate guard runs in AddonsStore.Register when AddonsScreen adopts the
' record. That is deliberate — keep it that way.
sub init()
    m.top.functionName = "install"
end sub

sub install()
    try
        http = Transport()
        store = AddonsStore(http)
        result = store.Install(m.top.address)
        record = invalid
        if result.ok and result.id <> invalid and result.id <> ""
            record = store.Get(result.id)
        end if
        m.top.result = {
            ok: result.ok
            id: result.id
            error: result.error
            record: record
        }
    catch e
        m.top.result = { ok: false, id: "", error: e.message, record: invalid }
    end try
end sub