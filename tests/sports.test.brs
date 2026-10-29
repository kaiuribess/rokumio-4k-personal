function SportsTestContent() as object
    return {children:[],CreateChild:function(kind as string) as object
        child = SportsTestContent():m.children.Push(child):return child
    end function}
end function
function SportsTestClock() as object
    return {elapsed:0,Mark:sub()
        m.elapsed=0
    end sub,TotalMilliseconds:function() as integer
        return m.elapsed
    end function}
end function
function SportsTestEvent(task as object) as object
    return {node:task,GetRoSGNode:function() as object
        return m.node
    end function}
end function
function AsyncTask_Launch(owner as object,kind as string,callback as string,params as object,id as string,done as string) as object
    if m.failLaunch = true then broken=invalid:broken.launch()
    m.launches++
    return {id:id,league:params.league,day:params.day,callback:callback,done:done,finished:false}
end function
sub AsyncTask_Reap(task as object,owner as object,doStop as boolean)
    m.reaps++
end sub
function SportsTestTransport() as object
    return m.workerHttp
end function
function SportsBody(state="in" as string) as object
    return {events:[{id:"123",name:"Example game",date:"2026-10-29T19:00Z",status:{type:{state:state,shortDetail:"Second half"}},competitions:[{competitors:[{team:{abbreviation:"A"},score:"3"},{team:{abbreviation:"B"},score:"2"}]}]}]}
end function
sub SportsReset()
    m.leagues = Sports_Leagues():m.leagueIndex=0:m.dayIndex=0:m.stateIndex=0
    m.days=[{raw:"20261029",label:"Today"},{raw:"20261030",label:"Tomorrow"}]
    m.states=[{raw:"",label:"All"},{raw:"in",label:"Live"},{raw:"pre",label:"Upcoming"},{raw:"post",label:"Completed"}]
    m.events=[]:m.rows=[]:m.catalogs=[]:m.task=invalid:m.sequence=0:m.desired="":m.applied="":m.loaded="":m.loadClock=invalid
    m.launches=0:m.reaps=0:m.failLaunch=false:m.top={screenActive:true}
    m.status={text:""}:m.name={text:""}:m.detail={text:""}:m.list={rowItemFocused:[0,0],rowItemSelected:[0,0]}
    m.filters={open:false,chipActivated:0,callFunc:function(name as string,a=invalid as dynamic,b=invalid as dynamic) as dynamic
        if name="IsMenuOpen" then return m.open
        if name="HideMenu" then m.open=false
        return invalid
    end function}
    m.addons = AddonsStore(ScriptedTransport([]),MockRegistry())
    m.stores={addons:{store:m.addons,callFunc:function(name as string,a=invalid as dynamic,b=invalid as dynamic,c=invalid as dynamic,d=invalid as dynamic,e=invalid as dynamic,f=invalid as dynamic) as dynamic
        if name="AddonsGetAll" then return m.store.GetAll()
        if name="AddonsSupportsResource" then return m.store.SupportsResource(a,b,c,d,e,f)
        if name="AddonsCatalogCapabilities" then return m.store.CatalogCapabilities(a)
        return invalid
    end function}}
end sub

Harness_Suite("Sports schedule worker, screen and stale-result boundaries")
SportsReset()
SportsRequest()
first=m.task
Harness_Equal(m.launches,1,"one worker for schedule")
Harness_Equal(first.done,"onSportsFinished","finished observer handles missing result")
onSportsResult(SportsTestEvent(first))
Harness_Equal(m.reaps,0,"empty notification does not consume live worker")
m.dayIndex=1:SportsRequest()
Harness_Equal(m.launches,1,"changed query waits for occupied slot")
owner=m.top:m.top=first:m.workerHttp=ScriptedTransport([{ok:true,status:200,json:SportsBody()}])
loadSchedule():m.top=owner
Harness_Equal(m.workerHttp.log[0].timeoutMs,10000,"schedule uses bounded network deadline")
Harness_Ok(first.finished,"worker always signals completion")
onSportsResult(SportsTestEvent(first))
Harness_Equal(m.events.Count(),0,"old date cannot overwrite requested date")
onSportsFinished(SportsTestEvent(first))
Harness_Equal(m.launches,2,"latest queued date starts after first worker finishes")
Harness_Equal(m.task.day,"20261030","latest selection, not an intermediate query")
current=m.task:current.result=Sports_Normalize(SportsBody(),"football/nfl")
onSportsResult(SportsTestEvent(current))
Harness_Equal(m.rows.Count(),1,"production result callback populates rows")
Harness_Equal(m.rows[0].id,"espn_football_nfl_123","portable ID for stream-provider lookup")
Harness_Equal(m.rows[0].score,"A 3   B 2","actual score details")
Harness_Equal(m.reaps,1,"result alone does not release worker slot")
current.finished=true:onSportsFinished(SportsTestEvent(current))
Harness_Equal(m.task,invalid,"finished worker releases slot")
onSportsFinished(SportsTestEvent(current)):onSportsResult(SportsTestEvent(first))
Harness_Equal(m.reaps,2,"duplicate and stale notifications ignored")
SportsRequest():current=m.task:current.finished=true:onSportsFinished(SportsTestEvent(current))
Harness_Ok(m.status.text.InStr("without a result")>=0,"finished-without-result is actionable failure")
Harness_Equal(m.events.Count(),1,"failed refresh preserves earlier schedule")
SportsRequest():current=m.task:OnExit():m.top.screenActive=false
current.result=Sports_Normalize(SportsBody(),"football/nfl"):current.finished=true
onSportsFinished(SportsTestEvent(current))
Harness_Equal(m.task,invalid,"hidden screen reaps completed work")
Harness_Equal(m.launches,4,"leaving does not launch background requests")
SportsReset():m.failLaunch=true:SportsRequest()
Harness_Equal(m.task,invalid,"failed task creation does not occupy the single worker slot")
Harness_Ok(m.status.text.InStr("Could not start")=0,"task creation failure is actionable")
m.failLaunch=false:SportsRequest()
Harness_Equal(m.launches,1,"retry after task creation failure can start")

Harness_Suite("Malformed, empty, oversized and failed schedules")
Harness_Ok(not Sports_Normalize({}, "football/nfl").ok,"missing events is not a successful empty schedule")
Harness_Ok(Sports_Normalize({events:[]}, "football/nfl").ok,"real empty collection is valid")
body=SportsBody():body.events.Push(invalid):body.events.Push({id:"../bad",name:"Bad"}):body.events.Push(body.events[0])
packet=Sports_Normalize(body,"football/nfl")
Harness_Equal(packet.events.Count(),1,"malformed and duplicate event records discarded")
Harness_Equal(packet.skipped,3,"partial schedule exposes skipped entries")
body={events:[]}
for i=1 to 150
    body.events.Push({id:i.ToStr(),name:String(500,"x"),status:{type:{state:"pre"}}})
end for
packet=Sports_Normalize(body,"football/nfl")
Harness_Equal(packet.events.Count(),100,"bounded event count")
Harness_Equal(packet.events[0].name.Len(),160,"bounded event text")
Harness_Ok(packet.truncated,"truncated response is explicit")
Harness_Equal(Sports_Url("../evil","20261029"),"","league cannot inject a host or path")
Harness_Equal(Sports_Url("football/nfl","20261029&token=x"),"","date cannot inject query")
Harness_Equal(TransportResponseLimit(Sports_Url("football/nfl","20261029")),1048576,"acquisition capped at one MiB before parsing")
SportsReset():m.top.league="football/nfl":m.top.day="20261029"
m.workerHttp=ScriptedTransport([{ok:false,status:503,json:SportsBody()}])
loadSchedule()
Harness_Ok(not m.top.result.ok,"HTTP failure is not schedule success")
Harness_Ok(m.top.finished,"failed worker completes")
Harness_Ok(m.top.result.error.InStr("https")<0,"UI never echoes private URL/error body")

Harness_Suite("Generated add-on -> actual registry -> catalog -> screen -> player resolver")
SportsReset():files=SportsFeedFixture():manifest=files["manifest.json"]
answer=m.addons.InstallFromDescriptor("https://sports.example.com/manifest.json",manifest)
Harness_Ok(answer.ok,"generated manifest installs through production AddonsStore")
Harness_Ok(answer.persisted,"provider registration has durable acknowledgement")
SportsCatalogs()
Harness_Equal(m.catalogs.Count(),2,"provider catalog appears alongside Manage add-ons")
m.filters.optionPicked={chip:3,index:1}:onSportsOption()
Harness_Equal(m.top.pushRequest.screen,"discoverScreen","catalog opens native Discover")
Harness_Equal(m.top.pushRequest.params.catalogId,"crimson-sports","correct catalog routed")
http=ScriptedTransport([{url:"https://sports.example.com/catalog/tv/crimson-sports/skip=0.json",ok:true,status:200,json:files["catalog/tv/crimson-sports/skip=0.json"]}])
catalog=CatalogStore(http).Catalog("https://sports.example.com","tv","crimson-sports")
Harness_Ok(catalog.ok,"generated skip=0 route serves actual CatalogStore")
Harness_Equal(catalog.metas.Count(),1,"one authorized feed item")
Harness_Ok(not catalog.hasMore,"static feed does not request nonexistent pages")
m.events=Sports_Normalize(SportsBody(),"football/nfl").events:RenderSportsRows()
Harness_Equal(SportsProviderCount(m.rows[0].id),1,"actual SupportsResource matches event ID")
onSportsSelected()
Harness_Equal(m.top.pushRequest.screen,"streamsScreen","game opens existing source selection")
request=m.top.pushRequest.params
Harness_Equal(request.metaType,"tv","live event uses channel playback policy")
Harness_Ok(not request.fourKOnly,"movie UHD-only preference cannot hide HD sports")
Harness_Equal(request.position,0,"live event does not resume stale VOD progress")
script=[{url:"https://sports.example.com/stream/tv/espn_football_nfl_123.json",ok:true,status:200,json:files["stream/tv/espn_football_nfl_123.json"]}]
store=PlaybackStore(ScriptedTransport(script))
sources=store.Streams("https://sports.example.com","tv",request.videoId)
Harness_Ok(sources.ok,"existing playback store accepts generated endpoint")
ranked=CinemaChooseStreams(CinemaBudgetStreams(sources.streams,256,262144),false,"projector",false)
Harness_Equal(ranked.Count(),2,"both direct options survive existing source policy")
Harness_Equal(ranked[0].url,"https://example.com/live.m3u8","HD source ranked ahead of lower fallback")
resolved=store.ResolvePlayback("",ranked[0])
Harness_Ok(resolved.ok,"native direct resolver needs no streaming server")
Harness_Equal(resolved.streamFormat,"hls","media URI resolves as HLS, not embed HTML")
Harness_Equal(resolved.mode,"direct","no external media proxy required")
Harness_Ok(ranked[0].behaviorHints.crimsonExpiresAt<>invalid,"expiry survives candidate budgeting")
ranked[0].behaviorHints.crimsonExpiresAt="2000-01-01T00:00:00Z"
Harness_Ok(not store.ResolvePlayback("",ranked[0]).ok,"expired retained fallback fails before network playback")
sources.streams[0].behaviorHints.crimsonExpiresAt="2000-01-01T00:00:00Z"
Harness_Equal(store.Streams("https://sports.example.com","tv",request.videoId).streams.Count(),1,"expired source excluded during new discovery")
Harness_Ok(PlaybackStreamExpired({behaviorHints:{crimsonExpiresAt:123}}),"malformed expiry fails closed")
Harness_Ok(not PlaybackStreamExpired({url:"https://example.com/movie.mp4"}),"ordinary movie provider unchanged")
m.sportsScreen=m.top:m.stack={calls:[],push:sub(screen as string,params as object)
    m.calls.Push({screen:screen,params:params})
end sub}
onSportsAction()
Harness_Equal(m.stack.calls.Count(),1,"production Scene routes selected sports event")
m.sportsScreen.screenActive=false:onSportsAction()
Harness_Equal(m.stack.calls.Count(),1,"hidden Sports cannot navigate away from playing video")

Harness_Suite("Honest schedule-only and upcoming behavior")
SportsReset():m.events=Sports_Normalize(SportsBody(),"football/nfl").events:RenderSportsRows()
onSportsSelected()
Harness_Equal(m.top.pushRequest,invalid,"schedule is not passed off as a playable stream")
Harness_Ok(m.status.text.InStr("Schedule only")=0,"missing providers explained")
m.events=Sports_Normalize(SportsBody("pre"),"football/nfl").events:RenderSportsRows():onSportsSelected()
Harness_Ok(m.status.text.InStr("Upcoming")=0,"upcoming event has no fabricated playback")
m.stateIndex=1:RenderSportsRows()
Harness_Equal(m.rows.Count(),0,"Live filter excludes upcoming events")
m.filters.open=true
Harness_Ok(OnBackPressed(),"Back dismisses filter menu first")
Harness_Ok(not OnBackPressed(),"second Back returns without waiting for network")
Harness_Finish()
