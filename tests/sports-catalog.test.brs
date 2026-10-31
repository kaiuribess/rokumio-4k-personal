function SportsCatalogFixture(id as string, name as string, catalogId as string, kind = "sport" as string) as object
    return {id:id,name:name,version:"1.0.0",resources:["catalog","stream"],types:[kind],catalogs:[{id:catalogId,name:"Basketball",type:kind,extra:[{name:"skip"}]}]}
end function

sub SportsBrowserFixture()
    SportsReset():m.browseProviders=true:m.catalogView="sports":m.allowUnknownLiveAudio=true
    m.addons.InstallFromDescriptor("https://first.example/private-fixture/manifest.json?token=fixture",SportsCatalogFixture("first","First provider","sports_basketball"))
    m.addons.InstallFromDescriptor("https://second.example/manifest.json",SportsCatalogFixture("second","Second provider","nba-games","tv"))
    SportsCatalogs():SportsBrowserEnter({}):RenderSportsCatalogs()
end sub

sub SportsDeliverCatalog(metas as object, ok = true as boolean, hasMore = false as boolean)
    task=m.browserTask:owner=m.top
    m.workerHttp=ScriptedTransport([{ok:ok,status:200,json:{metas:metas,hasMore:hasMore}}])
    m.top=task:loadSportsCatalog():m.top=owner
    onSportsCatalogResult(SportsTestEvent(task))
    onSportsCatalogFinished(SportsTestEvent(task))
end sub

function SportsFindRow(kind as string) as integer
    for i=0 to m.rows.Count()-1
        if m.rows[i].kind=kind then return i
    end for
    return -1
end function

Harness_Suite("Sport categories cover installed catalogs without exposing provider configuration")
for each fixture in [["sports_basketball","basketball"],["NBA games","basketball"],["NFL","football"],["College Football","football"],["Football","soccer"],["Soccer","soccer"],["MLB","baseball"],["NHL","hockey"],["UFC","mma"],["Boxing","boxing"],["F1","motorsport"],["MotoGP","motorsport"],["Tennis","tennis"],["Golf","golf"],["Cricket","cricket"],["Rugby","rugby"],["WWE","wrestling"],["Volleyball","volleyball"],["Cycling","cycling"],["Darts","darts"],["Snooker","snooker"],["Esports","esports"],["TV channels","channels"],["Mixed Live Events","other"]]
    Harness_Equal(Sports_Category(fixture[0]),fixture[1],"catalog category: "+fixture[0])
end for
SportsBrowserFixture()
Harness_Equal(m.rows[0].key,"basketball","default front door groups two providers into one basketball row")
Harness_Equal(m.rows.Count(),3,"one sport, advanced provider browsing, manage add-ons")
visible=""
for each row in m.list.content.children
    visible=visible+row.children[0].title+row.children[0].description
end for
Harness_Ok(visible.InStr("private-fixture")<0,"configured URL never shown in content")
Harness_Equal(m.launches,0,"root needs no network")
m.list.rowItemSelected=[0,0]:onSportsSelected()
Harness_Equal(m.browserMode,"events","actual screen selection opens shared game list")
Harness_Equal(m.launches,1,"one catalog worker at a time")
first=m.browserTask
onSportsCatalogResult(SportsTestEvent(first))
Harness_Equal(m.browserTask.id,first.id,"empty result notification retains worker ownership")
SportsDeliverCatalog([{id:"native:first",type:"sport",name:"LIVE: Home vs Away",status:"live",startTime:"2026-11-01T20:00:00Z",competition:"NBA"}])
Harness_Equal(m.browserEvents.Count(),1,"real worker/store/callback produces one clean event")
Harness_Equal(m.browserEvents[0].name,"Home vs Away","provider status prefix removed from display title")
Harness_Equal(m.workerHttp.log[0].timeoutMs,10000,"catalog worker network deadline is bounded")
Harness_Ok(m.workerHttp.log[0].url.InStr("/private-fixture/catalog/sport/sports_basketball/skip=0.json?token=fixture")>0,"private path/query and original type kept by production store")
Harness_Equal(m.launches,2,"second catalog starts only after finished")
onSportsCatalogFinished(SportsTestEvent(first))
Harness_Equal(m.launches,2,"duplicate finished cannot launch another request")
SportsDeliverCatalog([{id:"native:second",type:"tv",name:"Home - Away",status:"live",startTime:"2026-11-01T20:00Z",competition:"NBA"}])
Harness_Equal(m.browserEvents.Count(),1,"exact participants, competition, UTC time and state combine event")
Harness_Equal(m.browserEvents[0].routes.Count(),2,"both original provider routes retained")
Harness_Equal(m.browserTask,invalid,"last worker fully reaped")
SportsBrowserSelect(0)
Harness_Equal(m.rows[0].kind,"watch","event opens primary Watch action")
Harness_Equal(m.rows[1].kind,"sources","manual alternatives live under More sources")
SportsBrowserSelect(0):watch=m.top.pushRequest.params
Harness_Ok(watch.autoPlay and watch.livePlayback,"Watch reuses native automatic live playback")
Harness_Equal(watch.videoId,"native:first","Watch retains original primary ID")
Harness_Ok(watch.addonAddress.InStr("private-fixture")>0,"Watch remains scoped to original configured provider")
Harness_Ok(not watch.autoNextEpisode and not watch.onlineSubtitles and watch.position=0,"live playback cannot acquire movie resume/episode policy")
Harness_Ok(not watch.fourKOnly,"sports HD sources stay eligible")
SportsBrowserSelect(1)
Harness_Equal(m.browserMode,"sources","More sources opens manual provider options")
SportsBrowserSelect(1):manual=m.top.pushRequest.params
Harness_Equal(manual.videoId,"native:second","backup uses its own opaque ID")
Harness_Equal(manual.metaType,"tv","backup retains its declared resource type")
Harness_Equal(manual.addonAddress,"https://second.example","no foreign event ID is sent to primary")
Harness_Ok(not manual.autoPlay,"manual provider option opens existing stream picker")
Harness_Ok(SportsBrowserBack(),"Back from source options stays inside Sports")
Harness_Equal(m.browserMode,"event","Back restores event actions")
Harness_Ok(SportsBrowserBack(),"Back from actions restores events")
Harness_Equal(m.browserMode,"events","event list retained without another fetch")
Harness_Equal(m.launches,2,"no catalog refetch caused by menu navigation")

Harness_Suite("Conservative event identity: uncertain matches stay separate")
entry=m.catalogs[1]
base={id:"a",name:"Home vs Away",status:"live",startTime:"2026-11-01T20:00:00Z",competition:"NBA"}
item=Sports_NormalizeCatalogItem(base,entry)
key=item.matchKey
Harness_Ok(key<>"","complete event has match evidence")
for each change in [{startTime:"2026-11-02T20:00:00Z"},{competition:"College"},{status:"replay"},{status:"postponed"},{name:"Away vs Home"},{startTime:"2026-11-01"},{competition:""},{startTime:""},{status:""}]
    changed=ParseJson(FormatJson(base))
    for each field in change
        changed[field]=change[field]
    end for
    candidate=Sports_NormalizeCatalogItem(changed,entry)
    Harness_Ok(candidate.matchKey<>key,"date/competition/state/participants/unknowns do not silently match")
end for
Harness_Equal(Sports_NormalizeCatalogItem({id:"a",name:"NBA TV",status:"live",startTime:base.startTime,competition:"NBA"},entry).matchKey,"","linear channel is not a verified game match")
Harness_Equal(Sports_NormalizeCatalogItem({id:String(2049,"x"),name:"Game"},entry),invalid,"oversized opaque ID rejected, never truncated into another event")
Harness_Equal(Sports_NormalizeCatalogItem({id:"a",name:"Game",type:"movie"},entry),invalid,"mismatched type is not silently rerouted")
SportsBrowserReset():m.browserMode="events"
SportsBrowserAddEvent(item):SportsBrowserAddEvent(item)
Harness_Equal(m.browserEvents.Count(),1,"same-provider exact native identity deduplicated")
Harness_Equal(m.browserRouteCount,1,"duplicate catalog appearances do not consume route budget")
other=Sports_NormalizeCatalogItem({id:"x",name:"Home vs Away"},m.catalogs[2])
SportsBrowserAddEvent(other)
Harness_Equal(m.browserEvents.Count(),2,"same title without time/competition remains independently usable")

Harness_Suite("Actual worker handles malformed data, failure and raw pagination offsets")
SportsBrowserFixture():SportsBrowserStart("basketball","Basketball")
task=m.browserTask:owner=m.top:metas=[invalid,{id:"bad"}]
for i=1 to 60
    metas.Push({id:i.ToStr(),name:"Game "+i.ToStr(),type:"sport"})
end for
m.workerHttp=ScriptedTransport([{ok:true,status:200,json:{metas:metas,hasMore:true}}])
m.top=task:loadSportsCatalog():m.top=owner
Harness_Equal(task.result.events.Count(),48,"Task boundary returns at most 48 bounded records")
Harness_Equal(task.result.nextOffset,50,"skip offset includes invalid raw records before valid items")
Harness_Ok(task.result.hasMore,"remainder retained for next request")
onSportsCatalogResult(SportsTestEvent(task)):onSportsCatalogFinished(SportsTestEvent(task))
SportsDeliverCatalog([],false)
Harness_Equal(m.browserEvents.Count(),48,"failed backup does not erase primary event list")
Harness_Equal(m.browserFailed.Count(),1,"catalog failure is visible and retryable")
Harness_Ok(SportsFindRow("retry")>=0,"retry action is exposed")
SportsBrowserSelect(SportsFindRow("retry"))
Harness_Equal(m.browserTask.entry.provider,"Second provider","retry addresses the failed provider only")
SportsDeliverCatalog([{id:"second-game",name:"Different game",type:"tv"}])
Harness_Equal(m.browserEvents.Count(),49,"retry adds usable data to retained results")
Harness_Ok(SportsFindRow("next")>=0,"49th event stays reachable beyond the 48-row page")
SportsBrowserSelect(SportsFindRow("next"))
Harness_Equal(m.rows[0].index,48,"next page exposes later event")
Harness_Ok(SportsFindRow("previous")>=0,"earlier events stay reachable")
SportsBrowserSelect(SportsFindRow("load"))
Harness_Equal(m.browserTask.offset,50,"next network page uses raw offset")
SportsDeliverCatalog(metas)
Harness_Ok(m.browserNotices>0,"provider ignoring skip ends repeated-page loop honestly")
Harness_Equal(m.browserMore.Count(),0,"ignored skip cannot enqueue infinite next pages")

entry=m.catalogs[1]:entry.skipSupported=false
answer={ok:true,metas:[],rawCount:100,hasMore:true}
for i=1 to 100
    answer.metas.Push({id:i.ToStr(),name:"Game "+i.ToStr()})
end for
page=Sports_CatalogPage(answer,entry,48)
Harness_Equal(page.events.Count(),48,"non-paginated catalogs support local slices")
Harness_Equal(page.events[0].routes[0].videoId,"49","local pagination starts after previous slice")
page=Sports_CatalogPage(answer,entry,96)
Harness_Equal(page.events.Count(),4,"last local slice retains every remaining event")
Harness_Ok(not page.hasMore,"local last page ends despite heuristic upstream hasMore")

Harness_Suite("Back, covered screens and stale workers cannot change navigation or overcommit")
SportsBrowserFixture():SportsBrowserStart("basketball","Basketball")
old=m.browserTask:oldGeneration=m.browserGeneration
Harness_Ok(OnBackPressed(),"Back from loading immediately returns to sports groups")
Harness_Equal(m.browserMode,"groups","Back does not wait for network")
SportsBrowserStart("basketball","Basketball")
Harness_Equal(m.launches,1,"new navigation waits for existing transfer ownership")
SportsDeliverCatalog([{id:"old",name:"Old game",type:"sport"}])
Harness_Equal(m.browserEvents.Count(),0,"stale catalog cannot repaint a new generation")
Harness_Equal(m.launches,2,"latest request starts only after old FINISHED")
task=m.browserTask:m.top.screenActive=false
SportsDeliverCatalog([{id:"hidden",name:"Hidden game",type:"sport"}])
Harness_Equal(m.browserEvents.Count(),0,"hidden screen does not adopt result or steal focus")
Harness_Equal(m.launches,2,"no additional catalog requests behind playback")
m.top.screenActive=true:SportsBrowserPump()
Harness_Equal(m.launches,3,"deferred provider is retried on interactive return")
task=m.browserTask:task.finished=true:onSportsCatalogFinished(SportsTestEvent(task))
Harness_Equal(m.browserFailed.Count(),1,"finished-without-result is retryable, never a successful empty page")
SportsBrowserReset():m.browserEpoch=99
task=m.browserTask
if task<>invalid
    task.result={ok:true,events:[item]}:onSportsCatalogResult(SportsTestEvent(task))
end if
Harness_Equal(m.browserEvents.Count(),0,"account epoch mismatch rejects worker data")

Harness_Suite("All raw catalogs remain accessible through bounded pages")
SportsReset():m.browseProviders=true:m.catalogView="providers"
large=SportsCatalogFixture("many","Many","placeholder")
large.catalogs=[]
for i=1 to 64
    large.catalogs.Push({type:"sport",id:i.ToStr(),name:"Basketball "+i.ToStr()})
end for
m.addons.InstallFromDescriptor("https://many.example/manifest.json",large)
SportsCatalogs():RenderSportsCatalogs()
Harness_Equal(m.catalogs.Count(),65,"no 40-catalog truncation")
Harness_Equal(m.rows.Count(),49,"48 catalog rows plus next page")
m.list.rowItemSelected=[48,0]:onSportsSelected()
Harness_Equal(m.rows[0].catalogIndex,48,"remote selection reaches catalogs after the first page")
m.list.rowItemSelected=[16,0]:onSportsSelected()
Harness_Equal(m.top.pushRequest.params.catalogId,"64","last valid catalog reaches existing Discover")

Harness_Suite("Bounded batches retain queued providers instead of discarding later games")
SportsBrowserFixture()
for i=3 to 6
    manifest=SportsCatalogFixture("provider"+i.ToStr(),"Provider "+i.ToStr(),"basketball")
    m.addons.InstallFromDescriptor("https://provider"+i.ToStr()+".example/manifest.json",manifest)
end for
SportsCatalogs():SportsBrowserEnter({}):SportsBrowserStart("basketball","Basketball")
for p=1 to 5
    metas=[]
    for i=1 to 48
        metas.Push({id:"p"+p.ToStr()+"-"+i.ToStr(),name:"Game "+p.ToStr()+" / "+i.ToStr(),type:m.browserTask.entry.params.metaType})
    end for
    SportsDeliverCatalog(metas)
end for
Harness_Equal(m.browserRouteCount,240,"active batch has at most 240 original routes")
Harness_Equal(m.browserQueue.Count(),1,"later provider stays queued beyond the batch budget")
Harness_Equal(m.browserTask,invalid,"no further transfer starts behind a full batch")
Harness_Ok(m.rows.Count()<=52,"only one 48-event UI page plus navigation is created")
SportsBrowserSelect(SportsFindRow("load"))
Harness_Equal(m.browserRouteCount,0,"explicit next batch releases retained event data")
Harness_Equal(m.browserTask.entry.provider,"Provider 6","next batch reaches the previously queued provider")
SportsDeliverCatalog([{id:"last",name:"Last provider game",type:"sport"}])
Harness_Equal(m.browserEvents[0].routes[0].videoId,"last","later provider is not silently lost")

Harness_Suite("Launch failures, refresh and changed installed providers remain recoverable")
SportsBrowserFixture():m.failLaunch=true
SportsBrowserStart("basketball","Basketball")
Harness_Equal(m.browserTask,invalid,"failed launch never occupies a worker slot")
Harness_Equal(m.browserQueue.Count(),0,"failed task creation cannot leave an unpumped queue")
Harness_Equal(m.browserFailed.Count(),2,"all deferred catalogs remain available for explicit retry")
Harness_Ok(SportsFindRow("retry")>=0,"launch failure paints an actionable retry row")
m.failLaunch=false:SportsBrowserSelect(SportsFindRow("retry"))
SportsDeliverCatalog([{id:"retry-ok",name:"Recovered",type:"sport"}])
Harness_Equal(m.browserEvents.Count(),1,"retry after task-creation failure restores catalog results")
old=m.browserTask
m.catalogs=[{raw:"",label:"Manage add-ons"}]:SportsBrowserEnter(invalid)
Harness_Equal(m.browserEvents.Count(),0,"registry change clears removed provider data")
old.result={ok:true,events:[item]}:old.finished=true
onSportsCatalogFinished(SportsTestEvent(old))
Harness_Equal(m.browserEvents.Count(),0,"removed provider's delayed result stays rejected")

Harness_Suite("Upcoming actions, recorded mode and freshness keep distinct playback semantics")
SportsBrowserFixture():SportsBrowserStart("basketball","Basketball")
SportsDeliverCatalog([{id:"future",name:"Upcoming: Home vs Away",status:"upcoming",type:"sport"}])
SportsDeliverCatalog([])
SportsBrowserSelect(0):m.top.pushRequest=invalid:SportsBrowserSelect(0)
Harness_Equal(m.top.pushRequest,invalid,"upcoming event does not launch a guessed live stream")
Harness_Ok(m.status.text.InStr("Upcoming")=0,"upcoming event explains when to retry")
m.livePlayback=false:SportsBrowserSelect(0)
Harness_Equal(m.top.pushRequest.screen,"detailsScreen","recorded choice keeps established Details flow")
Harness_Equal(m.top.pushRequest.params.meta.id,"future","recorded metadata retains native ID")
m.sportsScreen=m.top:m.stack={calls:[],push:sub(screen as string,params as object)
    m.calls.Push({screen:screen,params:params})
end sub}
onSportsAction()
Harness_Equal(m.stack.calls[0].screen,"detailsScreen","actual Scene accepts recorded catalog selection")
m.livePlayback=true:m.browserMode="events":m.browserClock.elapsed=30001
before=m.launches:SportsBrowserEnter(invalid)
Harness_Equal(m.launches,before+1,"stale event list starts fresh lookup only on interactive return")
Harness_Equal(m.browserTask.offset,0,"refresh uses first page and fresh provider URLs")

Harness_Suite("Provider browsing return resumes deferred work; truncation never creates matches")
SportsBrowserFixture():SportsBrowserStart("basketball","Basketball")
SportsDeliverCatalog([{id:"first",name:"First game",type:"sport"}])
SportsBrowserSelect(SportsFindRow("providers"))
Harness_Equal(m.catalogView,"providers","advanced browsing can cover a loading event list")
SportsDeliverCatalog([{id:"second",name:"Second game",type:"tv"}])
Harness_Equal(m.browserTask,invalid,"covered request is reaped")
Harness_Equal(m.browserQueue.Count(),1,"deferred result retains its provider for interactive retry")
Harness_Ok(OnBackPressed(),"Back restores the grouped list")
Harness_Ok(m.browserTask<>invalid,"return from provider browsing resumes deferred catalog work")
long={id:"long",name:String(160,"a")+" vs away",competition:"NBA",startTime:"2026-11-01T20:00Z",status:"live"}
Harness_Equal(Sports_NormalizeCatalogItem(long,m.catalogs[1]).matchKey,"","truncated name cannot become a cross-provider match")
long.name="Home vs Away":long.competition=String(101,"n")
Harness_Equal(Sports_NormalizeCatalogItem(long,m.catalogs[1]).matchKey,"","truncated competition cannot become a cross-provider match")
Harness_Suite("Progressive arrivals preserve the selected action instead of pointing at another game")
SportsBrowserFixture():SportsBrowserStart("basketball","Basketball")
m.list.rowItemFocused=[SportsFindRow("providers"),0]
SportsDeliverCatalog([{id:"one",name:"One",type:"sport"},{id:"two",name:"Two",type:"sport"}])
Harness_Equal(m.rows[m.list.rowItemFocused[0]].kind,"providers","new event rows do not move focus from a footer action onto a game")
m.list.rowItemFocused=[1,0]
SportsDeliverCatalog([{id:"three",name:"Three",type:"tv"}])
Harness_Equal(m.rows[m.list.rowItemFocused[0]].index,1,"new provider results keep selected event identity stable")
Harness_Finish()
