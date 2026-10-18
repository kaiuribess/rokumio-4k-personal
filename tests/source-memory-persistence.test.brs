function MemoryTestClock() as object
    return {elapsed:0,Mark:sub()
        m.elapsed=0
    end sub,TotalMilliseconds:function() as integer
        return m.elapsed
    end function}
end function
function MemoryTestNow() as double
    return 1700000000#
end function
function MemoryFits(section as string,key as string,value as string) as boolean
    return true
end function
function MemoryHashA(value as string) as string
    return String(64,"a")
end function
function NextPlayerWorkerId(prefix as string) as string
    m.serial=m.serial+1
    return prefix+m.serial.ToStr()
end function
function AsyncTask_Launch(parent as object,kind as string,callback as string,fields as object,id as string) as dynamic
    if m.failLaunch then throw "injected task failure"
    fields.id=id:fields.kind=kind:fields.result=invalid
    m.launched.Push(fields)
    return fields
end function
sub AsyncTask_Reap(task as object,parent as object,stopped as boolean)
    m.reaped=m.reaped+1
end sub
function MemoryEvent(task as object) as object
    return {task:task,GetRoSGNode:function() as object
        return m.task
    end function,GetData:function() as dynamic
        return m.task.result
    end function}
end function
sub MemorySetup()
    m.serial=0:m.launched=[]:m.reaped=0:m.failLaunch=false
    m.nativeRegistry=MockRegistry()
    m.top={nodes:{sourceProofTick:{control:"stop"},sourceMemoryPump:{control:"stop"}},FindNode:function(id as string) as dynamic
        return m.nodes[id]
    end function}
    for each name in m.top.nodes
        m.top.nodes[name].ObserveField=sub(field as string,callback as string)
        end sub
    end for
    InitSourceMemory()
end sub
sub MemoryQueue(key as string,outcome as string)
    m.sourceAttemptKey=key
    QueueSourceOutcome(outcome)
end sub
sub MemoryPump()
    if Type(m.sourceMemoryRetryGuard)="roAssociativeArray" then m.sourceMemoryRetryGuard.clock.elapsed=m.sourceMemoryRetryGuard.delayMs
    onSourceMemoryPump()
end sub
sub MemoryComplete(task as object)
    screen=m.top:m.top=task
    MemoryRunWorker()
    m.top=screen
    onSourceMemorySaved(MemoryEvent(task))
end sub

Harness_Suite("Failed production memory writes retain newest file outcomes and retry durably")
MemorySetup():keyA=String(64,"a"):keyB=String(64,"b")
data=SourceMemory_Record(SourceMemory_Empty(),keyA,"working",MemoryTestNow()-10)
Harness_Ok(SourceMemory_Save(RegistryIO(m.nativeRegistry,"playbackMemory",MemoryFits),data,MemoryTestNow()),"previous working record is initially durable")
MemoryQueue(keyA,"network"):MemoryPump():held=m.sourceMemoryTask
Harness_Equal(m.launched.Count(),1,"one actual source-memory worker launched")
Harness_Equal(m.sourceMemoryInFlight.Count(),1,"active batch remains owned until acknowledgement")
MemoryQueue(keyB,"working"):MemoryQueue(keyA,"incompatible")
onSourceMemoryPump()
Harness_Equal(m.launched.Count(),1,"new outcomes never overlap the active registry writer")
m.nativeRegistry.failWrites=true:MemoryComplete(held)
Harness_Equal(m.sourceMemoryPending.Count(),2,"failed batch returns to bounded pending state")
Harness_Equal(m.sourceMemoryPending[1].outcome,"incompatible","newer same-key outcome wins over an older failed batch")
Harness_Equal(SourceMemory_Outcome(SourceMemory_Load(m.nativeRegistry,MemoryTestNow()),keyA),"working","failed Write cannot claim a durable replacement")
Harness_Ok(not m.memorySaved,"failed current outcomes are not reported saved")
Harness_Equal(m.sourceMemoryRetryGuard.delayMs,1000,"first retry has a bounded one-second delay")
onSourceMemoryPump()
Harness_Equal(m.launched.Count(),1,"queued stale pump fire cannot bypass retry delay")
m.nativeRegistry.failWrites=false:m.nativeRegistry.failFlushes=true
MemoryPump():second=m.sourceMemoryTask:MemoryComplete(second)
Harness_Equal(m.sourceMemoryPending.Count(),2,"failed Flush preserves distinct pending outcomes")
Harness_Equal(SourceMemory_Outcome(SourceMemory_Load(m.nativeRegistry,MemoryTestNow()),keyA),"working","actual RegistryIO restores the previous acknowledged record on failed Flush")
Harness_Equal(m.sourceMemoryRetryGuard.delayMs,2000,"second retry backs off to two seconds")
m.nativeRegistry.failFlushes=false:MemoryPump():third=m.sourceMemoryTask:MemoryComplete(third)
Harness_Ok(m.memorySaved,"successful worker acknowledgement marks the drained queue saved")
Harness_Equal(m.sourceMemoryPending.Count(),0,"only acknowledged outcomes leave the queue")
Harness_Equal(m.sourceMemoryInFlight.Count(),0,"completed batch releases its retained copy")
durable=SourceMemory_Load(m.nativeRegistry,MemoryTestNow())
Harness_Equal(SourceMemory_Outcome(durable,keyA),"incompatible","latest failed-file outcome reaches real registry")
Harness_Equal(SourceMemory_Outcome(durable,keyB),"working","different title outcome is also durable")
stream={url:"https://example.invalid/file.mkv",behaviorHints:{filename:"fixture.mkv"},sourceMemoryProvider:"fixture|example.invalid"}
Harness_Equal(SourceMemory_Order([stream],durable,"tt1","surround",MemoryTestNow(),MemoryHashA,true).Count(),0,"real automatic memory ordering excludes the newly acknowledged incompatible file")
before=m.reaped:onSourceMemorySaved(MemoryEvent(held))
Harness_Equal(m.reaped,before,"duplicate older result cannot requeue a completed batch")

Harness_Suite("Three timed retries stop safely while retaining failed outcomes")
MemorySetup():MemoryQueue(keyA,"network")
m.nativeRegistry.failFlushes=true
for attempt=1 to 4
    MemoryPump():MemoryComplete(m.sourceMemoryTask)
end for
Harness_Equal(m.launched.Count(),4,"initial attempt plus three retries is a hard bound")
Harness_Ok(m.sourceMemoryRetryBlocked,"persistent failure closes automatic retry gate")
Harness_Equal(m.sourceMemoryPending.Count(),1,"exhausted retries retain the unsaved file outcome")
Harness_Equal(m.sourceMemoryPump.control,"stop","exhausted retry budget stops the pump timer")
for extra=1 to 10
    onSourceMemoryPump()
end for
Harness_Equal(m.launched.Count(),4,"late timer events cannot create an endless write loop")
MemoryQueue(keyB,"working")
Harness_Ok(not m.sourceMemoryRetryBlocked,"a real new outcome can restart one bounded retry cycle")
Harness_Equal(m.sourceMemoryPending.Count(),2,"new trigger preserves previous unsaved outcome")
m.nativeRegistry.failFlushes=false:MemoryPump():MemoryComplete(m.sourceMemoryTask)
Harness_Equal(SourceMemory_Outcome(SourceMemory_Load(m.nativeRegistry,MemoryTestNow()),keyA),"network","later successful cycle preserves the earlier failed-source cooldown")
Harness_Ok(m.memorySaved,"new cycle acknowledges both retained outcomes")

Harness_Suite("Held workers, empty notifications and newest pending values remain separate")
MemorySetup():MemoryQueue(keyA,"working"):MemoryPump():held=m.sourceMemoryTask
onSourceMemorySaved(MemoryEvent(held))
Harness_Equal(m.sourceMemoryTask.id,held.id,"an initial empty result cannot consume a running worker")
MemoryQueue(keyA,"network")
MemoryComplete(held)
Harness_Ok(not m.memorySaved,"older success cannot mark newer pending failure saved")
Harness_Equal(m.sourceMemoryPending[0].outcome,"network","newer failure survives earlier success acknowledgement")
MemoryPump():nextTask=m.sourceMemoryTask
onSourceMemorySaved(MemoryEvent(held))
Harness_Equal(m.sourceMemoryTask.id,nextTask.id,"stale acknowledgement cannot consume the replacement worker")
MemoryComplete(nextTask)
Harness_Equal(SourceMemory_Outcome(SourceMemory_Load(m.nativeRegistry,MemoryTestNow()),keyA),"network","newest outcome replaces earlier success in durable memory")

Harness_Suite("Pending and failed-batch merge remain bounded and task launch failures are recoverable")
MemorySetup():MemoryQueue(keyA,"network"):MemoryPump():held=m.sourceMemoryTask
for index=1 to 100
    MemoryQueue(Right(String(64,"0")+index.ToStr(),64),"working")
end for
Harness_Equal(m.sourceMemoryPending.Count(),64,"flood of new distinct outcomes retains at most64 pending keys")
m.nativeRegistry.failWrites=true:MemoryComplete(held)
Harness_Equal(m.sourceMemoryPending.Count(),64,"restoring failed batch cannot grow the bounded queue")
Harness_Equal(m.sourceMemoryPending[63].key,Right(String(64,"0")+"100",64),"newest retained key survives the failed-batch merge")
Harness_Equal(m.sourceMemoryPending[0].Keys().Count(),2,"pending records retain only opaque key and fixed outcome")
MemorySetup():MemoryQueue(keyA,"network"):m.failLaunch=true:MemoryPump()
Harness_Equal(m.sourceMemoryPending.Count(),1,"failed task creation returns its batch to pending")
Harness_Equal(m.sourceMemoryTask,invalid,"failed task creation does not occupy the serialized writer")
Harness_Equal(m.sourceMemoryRetryCount,1,"task failure consumes the same bounded retry budget")
m.failLaunch=false:MemoryPump():MemoryComplete(m.sourceMemoryTask)
Harness_Ok(m.memorySaved,"later task creation can durably complete the retained batch")
Harness_Finish()
