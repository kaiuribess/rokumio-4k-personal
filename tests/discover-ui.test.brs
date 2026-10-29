function DiscoverTest_Event(task as object, data as dynamic) as object
    return {
        task: task
        data: data
        GetRoSGNode: function() as object
            return m.task
        end function
        GetData: function() as dynamic
            return m.data
        end function
    }
end function

function MockDiscoverNativeObject(kind as string, nodeType = "" as string) as object
    if kind="roTimespan" then return {elapsed:0,Mark:sub()
        m.elapsed=0
    end sub,TotalMilliseconds:function() as integer
        return m.elapsed
    end function}
    node = { children: [] }
    node.CreateChild = function(childType as string) as object
        child = MockDiscoverNativeObject("roSGNode", childType)
        m.children.Push(child)
        return child
    end function
    return node
end function

sub DiscoverTest_Reset()
    m.workerSequence = 0
    m.nextPageOffset = 0
    m.catalogRefreshClock=invalid:m.catalogRefreshing=false
    m.sourcesTask = invalid
    m.loadTask = invalid
    m.sources = []
    m.sourcesSignature = ""
    m.metas = []
    m.loaded = false
    m.allLoaded = false
    m.chunk = 5
    m.rowWidth = 1660
    m.rowGap = 18
    m.status = { text: "" }
    m.header = { text: "" }
    m.top = { screenActive: true }
    m.grid = {
        rowItemFocused: [0, 0]
        itemFocused: 0
        focused: false
        SetFocus: sub(on as boolean)
            m.focused = on
        end sub
        HasFocus: function() as boolean
            return m.focused
        end function
    }
    m.filterBar = {
        chipFocusCount: 0
        callFunc: function(name as string) as dynamic
            if name = "IsMenuOpen" then return false
            if name = "FocusIsOnChips" then return true
            if name = "FocusChips" then m.chipFocusCount = m.chipFocusCount + 1
            return invalid
        end function
    }
    m.stores = {
        addons: {
            values: []
            callFunc: function(name as string) as object
                return m.values
            end function
        }
        library: {
            callFunc: function(name as string, id as string, mediaType as string) as string
                return ""
            end function
        }
    }
    m.selectedCatalog = { address: "https://catalog.example", rawType: "movie", catalogId: "top", title: "Movies" }
    m.reaped = []
    m.launched = []
    m.ready = 0
end sub

function AsyncTask_Launch(parent as object, taskType as string, callback as string, fields as object, id as string) as object
    task = { id: id, taskType: taskType, result: invalid }
    for each key in fields
        task[key] = fields[key]
    end for
    m.launched.Push(task)
    return task
end function
sub AsyncTask_Reap(task as object, parent as object, doStop as boolean)
    m.reaped.Push({ id: task.id, stopped: doStop })
end sub
sub ReadySources()
    m.ready = m.ready + 1
end sub
sub ShowEmpty()
    m.status.text = "No catalog add-ons installed."
end sub
function GenreFilter() as string
    return "Drama"
end function
function DiscoverLabel() as string
    return "Movies"
end function

Harness_Suite("Discover rejects canceled source events and waits for real data")
DiscoverTest_Reset()
m.sources = [{ address: "https://old.example" }]
m.sourcesSignature = "old"
m.stores.addons.values = [{ address: "https://new.example", name: "New", catalogs: invalid }]
EnsureSources()
old = m.sourcesTask
Harness_Equal(m.sources.Count(), 0, "new registry cannot reuse a previous source array")
Harness_Equal(old.id, "discoverSources1", "source worker gets a unique monotonic id")
CancelSources()
EnsureSources()
current = m.sourcesTask
Harness_Equal(current.id, "discoverSources2", "re-entry does not reuse the canceled id")
onSourcesLoaded(DiscoverTest_Event(old, { sources: [{ address: "old" }] }))
Harness_Equal(m.sourcesTask.id, current.id, "old event leaves replacement worker intact")
Harness_Equal(m.reaped.Count(), 1, "old event does not reap the replacement")
Harness_Equal(m.ready, 0, "old source data cannot start a catalog")
onSourcesLoaded(DiscoverTest_Event(current, invalid))
Harness_Equal(m.sourcesTask.id, current.id, "empty result notification preserves pending source task")
Harness_Equal(m.reaped.Count(), 1, "pending source worker remains observed")
onSourcesLoaded(DiscoverTest_Event(current, { sources: [{ address: "new" }] }))
Harness_Equal(m.sources[0].address, "new", "current source answer is adopted")
Harness_Equal(m.sourcesTask, invalid, "current source completion claims its slot")
Harness_Equal(m.ready, 1, "current source answer starts discovery once")
onSourcesLoaded(DiscoverTest_Event(current, { sources: [] }))
Harness_Equal(m.ready, 1, "duplicate source completion is ignored")

Harness_Suite("Discover current page, malformed records and pagination stay aligned")
DiscoverTest_Reset()
FetchDiscover()
old = m.loadTask
ResetDiscover()
FetchDiscover()
current = m.loadTask
Harness_Ok(old.id <> current.id, "replacement page worker has a different id")
onDiscoverLoaded(DiscoverTest_Event(old, { ok: true, metas: [{ id: "old", type: "movie", name: "Old" }], hasMore: false }))
Harness_Equal(m.loadTask.id, current.id, "canceled page event cannot claim current slot")
Harness_Equal(m.metas.Count(), 0, "old catalog results are not displayed")
onDiscoverLoaded(DiscoverTest_Event(current, invalid))
Harness_Equal(m.loadTask.id, current.id, "empty page notification keeps current worker")
raw = [42, { id: "", type: "movie", name: "Bad" }, { id: "first", type: "movie", name: "First", poster: 42, runtime: {} }, { id: "second", type: "movie", name: "Second" }]
for i = 0 to 6
    raw.Push({ id: "more" + i.ToStr(), type: "movie", name: "More " + i.ToStr() })
end for
onDiscoverLoaded(DiscoverTest_Event(current, { ok: true, metas: raw, hasMore: true }))
Harness_Equal(m.metas.Count(), 9, "only usable metadata records enter the visible model")
Harness_Equal(m.metas[0].poster, "", "bad artwork is normalized before native binding")
Harness_Equal(m.metas[0].runtime, invalid, "bad runtime cannot break Details formatting")
Harness_Equal(raw[2].poster, 42, "normalization does not mutate provider records")
Harness_Equal(m.grid.content.children.Count(), 2, "all logical result rows remain in content")
Harness_Equal(m.grid.numRows, 1, "portrait viewport contains one fully visible 405px row")
Harness_Equal(m.nextPageOffset, 11, "pagination counts consumed raw provider records")
m.grid.rowItemSelected = [0, 1]
onResultSelected()
Harness_Equal(m.top.pushRequest.params.meta.id, "second", "visible selection resolves the filtered second movie")
m.top.pushRequest = invalid
m.grid.rowItemSelected = [0, -1]
onResultSelected()
Harness_Equal(m.top.pushRequest, invalid, "invalid tile coordinate cannot open a different movie")
m.grid.rowItemFocused = [1, 2]
LoadMore()
append = m.loadTask
Harness_Equal(append.pageOffset, 11, "next request skips raw records rather than the filtered count")
onDiscoverLoaded(DiscoverTest_Event(append, { ok: true, metas: [42, { id: "append", type: "movie", name: "Append" }], hasMore: false }))
Harness_Equal(m.metas.Count(), 10, "append filters records without replacing earlier titles")
Harness_Equal(m.nextPageOffset, 13, "append advances the raw offset")
Harness_Equal(m.grid.jumpToRowItem[0], 1, "append preserves focused row")
Harness_Equal(m.grid.jumpToRowItem[1], 2, "append preserves focused column")
Harness_Ok(m.allLoaded, "final provider page stops pagination")
onDiscoverLoaded(DiscoverTest_Event(append, { ok: true, metas: [], hasMore: false }))
Harness_Equal(m.metas.Count(), 10, "duplicate completion cannot append or clear results")

Harness_Suite("Discover viewport and changing shape preserve the selected title")
Harness_Equal(DiscoverVisibleRows(0, 405), 0, "empty content has zero visible rows")
Harness_Equal(DiscoverVisibleRows(40, 405), 1, "total catalog size does not grow portrait viewport")
Harness_Equal(DiscoverVisibleRows(40, 270), 2, "two landscape rows fit the viewport")
Harness_Equal(DiscoverUsableMetas("invalid").Count(), 0, "nonarray metadata is harmless")
DiscoverTest_Reset()
for i = 0 to 5
    m.metas.Push({ id: "portrait" + i.ToStr(), type: "movie", name: "Portrait", posterShape: "poster" })
end for
UpdateGrid()
for i = 0 to 9
    m.metas.Push({ id: "landscape" + i.ToStr(), type: "movie", name: "Landscape", posterShape: "landscape" })
end for
UpdateGrid([1, 0])
Harness_Equal(m.chunk, 3, "landscape majority changes to three columns")
Harness_Equal(m.grid.jumpToRowItem[0], 1, "shape change maps previous title into its new row")
Harness_Equal(m.grid.jumpToRowItem[1], 2, "shape change maps previous title into its new column")
m.grid.rowItemSelected = m.grid.jumpToRowItem
onResultSelected()
Harness_Equal(m.top.pushRequest.params.meta.id, "portrait5", "shape change keeps the same title selected")
DiscoverTest_Reset()
ignored = onKeyEvent("down", true)
Harness_Ok(not m.grid.focused, "empty results do not steal filter focus")
m.top.screenActive = false
LandingChipsFocus()
Harness_Equal(m.filterBar.chipFocusCount, 0, "hidden Discover does not move focus")

Harness_Suite("Discover retry replaces pending work and refreshes page zero")
DiscoverTest_Reset()
m.sources=[{address:"https://catalog.example"}]
FetchDiscover():old=m.loadTask
Harness_Ok(onKeyEvent("play",true),"Play/Pause is an explicit retry action")
Harness_Ok(m.loadTask.id<>old.id,"retry has its own task ownership")
Harness_Equal(m.reaped.Count(),1,"retry cancels the pending old lookup")
Harness_Equal(m.loadTask.pageOffset,0,"retry starts at page zero")
onDiscoverLoaded(DiscoverTest_Event(old,{ok:true,metas:[{id:"late",type:"movie",name:"Late"}],hasMore:false}))
Harness_Equal(m.metas.Count(),0,"abandoned retry result cannot repaint discovery")
DiscoverTest_Reset():m.selectedCatalog=invalid:m.sourcesSignature="stale"
m.stores.addons.values=[{address:"https://manifest.example",catalogs:invalid}]
ignored=onKeyEvent("play",true)
Harness_Ok(m.sourcesTask<>invalid,"retry can recover a manifest-source failure")

Harness_Suite("Discover re-entry refreshes current feeds without blanking or stealing focus")
DiscoverTest_Reset():m.sourcesSignature=CatalogSignature()
FetchDiscover():task=m.loadTask
onDiscoverLoaded(DiscoverTest_Event(task,{ok:true,metas:[{id:"one",type:"movie",name:"One"},{id:"two",type:"movie",name:"Two"}],hasMore:true}))
m.grid.rowItemFocused=[0,1]
OnEnter(invalid)
Harness_Equal(m.launched.Count(),1,"fresh production OnEnter reuses its current page")
m.catalogRefreshClock.elapsed=1799999:OnEnter(invalid)
Harness_Equal(m.launched.Count(),1,"fresh page is kept until thirty minutes")
m.catalogRefreshClock.elapsed=1800000:OnEnter(invalid)
Harness_Equal(m.launched.Count(),2,"stale production OnEnter requests a fresh page zero")
current=m.loadTask
Harness_Equal(m.metas.Count(),2,"stale reload keeps existing titles navigable")
Harness_Equal(m.nextPageOffset,2,"old pagination is preserved until successful replacement")
OnEnter(invalid)
Harness_Equal(m.launched.Count(),2,"a pending refresh is not duplicated")
beforeFocus=m.filterBar.chipFocusCount
onDiscoverLoaded(DiscoverTest_Event(current,{ok:true,metas:[{id:"two",type:"movie",name:"Two"},{id:"new",type:"movie",name:"New"}],hasMore:false}))
Harness_Equal(m.metas[1].id,"new","fresh titles replace the old snapshot")
Harness_Equal(m.grid.jumpToRowItem[1],0,"selected title stays selected after reordering")
Harness_Equal(m.filterBar.chipFocusCount,beforeFocus,"automatic refresh does not move focus to filters")
Harness_Ok(m.allLoaded,"replacement page updates pagination state")
m.catalogRefreshClock.elapsed=1800000:OnEnter(invalid):current=m.loadTask
onDiscoverLoaded(DiscoverTest_Event(current,{ok:false,error:"provider unavailable"}))
Harness_Equal(m.metas.Count(),2,"failed refresh keeps previous titles")
Harness_Ok(m.status.text.InStr("previous")>=0,"failed refresh explains that old data remains")
m.catalogRefreshClock.elapsed=1800000:m.top.screenActive=false:OnEnter(invalid)
Harness_Equal(m.launched.Count(),3,"hidden production OnEnter starts no refresh underneath playback")
m.top.screenActive=true:OnEnter(invalid):current=m.loadTask
BlurFocus()
Harness_Equal(m.loadTask,invalid,"leaving for Details or Video cancels the automatic refresh")
onDiscoverLoaded(DiscoverTest_Event(current,{ok:true,metas:[{id:"late",type:"movie",name:"Late"}],hasMore:false}))
Harness_Equal(m.metas[0].id,"two","late canceled refresh does not replace the retained title")
m.top.screenActive=true:OnEnter(invalid):current=m.loadTask
m.top.screenActive=false
onDiscoverLoaded(DiscoverTest_Event(current,{ok:true,metas:[{id:"hidden",type:"movie",name:"Hidden"}],hasMore:false}))
Harness_Equal(m.metas[0].id,"two","even a hidden race cannot rebuild the grid during playback")

Harness_Suite("Provider-native live discovery retains IDs, ownership and user audio choice")
DiscoverTest_Reset()
m.selectedCatalog={address:"https://sports.example/config?token=fixture",rawType:"tv",catalogId:"original-live"}
m.liveEntry={addonAddress:m.selectedCatalog.address,metaType:"tv",catalogId:"original-live",livePlayback:true,allowUnknownLiveAudio:true}
m.metas=[{id:"native/event:opaque?"+String(340,"x"),type:"tv",name:"Provider event"}]
m.grid.rowItemSelected=[0,0]
onResultSelected()
Harness_Equal(m.top.pushRequest.screen,"streamsScreen","live item goes to source picker without metadata gate")
Harness_Equal(m.top.pushRequest.params.videoId,m.metas[0].id,"long opaque provider ID survives untouched")
Harness_Equal(m.top.pushRequest.params.addonAddress,m.selectedCatalog.address,"private configuration retained only in runtime params")
Harness_Ok(m.top.pushRequest.params.livePlayback,"explicit live context survives navigation")
Harness_Ok(m.top.pushRequest.params.allowUnknownLiveAudio,"live audio choice preserved")
Harness_Ok(not m.top.pushRequest.params.autoPlay,"viewer sees available live sources before first play")
Harness_Ok(not m.top.pushRequest.params.fourKOnly,"movie-only UHD filter cannot hide sports")
Harness_Ok(not m.top.pushRequest.params.autoNextEpisode,"live event never advances episodes")
Harness_Equal(m.top.pushRequest.params.position,0,"no movie resume forwarded to live event")
m.selectedCatalog.catalogId="other-catalog":onResultSelected()
Harness_Equal(m.top.pushRequest.screen,"detailsScreen","different catalog does not inherit live audio exception")
m.selectedCatalog.catalogId="original-live":m.selectedCatalog.address="https://other.example":onResultSelected()
Harness_Equal(m.top.pushRequest.screen,"detailsScreen","same catalog ID at another provider is isolated")
m.top.screenActive=false:m.top.pushRequest=invalid:onResultSelected()
Harness_Equal(m.top.pushRequest,invalid,"hidden stale selection cannot interrupt playback")

Harness_Finish()
if m.failed > 0
    failure = invalid
    ignored = failure.assertion
end if
