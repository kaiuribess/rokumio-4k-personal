' DiscoverLoaderTask — fetch one filtered catalog row off the UI thread. The
' store is built fresh inside the task scope; nothing created on the render
' thread crosses the thread boundary. A hung add-on costs the worker thread,
' not a frozen channel.
'
' The screen hands over the raw genre (empty when unfiltered) rather than a
' pre-built extra string so this task can percent-encode it: genres come from
' arbitrary add-on manifests and may contain spaces or '&', which a raw query
' segment would corrupt.
sub init()
    m.top.functionName = "discover"
end sub
sub discover()
    try
        result = { ok: false, metas: [], hasMore: false, error: "" }
        http = Transport()
        catalog = CatalogStore(http)

        if m.top.addonAddress <> "" and m.top.metaType <> "" and m.top.catalogId <> ""
            parts = []
            if m.top.genre <> "" then parts.Push("genre=" + http.EncodeQueryValue(m.top.genre))
            parts.Push("skip=" + m.top.pageOffset.ToStr())
            answer = catalog.Catalog(m.top.addonAddress, m.top.metaType, m.top.catalogId, parts.Join("&"))
            result.ok = answer.ok
            result.error = answer.error
            result.hasMore = answer.hasMore
            if answer.ok and answer.metas <> invalid then result.metas = answer.metas
        else
            result.error = "missing discover filters"
        end if

        m.top.result = result
    catch e
        m.top.result = { ok: false, metas: [], hasMore: false, error: e.message }
    end try
end sub
