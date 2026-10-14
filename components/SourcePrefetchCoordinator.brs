' A shared two-slot source-list scheduler. Leaving a title discards queued work,
' but already-running transfers retain their slot until they publish a result.
' STOP is deliberately not treated as cancellation of an HTTP transfer.
sub init()
    m.sequence = 0
    m.workerSequence = 0
    m.context = invalid
    m.entries = []
    m.tasks = []
    m.activeTasks = []
    m.fullLoad = false
    m.suspended = false
    m.clock = CreateObject("roTimespan")
    m.clock.Mark()
    m.deadline = 0
    m.expiry = m.top.FindNode("prefetchExpiry")
    m.expiry.ObserveField("fire", "onPrefetchExpired")
end sub

function Prepare(context as object) as dynamic
    if Type(context) <> "roAssociativeArray" or Type(context.providers) <> "roArray" or context.key = "" then return invalid
    current = Snapshot(context.key)
    if current <> invalid then return current
    PrefetchClear()
    m.context = context
    m.fullLoad = false
    m.suspended = false
    count = context.providers.Count()
    if count > 4 then count = 4
    for i = 0 to count - 1
        m.entries.Push({status:"queued", result:invalid, warm:true})
        m.tasks.Push(invalid)
    end for
    m.expiry.duration = 60
    m.expiry.control = "start"
    m.deadline = m.clock.TotalMilliseconds() + 60000
    PrefetchPump()
    m.top.revision = m.top.revision + 1
    return Snapshot(context.key)
end function

' Explicit Play adopts warm requests and queues ALL matching providers. A failed
' warm lookup gets one fresh ordinary lookup; ordinary failures remain completed.
function Adopt(context as object) as dynamic
    if Type(context) <> "roAssociativeArray" or Type(context.providers) <> "roArray" or context.key = "" then return invalid
    current = Snapshot(context.key)
    if current = invalid
        PrefetchClear()
        m.context = context
    end if
    m.fullLoad = true
    m.suspended = false
    m.deadline = 0
    m.expiry.control = "stop"
    for i = 0 to context.providers.Count() - 1
        if i >= m.entries.Count()
            m.entries.Push({status:"queued",result:invalid,warm:false})
            m.tasks.Push(invalid)
        else if m.entries[i].status = "failed" and m.entries[i].warm = true
            m.entries[i] = {status:"queued",result:invalid,warm:false}
        else if m.entries[i].status = "queued"
            m.entries[i].warm = false
        end if
    end for
    PrefetchPump()
    return Snapshot(context.key)
end function

sub Suspend(key as string)
    if m.context <> invalid and m.context.key = key then m.suspended = true
end sub

function Resume(key as string) as dynamic
    if m.context = invalid or m.context.key <> key then return invalid
    m.suspended = false
    PrefetchPump()
    return Snapshot(key)
end function

function Snapshot(key as string) as dynamic
    if m.context = invalid or m.context.key <> key then return invalid
    if m.fullLoad <> true and m.clock.TotalMilliseconds() >= m.deadline
        PrefetchClear()
        return invalid
    end if
    return {token:m.sequence.ToStr(), entries:m.entries}
end function

sub Cancel(key as string)
    if m.context <> invalid and m.context.key = key then PrefetchClear()
end sub

sub PrefetchClear()
    m.sequence = m.sequence + 1
    m.context = invalid
    m.entries = []
    m.tasks = []
    m.fullLoad = false
    m.suspended = false
    m.deadline = 0
    if m.expiry <> invalid then m.expiry.control = "stop"
    ' Retain active task ownership and observers. Their late results free the
    ' shared slot but cannot populate a later title because tokens differ.
    if Type(m.activeTasks) <> "roArray" then m.activeTasks = []
    m.top.revision = m.top.revision + 1
end sub

sub PrefetchPump()
    if m.context = invalid or m.suspended = true then return
    if Type(m.activeTasks) <> "roArray" then m.activeTasks = []
    for i = 0 to m.entries.Count() - 1
        if m.activeTasks.Count() >= 2 then exit for
        if m.entries[i].status <> "queued" then continue for
        provider = m.context.providers[i]
        kind = "StreamsLoaderTask"
        if m.entries[i].warm = true then kind = "SourcePrefetchTask"
        token = m.sequence.ToStr()
        if m.workerSequence = invalid then m.workerSequence = 0
        m.workerSequence = m.workerSequence + 1
        task = AsyncTask_Launch(m.top,kind,"onPrefetchLoaded",{
            metaType:m.context.metaType,videoId:m.context.videoId,audioMode:m.context.audioMode,
            addonAddress:provider.address,providerId:provider.id,providerName:provider.name,
            providerIndex:i,loadToken:token
        },"sourceLookup"+token+"_"+i.ToStr()+"_"+m.workerSequence.ToStr())
        m.tasks[i] = task
        m.activeTasks.Push(task)
        m.entries[i].status = "pending"
    end for
end sub

sub onPrefetchExpired()
    if m.context = invalid or m.fullLoad = true then return
    remaining = m.deadline - m.clock.TotalMilliseconds()
    if remaining > 0
        m.expiry.duration = remaining / 1000.0
        m.expiry.control = "start"
        return
    end if
    PrefetchClear()
end sub

sub onPrefetchLoaded(event as object)
    task = event.GetRoSGNode()
    if task = invalid or Type(m.activeTasks) <> "roArray" then return
    activeIndex = -1
    for i = 0 to m.activeTasks.Count() - 1
        if m.activeTasks[i].id = task.id then activeIndex = i
    end for
    if activeIndex < 0 then return
    result = task.result
    if Type(result) <> "roAssociativeArray" then return
    m.activeTasks.Delete(activeIndex)
    AsyncTask_Reap(task,m.top,false)
    if m.context <> invalid and task.loadToken = m.sequence.ToStr()
        index = task.providerIndex
        if index >= 0 and index < m.entries.Count() and m.tasks[index] <> invalid
            if m.tasks[index].id <> task.id then return
            warm = m.entries[index].warm = true
            m.tasks[index] = invalid
            if Type(result.streams) = "roArray" and Type(result.readyStreams) = "roArray"
                m.entries[index] = {status:"ready",result:result,warm:warm}
            else if warm and m.fullLoad = true
                m.entries[index] = {status:"queued",result:invalid,warm:false}
            else
                m.entries[index] = {status:"failed",result:{streams:[],readyStreams:[],error:"Source lookup failed"},warm:warm}
            end if
        end if
    end if
    PrefetchPump()
    m.top.revision = m.top.revision + 1
end sub
