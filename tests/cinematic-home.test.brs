sub CancelLoad()
end sub
function CinemaContent() as object
    return {children:[],CreateChild:function(kind as string) as object
        node=CinemaContent():m.children.Push(node):return node
    end function,AppendChild:sub(node as object)
        m.children.Push(node)
    end sub,InsertChild:sub(node as object,index as integer)
        m.children.Push(node)
    end sub,GetChildCount:function() as integer
        return m.children.Count()
    end function,GetChild:function(index as integer) as object
        return m.children[index]
    end function}
end function
function CinemaClock() as object
    return {elapsed:0,Mark:sub()
        m.elapsed=0
    end sub,TotalMilliseconds:function() as integer
        return m.elapsed
    end function}
end function
function CinemaDate() as object
    return {GetYear:function() as integer
        return 2031
    end function}
end function
function CinemaList(name as string,state as object) as object
    return {name:name,state:state,rowItemFocused:[0,0],rowItemSelected:[0,0],content:CinemaContent(),ObserveField:sub(key as string,callback as string)
    end sub,SetFocus:sub(value as boolean)
        if value then m.state.active=m.name
    end sub,HasFocus:function() as boolean
        return m.state.active=m.name
    end function,IsInFocusChain:function() as boolean
        return m.state.active=m.name
    end function}
end function
function Transport() as object
    return {}
end function
function CatalogStore(http as object) as object
    return m.fixtureCatalog
end function
sub CinemaSetup()
    state={active:"quick"}
    m.catalog=CinemaList("catalog",state):m.rail=CinemaList("rail",state)
    m.quick=CinemaList("quick",state)
    nodes={homeQuick:m.quick,homeHeroArt:{uri:"",loadStatus:"none",ObserveField:sub(name as string,callback as string)
    end sub},homeHeroMark:{visible:true},homeHeroTitle:{text:""},homeHeroInfo:{text:""},homeHeroOverview:{text:""},homeHeroDelay:{control:"stop",ObserveField:sub(name as string,callback as string)
    end sub},homeHeroFace:{},homeHeroAccent:{},homeHeroPanel:{visible:true}}
    m.top={screenActive:true,nodes:nodes,FindNode:function(name as string) as object
        return m.nodes[name]
    end function}
    m.catalogRows=[]:m.gridRows=[]:m.homeGridDirty=false:m.catalogStatus={text:""}
    m.stores={library:{callFunc:function(name as string,id=invalid as dynamic,kind=invalid as dynamic) as dynamic
        if name="LibraryContinueWatching" then return []
        return ""
    end function}}
    HomeCinema_Init():HomeCinema_OnEnter()
end sub
function CinemaRow() as object
    return {index:0,title:"Popular movies",addonAddress:"https://catalog.example",metaType:"movie",catalogId:"top",genre:"Action",browse:true,metas:[{id:"one",type:"movie",name:"First movie",poster:"https://art.example/one",homeOverview:"First overview"},{id:"two",type:"movie",name:"Second movie",poster:"https://art.example/two",homeOverview:"Second overview"}]}
end function


function DiscoverText(value as dynamic) as string
    return HomeCatalog_Text(value)
end function
function TypeKey(value as dynamic) as string
    return HomeCatalog_Text(value)
end function
function SelectDefaults() as boolean
    return true
end function
sub ShowEmpty()
end sub
sub FetchDiscover()
    m.fetchedGenre=m.genre
end sub
sub SetChips()
end sub
function GenreOptions() as object
    return [{raw:"All",label:"All"},{raw:"Drama",label:"Drama"}]
end function

Harness_Suite("Home previews are bounded and malformed metadata cannot crash typed UI fields")
pool=[]
for index=0 to 99
    pool.Push({id:"movie"+index.ToStr(),name:"Movie "+index.ToStr(),type:"movie",poster:42,description:"Full provider description"})
end for
sample=HomeCatalog_Sample(pool)
Harness_Equal(sample.Count(),24,"home retains 24 preview titles rather than full catalog")
Harness_Equal(sample[0].poster,"","wrong-type poster becomes empty safe string")
Harness_Equal(sample[0].description,invalid,"full synopsis remains for Details metadata fetch")
Harness_Equal(sample[0].homeOverview,"Full provider description","home retains a separate short overview")
Harness_Equal(HomeCatalog_Sample([{id:"live",name:"Live",type:"channel",posterShape:"square"}])[0].posterShape,"square","preview keeps channel and landscape artwork layout")
Harness_Equal(HomeCatalog_Sample([invalid,{}, {id:"id",name:7}]).Count(),0,"malformed records are safely skipped")
desc={type:"movie",extra:[{name:"genre",options:["Unknown","Drama","Action","Comedy","Horror","Animation"]}]}
genres=HomeCatalog_Genres(desc)
Harness_Equal(genres.Count(),4,"genre preview requests are bounded")
Harness_Equal(genres[0],"Action","only advertised matching genres are selected")
Harness_Equal(HomeCatalog_Genres({type:"movie",extra:[]}).Count(),0,"unsupported genres are not invented")
Harness_Equal(CatalogTitle({id:"top",name:7},{name:"Addon"}),"top","wrong-type catalog title has safe fallback")

Harness_Suite("Hidden Home stages data without creating poster rows over playback")
CinemaSetup():m.top.screenActive=false
ApplyCatalogRow(CinemaRow())
Harness_Equal(m.catalogRows.Count(),1,"background result remains available on return")
Harness_Equal(m.catalog.content.GetChildCount(),0,"hidden callback does not create grid rows")
Harness_Ok(m.homeGridDirty,"pending UI work is recorded")
m.top.screenActive=true:BuildRows()
Harness_Equal(m.catalog.content.GetChildCount(),1,"return builds the staged catalog")
Harness_Equal(m.catalog.content.GetChild(0).GetChildCount(),3,"See all is added without losing preview titles")
Harness_Equal(m.catalog.numRows,1,"one visible row keeps space for hero and shortcuts")
m.catalog.rowItemFocused=[0,2]
onRowItemSelected({GetData:function() as object
    return [0,2]
end function})
Harness_Equal(m.top.pushRequest.screen,"discoverScreen","See all opens full browser")
Harness_Equal(m.top.pushRequest.params.catalogId,"top","catalog identity preserved")
Harness_Equal(m.top.pushRequest.params.genre,"Action","category genre preserved")

Harness_Suite("Featured art is debounced and cannot update after leaving Home")
m.catalog.rowItemFocused=[0,0]:HomeCinema_OnPosterFocus()
HomeCinema_OnHeroDelay()
Harness_Equal(m.heroTitle.text,"Your next movie night","old timer cannot adopt hovered poster too early")
m.heroGuard.clock.elapsed=250:HomeCinema_OnHeroDelay()
Harness_Equal(m.heroTitle.text,"First movie","mature focus uses selected metadata")
Harness_Equal(m.heroArt.uri,"https://art.example/one","one bounded image is assigned")
m.catalog.rowItemFocused=[0,1]:HomeCinema_OnPosterFocus()
m.top.screenActive=false:m.heroGuard.clock.elapsed=250:HomeCinema_OnHeroDelay()
Harness_Equal(m.heroTitle.text,"First movie","hidden screen cannot swap artwork during playback")
HomeCinema_Blur()
Harness_Equal(m.heroArt.uri,"","navigation releases featured texture")
Harness_Ok(not m.heroPending,"navigation cancels pending featured update")
m.top.screenActive=true:HomeCinema_RefreshHero()
Harness_Equal(m.heroTitle.text,"Second movie","return restores correct selected title")

Harness_Suite("Shortcuts and focus preserve access to every existing screen")
Harness_Equal(m.quickEntries.Count(),5,"search, movies, shows, genres and saved titles remain accessible")
m.quick.rowItemSelected=[0,2]:HomeCinema_OnQuickSelected()
Harness_Equal(m.top.pushRequest.params.metaType,"series","Shows shortcut requests series catalog")
m.quick.rowItemSelected=[0,3]:HomeCinema_OnQuickSelected()
Harness_Ok(m.top.pushRequest.params.focusGenres,"Genres shortcut requests filters")
m.quick.SetFocus(true):HomeCinema_Key("down")
Harness_Ok(m.catalog.HasFocus(),"Down enters poster browsing")
Harness_Ok(m.homeBrowse,"Down expands the existing catalog browser")
Harness_Ok(not m.heroPanel.visible,"expanded browser removes the featured area")
Harness_Equal(m.catalog.translation[1],292,"expanded poster rows fit above the footer")
Harness_Equal(m.heroArt.uri,"","expanded browser releases the featured texture")
Harness_Equal(HomeVisibleRows(12),2,"expanded browse retains two visible rows")
HomeCinema_Key("options")
Harness_Ok(m.rail.HasFocus(),"menu shortcut retains Add-ons, Settings and About")
Harness_Ok(m.heroPanel.visible,"return to menu restores featured layout")
Harness_Equal(m.catalog.numRows,1,"compact layout restores one row")
HomeCinema_Key("options")
Harness_Ok(m.quick.HasFocus(),"menu shortcut cycles back to new controls")

Harness_Suite("Actual catalog worker bounds rows, samples and repeated genre requests")
pool=[]
for index=0 to 99
    pool.Push({id:"item"+index.ToStr(),name:"Item "+index.ToStr(),type:"movie"})
end for
m.fixtureCatalog={pool:pool,calls:[],transport:{EncodeQueryValue:function(value as string) as string
    return value
end function},manifestCalls:0,Manifest:function(address as string) as object
    m.manifestCalls=m.manifestCalls+1
    return {ok:false}
end function,Catalog:function(address as string,kind as string,id as string,extra="" as string) as object
    m.calls.Push({id:id,extra:extra})
    if id="broken" then return {ok:false}
    return {ok:true,metas:m.pool}
end function}
extra=[{name:"genre",options:["Action","Comedy","Sci-Fi","Horror","Drama","Thriller"]}]
m.top={addons:[{address:"https://catalog.example",name:"Catalog",catalogs:[{id:"top",name:"Popular",type:"movie",extra:extra},{id:"new",name:"New",type:"movie",extra:extra},{id:"tv",name:"Popular",type:"series",extra:extra},{id:"another",name:7,type:"series"},{id:"broken",name:"Broken",type:"movie"},{}]}]}
load()
Harness_Ok(m.top.result.done,"worker publishes a terminal packet")
Harness_Equal(m.top.result.rows.Count(),12,"actual loader retains at most twelve populated rows")
Harness_Ok(m.fixtureCatalog.calls.Count()<=16,"actual loader has bounded catalog request count")
for each row in m.top.result.rows
    Harness_Equal(row.metas.Count(),24,"actual provider response is reduced to preview size")
    Harness_Ok(row.browse and row.catalogId<>"","full browse identity survives preview sampling")
end for
duplicates=0
for each call in m.fixtureCatalog.calls
    if call.id="new" and call.extra="genre=Action" then duplicates=duplicates+1
end for
Harness_Equal(duplicates,0,"repeated catalogs cannot duplicate a genre shelf")
unknown=[]
for index=0 to 39
    unknown.Push({address:"https://manifest.example/"+index.ToStr(),name:"Unknown"})
end for
m.top={addons:unknown}:load()
Harness_Equal(m.fixtureCatalog.manifestCalls,8,"unknown manifests cannot create unbounded Home requests")
Harness_Ok(m.top.result.done,"manifest exhaustion leaves working navigation and terminal result")

Harness_Suite("Home worker fetches only safe provider-advertised current-year feeds")
yearExtra=[{name:"genre",options:["2031","2030"],isRequired:true},{name:"skip"}]
legacy={id:"legacy",name:"Legacy New",type:"movie",extraRequired:["genre"],extra:[{name:"genre",options:["2031"],isRequired:true}]}
m.fixtureCatalog.calls=[]
m.top={addons:[{address:"https://catalog.example",name:"Catalog",catalogs:[
    {id:"year",name:"New",type:"movie",extra:yearExtra},
    {id:"year",name:"New",type:"series",extra:yearExtra},
    {id:"missing",name:"Missing options",type:"movie",extra:[{name:"genre",isRequired:true}]},
    {id:"stale",name:"Old only",type:"movie",extra:[{name:"genre",isRequired:true,options:["2030"]}]},
    {id:"bad",name:"Wrong options",type:"movie",extra:[{name:"genre",isRequired:true,options:[2031,{},invalid]}]},
    {id:"other",name:"Other required",type:"movie",extra:[{name:"genre",isRequired:true,options:["2031"]},{name:"privateListId",isRequired:true}]},
    legacy
]}]}
load()
Harness_Equal(m.fixtureCatalog.calls.Count(),3,"actual worker requests only two valid New feeds and legacy year descriptor")
Harness_Equal(m.fixtureCatalog.calls[0].extra,"genre=2031","year is derived at runtime and sent as provider input")
Harness_Equal(m.top.result.rows[1].genre,"2031","New shows retain their year for See all")
Harness_Equal(legacy.extraRequired.Count(),1,"feed validation cannot mutate persisted manifest extras")
Harness_Ok(not CatalogBrowsable({type:"movie",extraRequired:["search"]}),"search-only feed is not requested without a query")
many=[]
for index=0 to 49
    many.Push({id:"year"+index.ToStr(),name:"New",type:"movie",extra:yearExtra})
end for
m.fixtureCatalog.calls=[]:m.top={addons:[{address:"https://catalog.example",catalogs:many}]}:load()
Harness_Equal(m.fixtureCatalog.calls.Count(),8,"many year catalogs retain the existing eight base-request budget")
Harness_Equal(m.top.result.rows.Count(),8,"new catalog support does not bypass bounded Home rows")

Harness_Suite("Full-browser entry consumes shortcut presets before requesting data")
m.entryRequest={metaType:"series",addonAddress:"https://catalog.example",catalogId:"tv",genre:"Drama",focusGenres:true}
m.filterBar={calls:[],callFunc:sub(name as string,index=invalid as dynamic)
    m.calls.Push({name:name,index:index})
end sub}
DiscoveryReadySources()
Harness_Equal(m.typeKey,"series","Shows preset is applied before lookup")
Harness_Equal(m.selectedCatalog.catalogId,"tv","See all retains exact provider catalog")
Harness_Equal(m.genre,"Drama","See all retains exact category filter")
Harness_Equal(m.fetchedGenre,"Drama","actual ready callback fetches requested genre")
Harness_Equal(m.filterBar.chipActivated,2,"Genres opens correct filter rather than type menu")
Harness_Equal(m.entryRequest,invalid,"preset is consumed once and cannot replay on return")
Harness_Finish()
