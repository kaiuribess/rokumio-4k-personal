' HomeCatalogsTask — bounded previews from installed catalogs off the UI thread.
' Manifests are resolved here where the registry has none (built-ins), each
' browsable catalog is fetched, and the growing row set is republished after
' every completion so the Home grid fills in one row at a time instead of after
' the whole catalog set has downloaded. Running inside a Task means a hung
' add-on costs the worker thread, not a frozen channel. The store is built
' fresh in the task scope; only plain { address, catalogs } descriptors cross
' the thread boundary from HomeScreen.

sub init()
    m.top.functionName = "load"
end sub

sub load()
    rows = []
    providers = []
    genreJobs = []
    genreSeen = {}
    baseAttempts = 0
    manifestAttempts = 0
    try
        catalog = CatalogStore(Transport())
        if Type(m.top.addons) <> "roArray" then m.top.result = {rows:rows,done:true}:return
        addonCount = m.top.addons.Count()
        if addonCount > 64 then addonCount = 64
        for addonIndex = 0 to addonCount - 1
            addon = m.top.addons[addonIndex]
            if Type(addon) <> "roAssociativeArray" then continue for
            address = HomeCatalog_Text(addon.address)
            if address = "" then continue for
            catalogs = addon.catalogs
            if Type(catalogs) <> "roArray"
                if manifestAttempts >= 8 then continue for
                manifestAttempts = manifestAttempts + 1
                answer = catalog.Manifest(address)
                if answer.ok = true and Type(answer.manifest) = "roAssociativeArray" then catalogs = answer.manifest.catalogs
            end if
            if Type(catalogs) <> "roArray" then continue for
            provider = HomeCatalog_ProviderJobs(addon,address,catalogs)
            if provider.jobs.Count() = 0 then continue for
            providers.Push(provider)
            ' Publish the first row promptly, but give every later provider its
            ' first turn before spending a second base request on this one.
            if baseAttempts < 8
                baseAttempts = baseAttempts + 1
                job = provider.jobs[0]
                provider.nextJob = 1
                HomeFetchRow(catalog,rows,provider.address,job.kind,job.id,job.title,job.genre)
            end if
        end for
        for round = 1 to 7
            if baseAttempts >= 8 then exit for
            for each provider in providers
                if baseAttempts >= 8 then exit for
                if provider.nextJob >= provider.jobs.Count() then continue for
                job = provider.jobs[provider.nextJob]
                provider.nextJob = provider.nextJob + 1
                baseAttempts = baseAttempts + 1
                HomeFetchRow(catalog,rows,provider.address,job.kind,job.id,job.title,job.genre)
            end for
        end for
        ' Genre previews have their own eight-attempt budget. Interleave these
        ' too, while preserving the existing type/genre de-duplication rule.
        for round = 0 to 7
            if genreJobs.Count() >= 8 then exit for
            for each provider in providers
                if genreJobs.Count() >= 8 then exit for
                if round >= provider.genres.Count() then continue for
                job = provider.genres[round]
                key = job.kind + "|" + LCase(job.genre)
                if genreSeen.DoesExist(key) then continue for
                genreSeen[key] = true
                genreJobs.Push({address:provider.address,kind:job.kind,id:job.id,genre:job.genre,title:job.title})
            end for
        end for
        for each job in genreJobs
            if rows.Count() >= 12 then exit for
            HomeFetchRow(catalog,rows,job.address,job.kind,job.id,job.title,job.genre)
        end for
        m.top.result = {rows:rows,done:true}
    catch e
        m.top.result = {rows:rows,done:true,error:"Catalog request failed"}
    end try
end sub

' Only bounded preview jobs are copied; the installed catalog descriptors stay
' intact so Discover retains every provider's full collection and filters.
function HomeCatalog_ProviderJobs(addon as object, address as string, catalogs as object) as object
    provider = {address:address,jobs:[],genres:[],nextJob:0}
    seen = {}
    for each descriptor in catalogs
        if Type(descriptor) <> "roAssociativeArray" then continue for
        if HomeCatalog_Text(descriptor.id) = "" or HomeCatalog_Text(descriptor.type) = "" then continue for
        feed = HomeCatalog_Feed(descriptor)
        if not feed.ok then continue for
        if provider.jobs.Count() < 8
            provider.jobs.Push({kind:descriptor.type,id:descriptor.id,title:CatalogTitle(descriptor,addon),genre:feed.genre})
        end if
        if provider.genres.Count() < 8
            for each genre in HomeCatalog_Genres(descriptor)
                key = descriptor.type + "|" + LCase(genre)
                if seen.DoesExist(key) then continue for
                seen[key] = true
                family = "movies"
                if descriptor.type = "series" then family = "shows"
                provider.genres.Push({kind:descriptor.type,id:descriptor.id,genre:genre,title:genre + " " + family})
                if provider.genres.Count() >= 8 then exit for
            end for
        end if
        if provider.jobs.Count() >= 8 and provider.genres.Count() >= 8 then exit for
    end for
    return provider
end function

sub HomeFetchRow(catalog as object, rows as object, address as string, kind as string, id as string, title as string, genre as string)
    try
        extra = ""
        if genre <> "" then extra = "genre=" + catalog.transport.EncodeQueryValue(genre)
        response = catalog.Catalog(address,kind,id,extra)
        if response.ok <> true then return
        sampled = HomeCatalog_Sample(response.metas)
        if sampled.Count() = 0 then return
        for each item in sampled
            if item.type = "" then item.type = kind
        end for
        rows.Push({index:rows.Count(),addonAddress:address,catalogId:id,genre:genre,title:title,metaType:kind,metas:sampled,browse:true})
        m.top.result = {rows:rows,done:false}
    catch e
        ' One bad catalog does not stop other providers or categories.
    end try
end sub

' Browse only feeds whose required extras can be satisfied, including a
' current-year genre explicitly advertised by the provider.
function CatalogBrowsable(catalog as object) as boolean
    return HomeCatalog_Feed(catalog).ok
end function

' A row title that is always a non-empty string. Real-world manifests (Stremio's
' own Channels addon included) ship catalogs with only type/id and no name, and
' an invalid title crashes the Home title pipeline (an associative array cannot
' be keyed by invalid). Fall back: catalog name -> catalog id -> addon name ->
' "Unknown". The addon packet carries name so a nameless catalog still gets a
' recognizable label.
function CatalogTitle(catalog as object, addon as object) as string
    title = HomeCatalog_Text(catalog.name)
    if title = "" then title = HomeCatalog_Text(catalog.id)
    if title = "" then title = HomeCatalog_Text(addon.name)
    if title = "" then title = "Explore"
    title = title.Left(80)
    return title
end function
