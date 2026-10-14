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
end sub
sub ApplyCatalogRow(row as object)
    m.catalogRows.Push(row)
end sub
sub ShowHomeBusy(show as boolean)
    m.busy = show
end sub
sub HomeReset()
    m.top = {}
    m.workerSequence = 0
    m.catalogRowsBuilt = false
    m.catalogTask = invalid
    m.catalogRows = []
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
Harness_Finish()
if m.failed > 0
    failure = invalid
    ignored = failure.assertion
end if
