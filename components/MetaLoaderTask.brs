' MetaLoaderTask — fetch one add-on meta ({ ok, meta, error }) off the UI thread.
' Both Home (continue-watching tiles stack a full item meta before opening
' Details) and Episodes (its season list build) need the same fetch; running it
' in a Task means a hung add-on costs the worker thread, not a frozen channel.
' The store is built fresh in the task scope — no object created on the render
' thread is shared across the thread boundary.

sub init()
    m.top.functionName = "load"
end sub

sub load()
    try
        http = Transport()
        store = EpisodesStore(http)
        answer = store.GetMeta(m.top.addonAddress, m.top.metaType, m.top.metaId)
        m.top.result = { ok: answer.ok, meta: answer.meta, error: answer.error }
    catch e
        m.top.result = { ok: false, meta: invalid, error: e.message }
    end try
end sub