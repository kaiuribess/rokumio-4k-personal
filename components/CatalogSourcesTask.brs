' CatalogSourcesTask — resolve which catalogs every installed add-on actually
' serves, off the UI thread. The registry carries full catalog descriptors for
' add-ons installed from a manifest, but the built-in seeds ship catalogs =
' invalid until a manifest lands, so those are the only packets that need a
' manifest fetch. Everything else echoes straight through; the task exists to
' keep that one network call off the UI thread and to give Discover and Search
' one shared shape ({ address, name, resources, catalogs }) to reason about.
'
' The store is built fresh in the task scope; only plain descriptors cross the
' thread boundary from the caller.
'
' Output: result = { sources: [ { address, name, resources, catalogs } ], done }
' A packet whose manifest cannot be fetched is dropped rather than emitted with
' an empty catalog list, so a failed add-on never shows as a blank source.

sub init()
    m.top.functionName = "load"
end sub

sub load()
    sources = []
    try
        http = Transport()
        catalog = CatalogStore(http)

        for each addon in m.top.addons
            if addon = invalid then continue for
            catalogs = addon.catalogs
            resources = addon.resources
            name = addon.name

            if catalogs = invalid or Type(catalogs) <> "roArray"
                if addon.address <> invalid and addon.address <> ""
                    answer = catalog.Manifest(addon.address)
                    if answer.ok and answer.manifest <> invalid
                        catalogs = answer.manifest.catalogs
                        if resources = invalid then resources = answer.manifest.resources
                        if (name = invalid or name = "") and answer.manifest.name <> invalid then name = answer.manifest.name
                    end if
                end if
            end if

            if catalogs <> invalid and Type(catalogs) = "roArray"
                sources.Push({
                    address: addon.address
                    name: name
                    resources: resources
                    catalogs: catalogs
                })
            end if
        end for

        m.top.result = { sources: sources, done: true }
    catch e
        m.top.result = { sources: sources, done: true, error: e.message }
    end try
end sub
