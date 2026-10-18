' Read-only, source-correlated native delivery facts. Roku streamInfo reports
' the network estimate at stream selection, not a continuous throughput test.
' The native URL is compared privately and never copied into status or logs.
' See https://developer.roku.com/dev/docs/video (streamInfo).
sub InitDeliveryInfo()
    ResetDeliveryInfo()
    if m.video = invalid then return
    if not m.video.HasField("crimsonDeliveryGeneration")
        if not m.video.AddField("crimsonDeliveryGeneration","integer",false) then return
    end if
    m.video.crimsonDeliveryGeneration = m.deliveryGeneration
    ' ObserveField context is captured when the event occurs, so a queued
    ' notification cannot cross attempts even when both use the same URL.
    ' https://developer.roku.com/dev/docs/ifsgnodefield (infoFields, OS 9.3+).
    if m.video.HasField("streamInfo") then m.video.ObserveField("streamInfo","onDeliveryStreamInfoChanged",["crimsonDeliveryGeneration"])
    context = ["crimsonDeliveryGeneration"]
    for each field in ["state","position","positionInfo","bufferingStatus"]
        if m.video.HasField(field) then context.Push(field)
    end for
    for each field in ["state","bufferingStatus"]
        if m.video.HasField(field) then m.video.ObserveField(field,"onDeliveryPlaybackEvent",context)
    end for
    if m.video.HasField("duration") then m.video.ObserveField("duration","onDeliveryDurationChanged",["crimsonDeliveryGeneration"])
end sub

sub ResetDeliveryInfo()
    m.deliveryExpectedUrl = ""
    m.deliveryInfo = invalid
    m.deliveryDuration = invalid
    m.deliveryTrace = []
    m.deliveryTraceDropped = 0
    m.deliveryTraceClock = invalid
    try
        m.deliveryTraceClock = CreateObject("roTimespan")
        if m.deliveryTraceClock <> invalid then m.deliveryTraceClock.Mark()
    catch e
        ' Missing receipt-clock support leaves timestamps unknown.
    end try
    if m.deliveryGeneration = invalid then m.deliveryGeneration = 0
    if m.deliveryGeneration >= 2147483646 then m.deliveryGeneration = 0
    m.deliveryGeneration = m.deliveryGeneration + 1
    if m.video <> invalid
        if m.video.HasField("crimsonDeliveryGeneration") then m.video.crimsonDeliveryGeneration = m.deliveryGeneration
    end if
end sub

sub BeginDeliveryInfo(url as string)
    ResetDeliveryInfo()
    ' Retain only the existing in-memory playback URL; never persist or expose
    ' it. Exact comparison deliberately leaves redirected/unmatched reports
    ' unavailable rather than attributing a previous source's measurement.
    if url <> "" then m.deliveryExpectedUrl = url
end sub

function DeliveryInfo_Active() as boolean
    if m.video = invalid or m.playbackActive <> true or m.retryPending = true or m.playArmed = true then return false
    if GetInterface(m.deliveryExpectedUrl,"ifString") = invalid or m.deliveryExpectedUrl = "" then return false
    if not m.video.HasField("state") or not m.video.HasField("content") then return false
    state = m.video.state
    if state <> "playing" and state <> "buffering" and state <> "paused" then return false
    content = m.video.content
    if content = invalid then return false
    if GetInterface(content.url,"ifString") = invalid then return false
    return content.url = m.deliveryExpectedUrl
end function

' The reused Video node may retain the last file's duration. Only a fresh
' duration notification from this attempt can supply size/duration facts.
' An unchanged duration with no new event intentionally remains unknown.
sub onDeliveryDurationChanged(event as object)
    if not DeliveryInfo_Active() then return
    source = event.GetRoSGNode()
    if source = invalid then return
    if not source.IsSameNode(m.video) then return
    if LCase(PlaybackInfo_Text(event.GetField())) <> "duration" then return
    context = event.GetInfo()
    if Type(context) <> "roAssociativeArray" then return
    generation = DeliveryInfo_Integer(context.crimsonDeliveryGeneration,2147483647)
    if generation = invalid or generation <> m.deliveryGeneration then return
    m.deliveryDuration = invalid
    duration = DeliveryInfo_Number(event.GetData(),604800)
    if duration <> invalid
        if duration >= 1 then m.deliveryDuration = duration
    end if
end sub

function DeliveryInfo_Duration() as dynamic
    if not DeliveryInfo_Active() then return invalid
    return m.deliveryDuration
end function

' This trace measures when callbacks are RECEIVED, not when native events
' happened. Event snapshots and current values intentionally stay separate:
' queued native transitions can otherwise disappear behind newer fields.
' This diagnostic observer never changes playback or recovery decisions.
sub onDeliveryPlaybackEvent(event as object)
    if not DeliveryInfo_Active() then return
    source = event.GetRoSGNode()
    if source = invalid or not source.IsSameNode(m.video) then return
    field = LCase(PlaybackInfo_Text(event.GetField()))
    if field <> "state" and field <> "bufferingstatus" then return
    context = event.GetInfo()
    if Type(context) <> "roAssociativeArray" then return
    generation = DeliveryInfo_Integer(context.crimsonDeliveryGeneration,2147483647)
    if generation = invalid or generation <> m.deliveryGeneration then return
    receipt = invalid
    if m.deliveryTraceClock <> invalid
        try
            receipt = DeliveryInfo_Number(m.deliveryTraceClock.TotalMilliseconds(),2147483647)
        catch e
        end try
    end if
    eventState = context.state
    eventStatus = context.bufferingStatus
    if field = "state" then eventState = event.GetData()
    if field = "bufferingstatus" then eventStatus = event.GetData()
    currentStatus = invalid
    if m.video.HasField("bufferingStatus") then currentStatus = m.video.bufferingStatus
    eventSamples = context.positionInfo
    if Type(eventSamples) <> "roAssociativeArray" then eventSamples = {}
    currentSamples = {}
    if m.video.HasField("positionInfo")
        nativeSamples = m.video.positionInfo
        if Type(nativeSamples) = "roAssociativeArray" then currentSamples = nativeSamples
    end if
    currentPosition = invalid
    if m.video.HasField("position") then currentPosition = m.video.position
    eventUnderrun = invalid:eventPercentage = invalid
    if Type(eventStatus) = "roAssociativeArray"
        eventUnderrun = DeliveryInfo_Boolean(eventStatus.isUnderrun)
        eventPercentage = DeliveryInfo_Number(eventStatus.percentage,100)
    end if
    currentUnderrun = invalid:currentPercentage = invalid
    if Type(currentStatus) = "roAssociativeArray"
        currentUnderrun = DeliveryInfo_Boolean(currentStatus.isUnderrun)
        currentPercentage = DeliveryInfo_Number(currentStatus.percentage,100)
    end if
    attempt = DeliveryInfo_Integer(m.sourceIndex,191)
    if attempt <> invalid then attempt = attempt + 1
    sample = {
        receiptMilliseconds:receipt,field:field,generation:m.deliveryGeneration,attempt:attempt
        eventState:DeliveryInfo_State(eventState),currentState:DeliveryInfo_State(m.video.state)
        eventStatusPresent:Type(eventStatus) = "roAssociativeArray",currentStatusPresent:Type(currentStatus) = "roAssociativeArray"
        eventIsUnderrun:eventUnderrun,currentIsUnderrun:currentUnderrun,eventPercentage:eventPercentage,currentPercentage:currentPercentage
        eventPosition:DeliveryInfo_Number(context.position,2147483647),currentPosition:DeliveryInfo_Number(currentPosition,2147483647)
        eventAudioPosition:DeliveryInfo_Number(eventSamples.audio,2147483647),eventVideoPosition:DeliveryInfo_Number(eventSamples.video,2147483647)
        currentAudioPosition:DeliveryInfo_Number(currentSamples.audio,2147483647),currentVideoPosition:DeliveryInfo_Number(currentSamples.video,2147483647)
        eventClipId:DeliveryInfo_Integer(eventSamples.clip_id,2147483647),eventEpoch:DeliveryInfo_Integer(eventSamples.epoch,1)
    }
    if Type(m.deliveryTrace) <> "roArray" then m.deliveryTrace = []
    if m.deliveryTrace.Count() >= 64
        m.deliveryTrace.Shift()
        if m.deliveryTraceDropped < 2147483647 then m.deliveryTraceDropped = m.deliveryTraceDropped + 1
    end if
    m.deliveryTrace.Push(sample)
end sub

function DeliveryInfo_Number(value as dynamic, maximum as dynamic) as dynamic
    kind = Type(value)
    ' Roku OS 15.3+ returns LongInteger from roTimespan.TotalMilliseconds.
    if kind <> "Integer" and kind <> "roInt" and kind <> "roInteger" and kind <> "LongInteger" and kind <> "roLongInteger" and kind <> "roInt64" and kind <> "Float" and kind <> "roFloat" and kind <> "Double" and kind <> "roDouble" then return invalid
    ' Arithmetic unboxes roLongInteger/roInt wrappers before status JSON.
    if value >= 0 and value <= maximum then return value + 0
    return invalid
end function

function DeliveryInfo_Integer(value as dynamic, maximum as dynamic) as dynamic
    bounded = DeliveryInfo_Number(value,maximum)
    if bounded <> invalid
        if Int(bounded) = bounded then return bounded
    end if
    return invalid
end function

function DeliveryInfo_Boolean(value as dynamic) as dynamic
    kind = Type(value)
    if kind = "Boolean" or kind = "roBoolean" then return value
    return invalid
end function

function DeliveryInfo_State(value as dynamic) as string
    state = LCase(PlaybackInfo_Text(value))
    for each known in ["none","buffering","playing","paused","stopping","stopped","finished","error"]
        if state = known then return state
    end for
    return "unknown"
end function

sub onDeliveryStreamInfoChanged(event as object)
    if not DeliveryInfo_Active() then return
    source = event.GetRoSGNode()
    if source = invalid then return
    if not source.IsSameNode(m.video) then return
    if LCase(event.GetField()) <> "streaminfo" then return
    context = event.GetInfo()
    if Type(context) <> "roAssociativeArray" then return
    generation = DeliveryInfo_Integer(context.crimsonDeliveryGeneration,2147483647)
    if generation = invalid or generation <> m.deliveryGeneration then return
    ' Do not poll m.video.streamInfo: the reused native node can retain its
    ' previous file's read-only value before any new notification arrives.
    info = event.GetData()
    if Type(info) <> "roAssociativeArray" then return
    if GetInterface(info.streamUrl,"ifString") = invalid then return
    if info.streamUrl <> m.deliveryExpectedUrl then return
    snapshot = {available:true,measuredAtSelectionBitsPerSecond:invalid,streamBitrateNative:invalid,isUnderrun:invalid,isResume:invalid}
    snapshot.measuredAtSelectionBitsPerSecond = DeliveryInfo_Bitrate(info.measuredBitrate)
    ' The SceneGraph reference specifies bps only for measuredBitrate; retain
    ' streamBitrate as a raw native scalar rather than assume its unit. The
    ' older roVideoPlayerEvent measured rate uses a different unit entirely.
    snapshot.streamBitrateNative = DeliveryInfo_Bitrate(info.streamBitrate)
    if Type(info.isUnderrun) = "Boolean" or Type(info.isUnderrun) = "roBoolean" then snapshot.isUnderrun = info.isUnderrun
    if Type(info.isResume) = "Boolean" or Type(info.isResume) = "roBoolean" then snapshot.isResume = info.isResume
    m.deliveryInfo = snapshot
end sub

function DeliveryInfo_Bitrate(value as dynamic) as dynamic
    kind = Type(value)
    if kind <> "Integer" and kind <> "roInt" and kind <> "roInteger" and kind <> "Float" and kind <> "roFloat" and kind <> "Double" and kind <> "roDouble" then return invalid
    ' Native streamInfo documents integer rates. Missing, zero, negative,
    ' fractional or out-of-range values are unknown, never a zero-speed claim.
    if value > 0 and value <= 2147483647
        if Int(value) = value then return value
    end if
    return invalid
end function

function DeliveryInfo_Status() as object
    result = {available:false,measurement:"native-stream-selection-estimate",measuredAtSelectionBitsPerSecond:invalid,streamBitrateNative:invalid,isUnderrun:invalid,isResume:invalid,traceTimeBase:"callback-receipt-ms-since-source-begin",trace:[],traceDropped:0}
    if not DeliveryInfo_Active() then return result
    if Type(m.deliveryTrace) = "roArray"
        for each sample in m.deliveryTrace
            copied = {}
            for each field in sample
                copied[field] = sample[field]
            end for
            result.trace.Push(copied)
        end for
        result.traceDropped = m.deliveryTraceDropped
    end if
    if Type(m.deliveryInfo) <> "roAssociativeArray" then return result
    ' Copy only these fixed scalar fields. Never return the stored associative
    ' array by reference, raw native metadata, provider text or native URLs.
    result.available = m.deliveryInfo.available = true
    result.measuredAtSelectionBitsPerSecond = m.deliveryInfo.measuredAtSelectionBitsPerSecond
    result.streamBitrateNative = m.deliveryInfo.streamBitrateNative
    result.isUnderrun = m.deliveryInfo.isUnderrun
    result.isResume = m.deliveryInfo.isResume
    return result
end function
