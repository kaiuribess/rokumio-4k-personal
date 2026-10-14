'
' Account ownership and writes are held by MainScene; no worker changes owners.
sub InitAccountWork()
    m.accountGeneration = 0
    m.accountWorkerSequence = 0
    m.accountWrites = []
    m.accountPersistSignature = ""
    m.accountLibraryReady = false
    m.pushingLibraryWrite = false
    m.inFlightLibraryWrite = invalid
    m.top.accountGeneration = 0
end sub

function AccountGeneration() as integer
    if m.accountGeneration = invalid then return 0
    return m.accountGeneration
end function

function NextAccountWorkerId(prefix as string) as string
    if m.accountWorkerSequence = invalid then m.accountWorkerSequence = 0
    m.accountWorkerSequence = m.accountWorkerSequence + 1
    return prefix + AccountGeneration().ToStr() + "_" + m.accountWorkerSequence.ToStr()
end function

function AccountResultCurrent(task as dynamic, event as dynamic) as boolean
    if task = invalid then return false
    generation = task.accountGeneration
    if generation = invalid then generation = 0
    if generation <> AccountGeneration() then return false
    if event <> invalid
        try
            sender = event.GetRoSGNode()
            if sender = invalid or sender.id <> task.id then return false
        catch e
            return false
        end try
    end if
    return true
end function

sub ResetAccountWork()
    m.accountGeneration = AccountGeneration() + 1
    m.top.accountGeneration = m.accountGeneration
    if m.watchStatePump <> invalid then m.watchStatePump.control = "stop"
    for each task in [m.addonSyncTask,m.librarySyncTask,m.libraryWriteTask]
        if task <> invalid then AsyncTask_Reap(task,m.top,true)
    end for
    if m.import <> invalid
        if m.import.task <> invalid then AsyncTask_Reap(m.import.task,m.top,true)
        m.import = invalid
    end if
    m.addonSyncTask = invalid
    m.librarySyncTask = invalid
    m.libraryWriteTask = invalid
    m.pushingLibraryWrite = false
    m.inFlightLibraryWrite = invalid
    m.accountWrites = []
    m.accountPersistSignature = ""
    m.accountLibraryReady = false
    m.pendingWatchState = invalid
    m.pendingWatchedChange = invalid
    m.pendingLibraryChange = invalid
    m.pendingLibrarySync = false
    m.lastPacketKey = ""
    if m.storeHost <> invalid then m.storeHost.callFunc("WatchClear")
    try
        coordinator = m.top.FindNode("sourcePrefetch")
        if coordinator <> invalid then coordinator.callFunc("PrefetchClear")
    catch e
    end try
end sub

function QueueAccountEdit(kind as string, payload as dynamic) as boolean
    if Type(payload) <> "roAssociativeArray" then return false
    generation = payload.accountGeneration
    if generation = invalid then generation = 0
    if generation <> AccountGeneration() then return false
    if GetInterface(payload.metaId,"ifString") = invalid or payload.metaId = "" then return false
    if kind <> "watchState" and kind <> "watched" and kind <> "libraryChange" then return false
    if Type(m.accountWrites) <> "roArray" then m.accountWrites = []
    for index = 0 to m.accountWrites.Count() - 1
        job = m.accountWrites[index]
        if job.kind = kind and job.metaId = payload.metaId
            m.accountWrites[index] = {kind:kind,metaId:payload.metaId,payload:payload,accountGeneration:generation,blocked:false}
            return true
        end if
    end for
    if m.accountWrites.Count() >= 127
        ReportStoreFault("Account edit queue is full. Retry saved changes in Settings.",true)
        return false
    end if
    m.accountWrites.Push({kind:kind,metaId:payload.metaId,payload:payload,accountGeneration:generation,blocked:false})
    return true
end function

function NextLibraryWrite() as dynamic
    if Type(m.accountWrites) <> "roArray" then return invalid
    for index = 0 to m.accountWrites.Count() - 1
        job = m.accountWrites[index]
        if job.blocked = true then continue for
        itemBlocked = false
        for each other in m.accountWrites
            if other.metaId = job.metaId and other.blocked = true then itemBlocked = true
        end for
        if itemBlocked or job.accountGeneration <> AccountGeneration() then continue for
        payload = job.payload
        item = invalid
        if job.kind = "watchState"
            ' Player/outbox/local registry use Roku seconds. Codec/API use ms.
            wirePacket = {}
            for each field in payload
                wirePacket[field] = payload[field]
            end for
            wirePacket.position = payload.position * 1000
            wirePacket.duration = payload.duration * 1000
            item = m.storeHost.callFunc("LibraryBuildWatchStateItem",wirePacket)
        else if job.kind = "watched"
            item = m.storeHost.callFunc("LibraryBuildWatchedStateItem",payload)
        else if job.kind = "libraryChange"
            item = m.storeHost.callFunc("LibraryBuildLibraryChangeItem",payload.metaId,payload.metaType,payload.name,payload.poster,payload.added)
        end if
        if Type(item) <> "roAssociativeArray"
            job.blocked = true
            ReportStoreFault("Account changes are not synced. Settings > Retry saved changes.",true)
            continue for
        end if
        job.item = item
        m.accountWrites.Delete(index)
        return job
    end for
    return invalid
end function

sub PumpLibraryWrites()
    if m.storeHost = invalid then return
    if m.storeHost.callFunc("AuthGetSession") <> "stremio" then return
    PersistAccountWrites()
    if m.pushingLibraryWrite = true or m.accountLibraryReady <> true then return
    job = NextLibraryWrite()
    if job = invalid then return
    m.inFlightLibraryWrite = job
    m.pushingLibraryWrite = true
    m.libraryWriteTask = AsyncTask_Launch(m.top,"LibraryPutTask","onLibraryWriteResult",{
        authKey:m.storeHost.callFunc("AuthGetAuthKey"),item:job.item,accountGeneration:AccountGeneration()
    },NextAccountWorkerId("libraryPut"))
end sub

sub onLibraryWriteResult(event = invalid as dynamic)
    task = m.libraryWriteTask
    if not AccountResultCurrent(task,event) then return
    result = task.result
    if Type(result) <> "roAssociativeArray" then return
    job = m.inFlightLibraryWrite
    m.libraryWriteTask = invalid
    m.pushingLibraryWrite = false
    AsyncTask_Reap(task,m.top,false)
    m.inFlightLibraryWrite = invalid
    if result.ok <> true and job <> invalid
        superseded = false
        for each newer in m.accountWrites
            if newer.kind = job.kind and newer.metaId = job.metaId then superseded = true
        end for
        if not superseded
            job.blocked = true
            m.accountWrites.Unshift(job)
        end if
        ReportStoreFault("Account changes are not synced. Settings > Retry saved changes.",true)
    end if
    if m.accountWrites.Count() = 0 then ReportStoreFault("Account changes are not synced. Settings > Retry saved changes.",false)
    PersistAccountWrites()
    PumpLibraryWrites()
end sub

sub RetryAccountWrites()
    if Type(m.accountWrites) <> "roArray" then return
    for each job in m.accountWrites
        job.blocked = false
    end for
    m.accountLibraryReady = false
    StartAddonSync()
    StartLibrarySync()
    ScheduleWatchStatePush()
end sub

sub onPersistenceTick()
    if m.storeHost = invalid then return
    if Type(m.accountWrites) = "roArray" and m.accountWrites.Count() > 0 then PersistAccountWrites()
    result = m.storeHost.callFunc("RetryPersistence")
    if Type(result) <> "roAssociativeArray" then return
    ReportStoreFault("Device storage could not save changes. Retrying.",result.failed = true)
end sub

sub PersistAccountWrites()
    if m.storeHost = invalid or m.storeHost.callFunc("AuthGetSession") <> "stremio" then return
    jobs = []
    if m.inFlightLibraryWrite <> invalid then jobs.Push(m.inFlightLibraryWrite)
    if Type(m.accountWrites) = "roArray" then jobs.Append(m.accountWrites)
    records = []
    for each job in jobs
        records.Push({kind:job.kind,metaId:job.metaId,payload:job.payload,blocked:job.blocked = true})
    end for
    signature = FormatJson(records)
    if signature <> m.accountPersistSignature
        if m.storeHost.callFunc("LibrarySetAccountOutbox",records) = true
            m.accountPersistSignature = signature
        else
            ReportStoreFault("Device storage could not save changes. Retrying.",true)
        end if
    end if
    for each job in jobs
        if job.blocked = true then ReportStoreFault("Account changes are not synced. Settings > Retry saved changes.",true):exit for
    end for
end sub

sub RestoreAccountWrites()
    if m.storeHost = invalid or m.storeHost.callFunc("AuthGetSession") <> "stremio" then return
    jobs = m.storeHost.callFunc("LibraryGetAccountOutbox")
    if Type(jobs) <> "roArray" then return
    for each job in jobs
        if Type(job) <> "roAssociativeArray" then continue for
        if Type(job.payload) <> "roAssociativeArray" then continue for
        job.payload.accountGeneration = AccountGeneration()
        if QueueAccountEdit(job.kind,job.payload)
            for each queued in m.accountWrites
                if queued.kind = job.kind and queued.metaId = job.metaId then queued.blocked = true
            end for
        end if
    end for
end sub
