' SearchLoaderTask — back one add-on's search query off the UI thread. The
' screen spawns one task per add-on, each carrying the subset of search-capable
' catalogs that add-on serves. The task asks the add-on the same query against
' each catalog in turn (try/catch per catalog, so one bad answer cannot kill the
' rest) and publishes { sections, addonKey } — one section per requested catalog.
' The store is built fresh in the task scope; no object created on the render
' thread is shared across the thread boundary.
sub init()
    m.top.functionName = "search"
end sub
sub search()
    sections = []
    results = { sections: sections, addonKey: m.top.addonKey }
    try
        http = Transport()
        catalog = CatalogStore(http)

        for each cat in m.top.catalogs
            if cat = invalid or cat.key = invalid then continue for

            section = { key: cat.key, metas: [], error: "" }
            try
                if m.top.addonAddress <> "" and m.top.query <> "" and cat.type <> invalid and cat.type <> "" and cat.id <> invalid and cat.id <> ""
                    answer = catalog.Search(m.top.addonAddress, cat.type, m.top.query, cat.id)
                    if answer.ok and answer.metas <> invalid
                        section.metas = answer.metas
                    else if answer.error <> invalid and answer.error <> ""
                        section.error = answer.error
                    end if
                end if
            catch e
                section.error = e.message
            end try

            sections.Push(section)
        end for
    catch e
        results.error = e.message
    end try

    m.top.result = results
end sub
