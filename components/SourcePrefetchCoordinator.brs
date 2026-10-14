' One currently displayed title/episode; successful provider results survive
' the Details -> Streams transition for at most 60 seconds. All state is local
' to this Scene node and dies with the app. No registry or media traffic.
sub init()
    m.sequence = 0
    m.context = invalid
    m.entries = []
    m.tasks = []
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
    token = m.sequence.ToStr()
    count = context.providers.Count()
    if count > 4 then count = 4
    for i = 0 to count - 1
        m.entries.Push({status:"pending", result:invalid})
        m.tasks.Push(invalid)
    end for
    m.expiry.duration = 60
    m.expiry.control = "start"
    m.deadline = m.clock.TotalMilliseconds() + 60000
    for i = 0 to count - 1
        provider = context.providers[i]
        m.tasks[i] = AsyncTask_Launch(m.top, "SourcePrefetchTask", "onPrefetchLoaded", {
            metaType:context.metaType, videoId:context.videoId, audioMode:context.audioMode,
            addonAddress:provider.address, providerId:provider.id, providerName:provider.name,
            providerIndex:i, loadToken:token
        }, "sourcePrefetch" + token + "_" + i.ToStr())
    end for
    m.top.revision = m.top.revision + 1
    return Snapshot(context.key)
end function

function Snapshot(key as string) as dynamic
    if m.context = invalid or m.context.key <> key then return invalid
    if m.clock.TotalMilliseconds() >= m.deadline
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
    m.deadline = 0
    if m.expiry <> invalid then m.expiry.control = "stop"
    if m.tasks <> invalid
        for each task in m.tasks
            if task <> invalid then AsyncTask_Reap(task, m.top, true)
        end for
    end if
    m.tasks = []
    m.top.revision = m.top.revision + 1
end sub

sub onPrefetchExpired()
    if m.context = invalid then return
    remaining = m.deadline - m.clock.TotalMilliseconds()
    if remaining > 0
        ' A queued fire from the previous context must not expire the new one.
        m.expiry.duration = remaining / 1000.0
        m.expiry.control = "start"
        return
    end if
    PrefetchClear()
end sub

sub onPrefetchLoaded(event as object)
    task = event.GetRoSGNode()
    if task = invalid or m.context = invalid then return
    if task.loadToken <> m.sequence.ToStr() then return
    if m.clock.TotalMilliseconds() >= m.deadline
        PrefetchClear()
        return
    end if
    index = task.providerIndex
    if index < 0 or index >= m.tasks.Count() then return
    if m.tasks[index] = invalid or task.id <> m.tasks[index].id then return
    result = task.result
    if Type(result) <> "roAssociativeArray" then return
    m.tasks[index] = invalid
    AsyncTask_Reap(task, m.top, false)
    ' Failures are sent as a refresh signal, never retained as a usable result.
    if result.ok = true and Type(result.streams) = "roArray" and Type(result.readyStreams) = "roArray"
        m.entries[index] = {status:"ready", result:result}
    else
        m.entries[index] = {status:"failed", result:invalid}
    end if
    m.top.revision = m.top.revision + 1
end sub
