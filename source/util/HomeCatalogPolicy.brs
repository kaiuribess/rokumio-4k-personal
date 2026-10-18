' Home is a bounded preview; Discover retains full catalogs and pagination.
function HomeCatalog_Text(value as dynamic) as string
    if Type(value) = "String" or Type(value) = "roString" then return value.Trim()
    return ""
end function

function HomeCatalog_Sample(metas as dynamic) as object
    result = []
    if Type(metas) <> "roArray" then return result
    for each meta in metas
        if Type(meta) <> "roAssociativeArray" then continue for
        id = HomeCatalog_Text(meta.id)
        name = HomeCatalog_Text(meta.name)
        if id = "" or id.Len() > 1024 or name = "" then continue for
        item = {id:id,name:name.Left(160),type:HomeCatalog_Text(meta.type),homeOverview:HomeCatalog_Text(meta.description).Left(280)}
        for each key in ["poster","background","logo"]
            value = HomeCatalog_Text(meta[key])
            if value.Len() <= 8192 then item[key] = value
        end for
        item.releaseInfo = HomeCatalog_Text(meta.releaseInfo).Left(64)
        shape = LCase(HomeCatalog_Text(meta.posterShape))
        if shape = "poster" or shape = "square" or shape = "landscape" then item.posterShape = shape
        result.Push(item)
        if result.Count() >= 24 then exit for
    end for
    return result
end function

function HomeCatalog_Genres(descriptor as dynamic) as object
    result = []
    if Type(descriptor) <> "roAssociativeArray" or Type(descriptor.extra) <> "roArray" then return result
    if descriptor.type <> "movie" and descriptor.type <> "series" then return result
    options = invalid
    for each extra in descriptor.extra
        if Type(extra) = "roAssociativeArray" and extra.name = "genre" and Type(extra.options) = "roArray" then options = extra.options
    end for
    if options = invalid then return result
    wanted = ["Action","Comedy","Sci-Fi","Horror","Animation","Drama","Thriller","Family"]
    for each preference in wanted
        for each value in options
            genre = HomeCatalog_Text(value)
            if genre <> "" and LCase(genre) = LCase(preference)
                result.Push(genre)
                exit for
            end if
        end for
        if result.Count() >= 4 then exit for
    end for
    return result
end function

' Required year filters are safe only when the provider advertises this year.
' Never invent a genre or submit a feed whose other required input is missing.
function HomeCatalog_Feed(descriptor as dynamic) as object
    result = {ok:false,genre:""}
    if Type(descriptor) <> "roAssociativeArray" then return result
    required = []
    if Type(descriptor.extraRequired) = "roArray"
        for each name in descriptor.extraRequired
            required.Push(name)
        end for
    end if
    options = invalid
    if Type(descriptor.extra) = "roArray"
        for each extra in descriptor.extra
            if Type(extra) <> "roAssociativeArray" then continue for
            if extra.isRequired = true then required.Push(extra.name)
            if extra.name = "genre" and Type(extra.options) = "roArray" then options = extra.options
        end for
    end if
    needsYear = false
    for each name in required
        if name = "genre"
            needsYear = true
        else if name <> "skip"
            return result
        end if
    end for
    if needsYear
        if descriptor.type <> "movie" and descriptor.type <> "series" then return result
        if Type(options) <> "roArray" then return result
        year = CreateObject("roDateTime").GetYear().ToStr()
        for each option in options
            if HomeCatalog_Text(option) = year then result.genre = year:exit for
        end for
        if result.genre = "" then return result
    end if
    result.ok = true
    return result
end function
