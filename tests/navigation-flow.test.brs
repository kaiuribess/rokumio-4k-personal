function NavigationObject(kind as string, nodeType as string) as object
    return {}
end function
function AccountEpoch_Read(node as object) as integer
    return 1
end function
sub SourcePrefetch_Cancel(node as object, context as dynamic)
end sub
sub ScheduleEpisodePrefetch()
end sub
sub CancelEpisodeBuild()
end sub
sub RefreshWatchedMarks()
end sub
sub SetEpisodeHelp(text as string)
    m.help=text
end sub
sub BuildList(meta as object)
    m.built.Push(meta)
end sub
function AsyncTask_Launch(parent as object, kind as string, callback as string, fields as object, id as string) as object
    m.launched.Push(fields)
    return {id:id,metaId:fields.metaId}
end function
sub AsyncTask_Reap(task as object, parent as object, doStop as boolean)
    m.reaped.Push(task.id)
end sub
sub NavigationReset()
    m.top={}
    m.launched=[]:m.built=[]:m.reaped=[]
    m.epName={}:m.bgPoster={}:m.epList={}:m.epHeaderLine={}:m.epDesc={}
    m.prefetchTimer=invalid:m.prefetchContext=invalid
    m.seasons=[]:m.episodeSnapshot=invalid:m.episodeSnapshotSequence=0
    m.seriesTaskSequence=0:m.loadTask=invalid:m.cachedSeriesMeta=invalid
end sub
Harness_Suite("Complete series metadata survives Details to Episodes")
NavigationReset()
videos=[]
for i=1 to 511
    videos.Push({id:"provider:"+i.ToStr(),season:1,episode:i})
end for
m.meta={id:"tt0182576",type:"series",name:"Family Guy",videos:videos}
m.metaRefreshed=true:m.addonAddress="https://catalog.example":m.resume=invalid
OpenEpisodes()
packet=m.top.pushRequest.params
Harness_Equal(packet.meta.videos.Count(),511,"full fetched episode list crosses the real action boundary")
Harness_Ok(packet.episodeMetaComplete,"only a successful Details refresh authorizes reuse")
OnEnter(packet)
Harness_Equal(m.built.Count(),1,"complete episodes render immediately")
Harness_Equal(m.built[0].videos[510].id,"provider:511","later opaque episode ids survive")
Harness_Equal(m.launched.Count(),0,"opening known episodes does not make a second network request")
Harness_Equal(m.seriesMeta.id,"tt0182576","accepted cached series is retained for watched marks")
OnEnter({meta:{id:"other-show",type:"series",name:"Other"},addonAddress:"https://other.example"})
Harness_Equal(m.launched.Count(),1,"switching to a skinny new show requests its metadata")
Harness_Equal(m.launched[0].metaId,"other-show","new title cannot inherit old episodes")
Harness_Equal(m.cachedSeriesMeta,invalid,"old cached metadata ownership is cleared")
OnExit()
Harness_Equal(m.loadTask,invalid,"Back disowns pending episode load")
Harness_Equal(m.reaped.Count(),1,"Back reaps the pending episode task")
onSeriesLoaded(invalid)
Harness_Equal(m.built.Count(),1,"late completion after Back cannot rebuild a hidden list")
NavigationReset()
m.meta={id:"preview",type:"series",name:"Preview",videos:[{id:"preview-only",season:1,episode:1}]}
m.metaRefreshed=false:m.addonAddress="https://catalog.example":m.resume=invalid
OpenEpisodes()
packet=m.top.pushRequest.params
Harness_Ok(not packet.episodeMetaComplete,"unvalidated catalog preview is not treated as complete")
OnEnter(packet)
Harness_Equal(m.launched.Count(),1,"partial catalog metadata still gets a full series request")
NavigationReset()
OnEnter({meta:{id:"empty",type:"series",name:"Empty",videos:[]},episodeMetaComplete:true,addonAddress:"https://catalog.example"})
Harness_Equal(m.launched.Count(),1,"an empty claimed snapshot cannot strand the episode browser")
Harness_Suite("A finished episode grid belongs to its Details snapshot")
NavigationReset()
m.meta={id:"series",type:"series",name:"Series",videos:[{id:"ep1",season:1,episode:1}]}
m.metaRefreshed=true:m.episodeSnapshotSequence=17:m.addonAddress="https://catalog.example":m.resume=invalid
OpenEpisodes():packet=m.top.pushRequest.params
OnEnter(packet)
m.seasons=[1]:m.epList.content={}
m.epList.SetFocus=sub(focused)
end sub
OnEnter(packet)
Harness_Equal(m.built.Count(),1,"reopening the same complete snapshot reuses its native grid")
Harness_Equal(m.launched.Count(),0,"reopening does not repeat the provider fetch")
packet.episodeSnapshot=18
OnEnter(packet)
Harness_Equal(m.built.Count(),2,"a new Details metadata snapshot rebuilds the grid")
packet.addonAddress="https://other.example"
OnEnter(packet)
Harness_Equal(m.built.Count(),3,"same title and snapshot cannot reuse a different provider's grid")

Harness_Finish()
if m.failed>0 then fail=invalid:ignored=fail.assertion
