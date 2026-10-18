function HomeEvent(task as object, data = invalid as dynamic) as object
    return {
        task:task, data:data
        GetRoSGNode:function() as object
            return m.task
        end function
        GetData:function() as dynamic
            return m.data
        end function
    }
end function
function AsyncTask_Launch(parent as object, kind as string, callback as string, fields as object, id as string) as object
    task = {id:id, result:invalid, fields:fields}
    m.launched.Push(task)
    return task
end function
sub AsyncTask_Reap(task as object, parent as object, doStop as boolean)
    m.reaped.Push({id:task.id, stopped:doStop})
end sub
sub BuildRows()
    m.builds = m.builds + 1
    m.gridRows = m.catalogRows
end sub
function HomeClock() as object
    return {elapsed:0,Mark:sub()
        m.elapsed=0
    end sub,TotalMilliseconds:function() as integer
        return m.elapsed
    end function}
end function
function ContinueWatchingSignature() as string
    return "same"
end function
sub RefreshContinueWatching()
end sub
sub BuildRail()
    m.railBuilt=true
end sub
sub ApplyCatalogRow(row as object)
    m.catalogRows.Push(row)
end sub
sub ShowHomeBusy(show as boolean)
    m.busy = show
end sub
sub HomeReset()
    m.top = {screenActive:true}
    m.workerSequence = 0
    m.catalogRowsBuilt = false
    m.catalogTask = invalid
    m.catalogRows = []
    m.catalogRefreshClock=invalid:m.catalogRefreshing=false:m.catalogRefreshRows=[]
    m.gridBuilt=true:m.railBuilt=true:m.homeGridDirty=false:m.homeVisited=true:m.returnFocus="rail":m.cwSignature="same"
    m.quick=invalid:m.heroTitle=invalid
    m.gridRows = []
    m.launched = []
    m.reaped = []
    m.builds = 0
    m.catalogStatus = {text:""}
    m.stores = {addons:{
        callFunc:function(name as string) as object
            return [{address:"https://catalog.example", catalogs:[], name:"Catalog"}]
        end function
    }}
    m.rail = {
        focused:false
        SetFocus:sub(on as boolean)
            m.focused = on
        end sub
        HasFocus:function() as boolean
            return m.focused
        end function
        IsInFocusChain:function() as boolean
            return m.focused
        end function
    }
    m.catalog = m.rail
    m.openTask = invalid
    m.pendingOpen = invalid
end sub

Harness_Suite("Home refresh fetches again and rejects canceled catalog snapshots")
HomeReset()
StartCatalogLoad()
old = m.catalogTask
Harness_Equal(old.id, "homeCatalog1", "initial catalog request has unique identity")
Harness_Equal(m.launched.Count(), 1, "initial request launched once")
StartCatalogLoad()
Harness_Equal(m.launched.Count(), 1, "repeated entry does not duplicate pending request")
Harness_Ok(not onKeyEvent("play", false), "refresh ignores key release")
Harness_Equal(m.launched.Count(), 1, "release does not fetch")
Harness_Ok(onKeyEvent("play", true), "Play/Pause handles catalog refresh")
current = m.catalogTask
Harness_Equal(current.id, "homeCatalog2", "refresh uses new task identity")
Harness_Ok(m.reaped[0].stopped, "refresh stops previous pending worker")
Harness_Equal(m.builds, 1, "refresh rebuilds visible model once")
Harness_Ok(m.rail.focused, "refresh keeps a valid navigation target")
onCatalogState(HomeEvent(old, {rows:[{index:0,title:"Old"}],done:true}))
Harness_Equal(m.catalogRows.Count(), 0, "canceled snapshot cannot populate new catalog")
Harness_Equal(m.catalogTask.id, current.id, "old event cannot reap new worker")
onCatalogState(HomeEvent(current, invalid))
Harness_Equal(m.catalogTask.id, current.id, "blank notification keeps pending worker")
onCatalogState(HomeEvent(current, {rows:[{index:0,title:"New releases"}],done:false}))
Harness_Equal(m.catalogRows[0].title, "New releases", "current catalog results displayed")
onCatalogState(HomeEvent(current, {rows:[{index:0,title:"New releases"}],done:true}))
Harness_Equal(m.catalogRows.Count(), 1, "progress snapshots do not duplicate rows")
Harness_Ok(m.catalogRowsBuilt, "finished refresh marked complete")
Harness_Equal(m.catalogStatus.text, "", "successful refresh clears loading hint")
Harness_Equal(m.catalogTask, invalid, "finished worker disposed")
onCatalogState(HomeEvent(current, {rows:[{index:1,title:"Duplicate"}],done:true}))
Harness_Equal(m.catalogRows.Count(), 1, "duplicate completion ignored")
RebuildRows()
empty = m.catalogTask
onCatalogState(HomeEvent(empty, {rows:[],done:true}))
Harness_Ok(m.catalogStatus.text.InStr("retry") >= 0, "empty catalog gives retry control")
HomeReset()
m.stores.addons.callFunc = function(name as string) as object
    return []
end function
StartCatalogLoad()
Harness_Ok(m.catalogStatus.text.InStr("Add-ons") >= 0, "removed catalogs expose setup action")
Harness_Equal(m.launched.Count(), 0, "empty registry starts no catalog task")

Harness_Suite("Home continues watching only the selected current title")
HomeReset()
live = {id:NextHomeWorkerId("continueWatchingLoader"),result:invalid}
m.openTask = live
m.pendingOpen = {address:"https://catalog.example",meta:{id:"fallback"},resume:{position:5}}
onContinueWatchingLoaded(HomeEvent({id:"old",result:{ok:true,meta:{id:"wrong"}}}))
Harness_Equal(m.openTask.id, live.id, "stale title result does not claim new selection")
onContinueWatchingLoaded(HomeEvent(live))
Harness_Equal(m.reaped.Count(), 0, "blank title notification stays pending")
live.result = {ok:true,meta:{id:"current"}}
onContinueWatchingLoaded(HomeEvent(live))
Harness_Equal(m.top.pushRequest.params.meta.id, "current", "current selected title opens")
Harness_Equal(m.top.pushRequest.params.resume.position, 5, "resume point preserved")
Harness_Equal(m.pendingOpen, invalid, "selection context cleared after completion")
Harness_Equal(m.openTask, invalid, "current title worker disposed")

Harness_Suite("Home re-entry refreshes stale catalogs without clearing usable titles")
HomeReset()
StartCatalogLoad():task=m.catalogTask
oldRow={index:0,title:"Popular",addonAddress:"https://catalog.example",catalogId:"top",genre:"",metaType:"movie",metas:[{id:"one",name:"One",type:"movie"},{id:"two",name:"Two",type:"movie"}]}
onCatalogState(HomeEvent(task,{rows:[oldRow],done:true}))
m.gridRows=m.catalogRows:m.catalog.rowItemFocused=[0,1]
OnEnter(invalid)
Harness_Equal(m.launched.Count(),1,"fresh production OnEnter does not refetch")
m.catalogRefreshClock.elapsed=1799999:OnEnter(invalid)
Harness_Equal(m.launched.Count(),1,"catalog remains fresh just before thirty minutes")
m.catalogRefreshClock.elapsed=1800000:OnEnter(invalid)
Harness_Equal(m.launched.Count(),2,"stale production OnEnter starts one refresh")
current=m.catalogTask
Harness_Equal(m.catalogRows[0].title,"Popular","stale refresh keeps the old visible model")
OnEnter(invalid)
Harness_Equal(m.launched.Count(),2,"repeated OnEnter cannot duplicate pending refresh")
newRow={index:0,title:"Updated",addonAddress:"https://catalog.example",catalogId:"top",genre:"",metaType:"movie",metas:[{id:"two",name:"Two",type:"movie"},{id:"one",name:"One",type:"movie"}]}
onCatalogState(HomeEvent(current,{rows:[newRow],done:false}))
Harness_Equal(m.catalogRows[0].title,"Popular","partial progress does not replace the current grid")
onCatalogState(HomeEvent(current,{rows:[newRow],done:true}))
Harness_Equal(m.catalogRows[0].title,"Updated","completed refresh adopts current titles")
Harness_Equal(m.catalog.jumpToRowItem[1],0,"selected title is restored after provider reordering")
Harness_Ok(m.rail.focused,"refresh completion does not steal remote focus")
m.catalogRefreshClock.elapsed=1800000:OnEnter(invalid):current=m.catalogTask
onCatalogState(HomeEvent(current,{rows:[],done:true,error:"unavailable"}))
Harness_Equal(m.catalogRows[0].title,"Updated","failed refresh preserves the last usable titles")
Harness_Ok(m.catalogStatus.text.InStr("previous")>=0,"failed retained refresh is explained honestly")
m.catalogRefreshClock.elapsed=1800000:m.top.screenActive=false:OnEnter(invalid)
Harness_Equal(m.launched.Count(),3,"hidden production OnEnter cannot start work during playback")
m.top.screenActive=true:OnEnter(invalid):current=m.catalogTask
BlurFocus()
Harness_Equal(m.catalogTask,invalid,"leaving Home cancels an automatic refresh")
onCatalogState(HomeEvent(current,{rows:[oldRow],done:true}))
Harness_Equal(m.catalogRows[0].title,"Updated","canceled refresh cannot replace data underneath playback")
m.gridRows=[{source:"library",metas:[{id:"remaining",type:"movie",name:"Remaining"}]}]
RestoreHomeCatalogSelection({row:0,column:1,id:"removed"})
Harness_Equal(m.catalog.jumpToRowItem[1],0,"Continue Watching without See all clamps to an existing tile")
HomeReset():StartCatalogLoad():current=m.catalogTask
onCatalogState(HomeEvent(current,{rows:[],done:true}))
m.catalogRefreshClock.elapsed=1800000:OnEnter(invalid):current=m.catalogTask
onCatalogState(HomeEvent(current,{rows:[oldRow],done:true}))
Harness_Equal(m.catalogRows.Count(),1,"a previously empty catalog can recover on stale re-entry")
Harness_Finish()
if m.failed > 0
    failure = invalid
    ignored = failure.assertion
end if
