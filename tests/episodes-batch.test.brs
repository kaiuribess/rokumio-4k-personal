function BatchNode() as object
    return {children:[],CreateChild:function(kind)
        child=BatchNode():m.children.Push(child):return child
    end function,GetChild:function(index)
        return m.children[index]
    end function,SetFocus:sub(focused)
    end sub}
end function
function BatchObject(kind as string, nodeType as string) as object
    return BatchNode()
end function
function BatchStore(method as string, a=invalid as dynamic, b=invalid as dynamic, c=invalid as dynamic, d=invalid as dynamic, e=invalid as dynamic) as dynamic
    if method="EpisodesPrepare" then return m.prepared
    if method="TimeNowIso" then return "2026-10-14T00:00:00Z"
    if method="LibraryEpisodeMark" then m.marks=m.marks+1:return {aired:true,watched:false}
    if method="LibraryMarkAllIfDone" then m.completed=m.completed+1
    return invalid
end function
function AccountEpoch_Read(node as object) as integer
    return node.epoch
end function
function SeasonLabel(season as integer) as string
    return season.ToStr()
end function
function EpisodeLabel(season as integer, ep as object) as string
    return ep.episode.ToStr()
end function
function EpisodesVisibleRows(count as integer) as integer
    return 2
end function
function ResumePosition() as object
    return [0,0]
end function
sub UpdateHeader(position as object)
end sub
sub SetEpisodeHelp(value as string)
end sub
sub BatchReset(count as integer)
    m.top={screenActive:true,epoch:4}:m.accountGeneration=4
    m.buildClock={Mark:sub()
    end sub,TotalMilliseconds:function()
        return 0
    end function}
    m.buildTimer={control:"stop"}:m.buildPending=false
    m.epList=BatchNode():m.epDesc={}:m.epHeaderLine={}
    m.meta={id:"show"}:m.seriesMeta=m.meta
    episodes=[]:ids=[]
    for i=1 to count
        episodes.Push({id:"ep-"+i.ToStr(),season:1,episode:i}):ids.Push("ep-"+i.ToStr())
    end for
    boundary={callFunc:BatchStore,prepared:{seasons:[1],seasonEpisodes:[episodes],orderedVideoIds:ids},marks:0,completed:0}
    m.stores={episodes:boundary,library:boundary,time:boundary}
end sub
Harness_Suite("Large episode grids yield, cancel and retain all cards")
BatchReset(880)
BuildList({})
Harness_Ok(m.buildPending,"building is deferred before the first card")
Harness_Equal(m.buildContent.children.Count(),0,"entry does not create hundreds of nodes synchronously")
onEpisodeBuildTick()
Harness_Equal(m.stores.library.marks,24,"one callback has a hard 24-card ceiling")
Harness_Ok(m.buildPending,"large list yields for remote input")
ticks=1
while m.buildPending and ticks<100
    onEpisodeBuildTick():ticks=ticks+1
end while
Harness_Ok(not m.buildPending,"all batches finish")
Harness_Equal(m.epList.content.children[0].children.Count(),880,"later episodes are not truncated")
Harness_Equal(m.epList.content.children[0].children[879].title,"880","last episode remains selectable")
Harness_Equal(m.stores.library.completed,1,"series completion is evaluated once after a complete build")
RefreshWatchedMarks()
onEpisodeBuildTick()
Harness_Equal(m.stores.library.marks,904,"badge refresh also yields after 24 cards")
CancelEpisodeBuild()
onEpisodeBuildTick()
Harness_Equal(m.stores.library.marks,904,"canceled callback cannot continue updating hidden content")
Harness_Equal(m.buildContent,invalid,"cancel releases partially built nodes")
BatchReset(511):BuildList({}):m.top.epoch=5:onEpisodeBuildTick()
Harness_Ok(not m.buildPending,"account switch cancels stale batch")
Harness_Equal(m.stores.library.completed,0,"old account cannot publish series completion")
BatchReset(511):BuildList({}):m.top.screenActive=false:onEpisodeBuildTick()
Harness_Ok(not m.buildPending,"hidden screen cannot build or steal focus")
Harness_Finish()
if m.failed>0 then fail=invalid:ignored=fail.assertion
