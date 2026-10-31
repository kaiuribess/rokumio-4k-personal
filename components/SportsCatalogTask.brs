sub init()
    m.top.functionName = "loadSportsCatalog"
end sub

sub loadSportsCatalog()
    result = {ok:false,events:[],nextOffset:m.top.offset,hasMore:false,skipped:0,firstId:""}
    try
        entry = m.top.entry
        http = Transport()
        ' CatalogStore remains the authority on URL assembly and validation.
        ' This wrapper supplies a bounded per-request deadline in this Task.
        bounded = {http:http,Get:function(url as string) as object
            return m.http.Get(url,invalid,10000)
        end function,EncodeQueryValue:function(value as string) as string
            return m.http.EncodeQueryValue(value)
        end function,EndpointUrl:function(address as string,path as string) as string
            return m.http.EndpointUrl(address,path)
        end function}
        offset = 0
        if entry.skipSupported = true then offset = m.top.offset
        extra = "skip=" + offset.ToStr()
        answer = CatalogStore(bounded).Catalog(entry.params.addonAddress,entry.params.metaType,entry.params.catalogId,extra,entry.pageSize,true)
        result = Sports_CatalogPage(answer,entry,m.top.offset)
    catch e
        ' Never expose configured URLs, response bodies or exception details.
    end try
    m.top.result = result
    m.top.finished = true
end sub
