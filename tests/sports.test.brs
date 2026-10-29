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
Harness_Suite("Hosted-provider response shape crosses registry, Sports, Discover, stream and resolver boundaries")
SportsReset():m.browseProviders=true:m.livePlayback=true:m.allowUnknownLiveAudio=true
manifest={id:"com.example.sports",name:"Fixture live provider",version:"3.0.0",resources:["catalog","meta","stream"],types:["tv"],idPrefixes:["stremevent_"],catalogs:[{type:"tv",id:"provider_live_events",name:"Live Events",extra:[{name:"search"},{name:"skip"}]}]}
installed=m.addons.InstallFromDescriptor("https://sports.example/config/fixture/manifest.json?token=fixture",manifest)
Harness_Ok(installed.ok,"configured hosted-style manifest installs through real store")
SportsCatalogs():RenderSportsCatalogs()
Harness_Equal(m.rows.Count(),2,"installed provider shown without generating a schedule feed")
Harness_Equal(m.launches,0,"provider browsing does not issue ESPN lookups")
OpenSportsCatalog(1):entry=m.top.pushRequest.params
Harness_Ok(entry.livePlayback and entry.allowUnknownLiveAudio,"Sports transfers explicit live/audio policy")
Harness_Ok(entry.addonAddress.InStr("config/fixture")>=0,"configuration path preserved privately")
id="stremevent_merged_"+String(340,"A")
transport=ScriptedTransport([{ok:true,status:200,json:{metas:[{id:id,type:"tv",name:"Copa fixture"}]}}])
catalog=CatalogStore(transport).Catalog(entry.addonAddress,entry.metaType,entry.catalogId)
Harness_Ok(catalog.ok,"actual catalog client accepts provider-native items")
m.selectedCatalog={address:entry.addonAddress,rawType:entry.metaType,catalogId:entry.catalogId}:m.liveEntry=entry
m.metas=catalog.metas:m.grid={rowItemSelected:[0,0]}:m.chunk=5
SportsDiscoverSelected():request=m.top.pushRequest.params
Harness_Equal(m.top.pushRequest.screen,"streamsScreen","actual Discover callback opens source picker")
Harness_Equal(request.videoId,id,"opaque ID remains original, not an ESPN identifier")
streams=[{name:"SV",title:"HD SERVER",url:"https://media.example/live.m3u8?token=temporary-fixture",behaviorHints:{proxyHeaders:{request:{Referer:"https://provider.example/","User-Agent":"Fixture client"}}}},{name:"Open browser",externalUrl:"https://provider.example/watch"}]
transport=ScriptedTransport([{ok:true,status:200,json:{streams:streams}}])
playback=PlaybackStore(transport):answer=playback.Streams(request.addonAddress,request.metaType,request.videoId)
Harness_Ok(transport.log[0].url.InStr("/stream/tv/"+id+".json")>=0,"stream endpoint receives original event ID")
Harness_Ok(Right(transport.log[0].url,14)="?token=fixture","configured query retained on stream endpoint")
budgeted=CinemaBudgetStreams(answer.streams,256,262144)
Harness_Equal(CinemaSkippedSources(budgeted).browserOnly,1,"external browser option is diagnosed, never sent to Video")
ranked=CinemaChooseStreams(budgeted,false,"projector",false)
Harness_Equal(ranked.Count(),1,"only direct HTTPS stream reaches playback")
resolved=playback.ResolvePlayback("",ranked[0])
Harness_Equal(resolved.url,streams[0].url,"temporary media query survives exact resolution")
Harness_Equal(resolved.headers.Count(),2,"provider-required headers survive response budgeting")
Harness_Equal(resolved.streamFormat,"hls","live source uses native HLS")
Harness_Equal(CinemaResolutionHint(ranked[0]),0,"HD SERVER name is not proof of HD dimensions")
Harness_Ok(not request.autoNextEpisode,"live route never advances a movie or series")
OpenSportsCatalog(0)
Harness_Equal(m.top.pushRequest.screen,"addonsScreen","provider installation remains explicit")

Harness_Suite("Manual provider switch keeps native IDs separate")
backup={id:"com.example.backup",name:"Backup fixture",version:"1.0.0",resources:["catalog","stream"],types:["tv"],idPrefixes:["other_"],catalogs:[{id:"other-live",type:"tv",name:"Other live"}]}
Harness_Ok(m.addons.InstallFromDescriptor("https://backup.example/config/fixture/manifest.json",backup).ok,"backup registers independently")
OnEnter({backupMode:true,previousEventName:"Home vs Away",previousProviderAddress:entry.addonAddress,allowUnknownLiveAudio:false})
Harness_Equal(m.catalogs[1].params.catalogId,"other-live","other provider catalogs are offered before current provider")
Harness_Ok(m.catalogs[2].label.InStr("Current")=0,"previous provider labeled honestly")
Harness_Ok(m.status.text.InStr("Home vs Away")>=0,"original event name remains visible for comparison")
Harness_Ok(not m.allowUnknownLiveAudio,"strict live audio choice survives manual switch")
OpenSportsCatalog(1):other=m.top.pushRequest.params
Harness_Equal(other.previousEventName,"Home vs Away","human comparison label reaches new catalog")
Harness_Equal(other.videoId,invalid,"no foreign provider event ID sent to catalog")
m.selectedCatalog={address:other.addonAddress,rawType:"tv",catalogId:"other-live"}:m.liveEntry=other
m.metas=[{id:"other_original_987",type:"tv",name:"Home vs Away"}]:m.grid={rowItemSelected:[0,0]}:m.chunk=5
SportsDiscoverSelected()
Harness_Equal(m.top.pushRequest.params.videoId,"other_original_987","backup selection uses its own event ID")
Harness_Equal(m.top.pushRequest.params.addonAddress,other.addonAddress,"backup playback remains scoped to backup owner")
OnEnter({})
Harness_Equal(m.previousEventName,"","ordinary Sports entry clears stale comparison context")

Harness_Suite("Provider sports type survives catalog and player boundaries")
sportManifest={id:"com.example.sports-type",name:"Sports type fixture",version:"1.0.0",resources:["catalog","stream"],types:["sports"],catalogs:[{id:"sports-native-live",type:"sports",name:"Live"}]}
Harness_Ok(m.addons.InstallFromDescriptor("https://sports-type.example/config/fixture/manifest.json",sportManifest).ok,"custom sports provider registers through production store")
SportsCatalogs()
sportIndex=-1
for i=1 to m.catalogs.Count()-1
    if m.catalogs[i].params.catalogId="sports-native-live" then sportIndex=i
end for
Harness_Ok(sportIndex>0,"sports resource is visible beside tv catalogs")
OpenSportsCatalog(sportIndex):sportEntry=m.top.pushRequest.params
Harness_Equal(sportEntry.metaType,"sports","catalog request keeps declared sports type")
m.selectedCatalog={address:sportEntry.addonAddress,rawType:"sports",catalogId:"sports-native-live"}:m.liveEntry=sportEntry
m.metas=[{id:"provider:sports:original",type:"sports",name:"Home vs Away"}]:m.grid={rowItemSelected:[0,0]}:m.chunk=5
SportsDiscoverSelected()
Harness_Equal(m.top.pushRequest.screen,"streamsScreen","sports type takes explicit live source path")
Harness_Equal(m.top.pushRequest.params.metaType,"sports","native stream request preserves provider sports type")
Harness_Equal(m.top.pushRequest.params.videoId,"provider:sports:original","sports native ID never becomes ESPN ID")
sportRequest=m.top.pushRequest.params
sportTransport=ScriptedTransport([{ok:true,status:200,json:{streams:[{url:"https://media.example/live.m3u8?token=fixture"}]}}])
sportPlayback=PlaybackStore(sportTransport)
sportAnswer=sportPlayback.Streams(sportRequest.addonAddress,sportRequest.metaType,sportRequest.videoId)
Harness_Ok(sportAnswer.ok,"production source store admits the custom sports type")
Harness_Ok(sportTransport.log[0].url.InStr("/stream/sports/provider%3Asports%3Aoriginal.json")>=0,"source request retains type and escaped native ID")
Harness_Ok(sportPlayback.ResolvePlayback("",sportAnswer.streams[0]).ok,"custom sports source reaches existing direct resolver")

Harness_Suite("Scene backup action reuses real stack without duplicate static screens")
scene={nodes:{},FindNode:function(id as string) as object
    return m.nodes[id]
end function}
for each name in ["homeScreen","sportsScreen","discoverScreen","streamsScreen"]
    scene.nodes[name]={id:name,screenActive:false,calls:[],SetFocus:sub(value as boolean)
        m.focus=value
    end sub,callFunc:function(name as string,params=invalid as dynamic) as dynamic
        m.calls.Push({name:name,params:params})
        return invalid
    end function}
end for
m.stack=ScreenStack(scene)
for each name in ["homeScreen","sportsScreen","discoverScreen","streamsScreen"]
    m.stack.push(name,{})
end for
m.streamsScreen=scene.nodes.streamsScreen:m.sportsScreen=scene.nodes.sportsScreen
m.streamsScreen.pushRequest={screen:"sportsScreen",params:{backupMode:true,previousEventName:"Home vs Away"}}
onStreamsAction()
Harness_Equal(m.stack.count(),2,"backup navigation unwinds sources and catalog instead of duplicating Sports")
Harness_Equal(m.stack.top().id,"sportsScreen","Sports is interactive after manual action")
calls=m.sportsScreen.calls
Harness_Equal(calls[calls.Count()-1].params.previousEventName,"Home vs Away","actual Scene hands comparison context to Sports OnEnter")
Harness_Ok(not m.streamsScreen.screenActive,"old source screen deactivated")
onStreamsAction()
Harness_Equal(m.stack.count(),2,"duplicate hidden source action is ignored")

Harness_Suite("Backup priority applies before catalog row budget")
SportsReset():m.previousProviderAddress="https://large.example"
large={id:"com.example.large",name:"Large",version:"1.0.0",resources:["catalog","stream"],types:["tv"],catalogs:[]}
for i=1 to 45
    large.catalogs.Push({id:"catalog"+i.ToStr(),type:"tv",name:"Catalog"})
end for
Harness_Ok(m.addons.InstallFromDescriptor("https://large.example/manifest.json",large).ok,"large current provider is valid")
Harness_Ok(m.addons.InstallFromDescriptor("https://backup.example/manifest.json",backup).ok,"later backup provider registers normally")
SportsCatalogs()
Harness_Equal(m.catalogs.Count(),40,"existing catalog row budget remains bounded")
Harness_Equal(m.catalogs[1].params.addonAddress,"https://backup.example","large current provider cannot hide the backup before sorting")
Harness_Ok(m.catalogs[2].label.InStr("Current")=0,"current provider remains distinguishable after priority")

Harness_Finish()
