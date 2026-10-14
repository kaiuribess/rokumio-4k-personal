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
    genreJobs = []
    genreSeen = {}
    baseAttempts = 0
    manifestAttempts = 0
    try
        catalog = CatalogStore(Transport())
        if Type(m.top.addons) <> "roArray" then m.top.result = {rows:rows,done:true}:return
        for each addon in m.top.addons
            if baseAttempts >= 8 and genreJobs.Count() >= 8 then exit for
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
            for each descriptor in catalogs
                if baseAttempts >= 8 and genreJobs.Count() >= 8 then exit for
                if Type(descriptor) <> "roAssociativeArray" then continue for
                if HomeCatalog_Text(descriptor.id) = "" or HomeCatalog_Text(descriptor.type) = "" or not CatalogBrowsable(descriptor) then continue for
                if rows.Count() < 8 and baseAttempts < 8
                    baseAttempts = baseAttempts + 1
                    HomeFetchRow(catalog,rows,address,descriptor.type,descriptor.id,CatalogTitle(descriptor,addon),"")
                end if
                if genreJobs.Count() < 8
                    for each genre in HomeCatalog_Genres(descriptor)
                        key = descriptor.type + "|" + LCase(genre)
                        if genreSeen.DoesExist(key) then continue for
                        genreSeen[key] = true
                        family = "movies"
                        if descriptor.type = "series" then family = "shows"
                        genreJobs.Push({address:address,kind:descriptor.type,id:descriptor.id,genre:genre,title:genre + " " + family})
                        if genreJobs.Count() >= 8 then exit for
                    end for
                end if
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

' A catalog is browsable when none of its required extras demand more than the
' plain skip=0 browse supplies (the same rule the old synchronous Home walk
' applied).
function CatalogBrowsable(catalog as object) as boolean
    if Type(catalog) <> "roAssociativeArray" then return false
    required = catalog.extraRequired
    if required <> invalid and Type(required) = "roArray"
        for each name in required
            if name <> "skip" then return false
        end for
    end if
    extras = catalog.extra
    if extras <> invalid and Type(extras) = "roArray"
        for each extra in extras
            if Type(extra) = "roAssociativeArray"
                if extra.isRequired = true and extra.name <> "skip" then return false
            end if
        end for
    end if
    return true
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
