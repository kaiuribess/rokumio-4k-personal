function DeliveryFixtureVideo(url as string) as object
    if m.fixtureNodeSequence = invalid then m.fixtureNodeSequence = 0
    m.fixtureNodeSequence = m.fixtureNodeSequence + 1
    return {
        fixtureNodeId:m.fixtureNodeSequence
        state:"playing"
        content:{url:url}
        position:10
        duration:900
        positionInfo:{audio:10,video:10,clip_id:1,epoch:0}
        bufferingStatus:invalid
        streamInfo:{streamUrl:url,measuredBitrate:999999999,streamBitrate:999999999}
        observations:[]
        HasField:function(name as string) as boolean
            return m.DoesExist(name)
        end function
        AddField:function(name as string,kind as string,notify as boolean) as boolean
            m[name] = 0
            return true
        end function
        IsSameNode:function(node as object) as boolean
            return m.fixtureNodeId = node.fixtureNodeId
        end function
        ObserveField:sub(name as string,callback as string,context as object)
            m.observations.Push({field:name,callback:callback,context:context})
        end sub
    }
end function

function DeliveryFixtureClock() as dynamic
    if m.noDeliveryClock = true then return invalid
    return {elapsed:0,Mark:sub()
        m.elapsed = 0
    end sub,TotalMilliseconds:function() as integer
        return m.elapsed
    end function}
end function

function DeliveryFixtureEvent(data as dynamic) as object
    return {
        data:data
        node:m.video
        field:"streamInfo"
        info:{crimsonDeliveryGeneration:m.deliveryGeneration}
        GetData:function() as dynamic
            return m.data
        end function
        GetRoSGNode:function() as dynamic
            return m.node
        end function
        GetField:function() as dynamic
            return m.field
        end function
        GetInfo:function() as dynamic
            return m.info
        end function
    }
end function

' Non-delivery dependencies of the real PlaybackStatus callback are fixed
' fixture facts. DeliveryInfo_Status and its native callback run unmodified.
function CurrentEnglishAudioCheck() as object
    return {verified:false,reason:"fixture",englishTracks:[]}
end function
function NativeMedia_Reason(media as dynamic) as string
    return "unknown"
end function
function NativeMedia_Resolution(media as dynamic) as string
    return "unknown"
end function
function BufferingRecovery_Status() as object
    return {underruns:0}
end function

sub Main()
    Harness_Suite("Native delivery notification to real playback-status boundary")
    m.video = invalid
    Harness_Ok(not DeliveryInfo_Status().available,"partial fixture without init safely reports unknown")
    ResetDeliveryInfo()
    Harness_Ok(not DeliveryInfo_Status().available,"reset without native Video is safe")

    first = "https://media.example/first.mkv?fixture=private-first"
    second = "https://media.example/second.mkv?fixture=private-second"
    m.video = DeliveryFixtureVideo(first)
    m.playbackActive = true
    m.retryPending = false
    m.playArmed = false
    m.sourceIndex = 0
    InitDeliveryInfo()
    Harness_Equal(m.video.observations.Count(),4,"init observes stream information, two diagnostic events and duration")
    Harness_Equal(m.video.observations[0].field,"streamInfo","native streamInfo is the event source")
    Harness_Equal(m.video.observations[0].callback,"onDeliveryStreamInfoChanged","production callback is registered")
    Harness_Equal(m.video.observations[0].context[0],"crimsonDeliveryGeneration","attempt context is requested at native event creation")
    BeginDeliveryInfo(first)
    snapshot = PlaybackStatus().delivery
    Harness_Ok(not snapshot.available,"retained native field is ignored before a fresh notification")
    Harness_Equal(snapshot.measuredAtSelectionBitsPerSecond,invalid,"cached previous stream speed is never polled")

    info = {streamUrl:first,measuredBitrate:24000000,streamBitrate:12000000,isUnderrun:false,isResume:false,token:"fixture-secret",headers:{Authorization:"fixture-secret"},extra:"private-title"}
    firstEvent = DeliveryFixtureEvent(info)
    onDeliveryStreamInfoChanged(firstEvent)
    snapshot = PlaybackStatus().delivery
    Harness_Ok(snapshot.available,"matching native event crosses the real status boundary")
    Harness_Equal(snapshot.measuredAtSelectionBitsPerSecond,24000000,"native selection-time measurement remains unscaled")
    Harness_Equal(snapshot.streamBitrateNative,12000000,"stream bitrate remains a separate field")
    Harness_Equal(snapshot.measurement,"native-stream-selection-estimate","semantics never claim continuous current speed")
    Harness_Equal(snapshot.isUnderrun,false,"false native underrun remains false")
    Harness_Equal(snapshot.isResume,false,"false resume remains false")
    json = FormatJson(PlaybackStatus())
    Harness_Ok(json.InStr("https://") < 0,"full status contains no stream URL")
    Harness_Ok(json.InStr("fixture-secret") < 0,"native tokens and headers are excluded")
    Harness_Ok(json.InStr("private-title") < 0,"arbitrary native text is excluded")
    Harness_Equal(snapshot.Count(),9,"status has only fixed delivery fields and bounded trace fields")
    info.measuredBitrate = 123
    snapshot.streamBitrateNative = 456
    Harness_Equal(PlaybackStatus().delivery.measuredAtSelectionBitsPerSecond,24000000,"input mutation cannot change stored scalar snapshot")
    Harness_Equal(PlaybackStatus().delivery.streamBitrateNative,12000000,"returned snapshot cannot mutate internal state")

    Harness_Suite("Source transitions, stale and unmatched native notifications")
    BeginDeliveryInfo(first)
    onDeliveryStreamInfoChanged(firstEvent)
    Harness_Ok(not PlaybackStatus().delivery.available,"queued prior-attempt event is rejected even when the URL is identical")
    wrongNodeEvent = DeliveryFixtureEvent(info)
    wrongNodeEvent.node = DeliveryFixtureVideo(first)
    onDeliveryStreamInfoChanged(wrongNodeEvent)
    Harness_Ok(not PlaybackStatus().delivery.available,"matching URL from a different native node is rejected")
    missingContext = DeliveryFixtureEvent(info)
    missingContext.info = {}
    onDeliveryStreamInfoChanged(missingContext)
    Harness_Ok(not PlaybackStatus().delivery.available,"event without captured attempt context is rejected")
    BeginDeliveryInfo(second)
    Harness_Ok(not PlaybackStatus().delivery.available,"new source immediately clears previous telemetry")
    onDeliveryStreamInfoChanged(DeliveryFixtureEvent({streamUrl:second,measuredBitrate:18000000}))
    Harness_Ok(not PlaybackStatus().delivery.available,"new report cannot apply while native content still belongs to old source")
    m.video.content = {url:second}
    onDeliveryStreamInfoChanged(DeliveryFixtureEvent(info))
    Harness_Ok(not PlaybackStatus().delivery.available,"delayed old-source notification cannot attach to a new source")
    onDeliveryStreamInfoChanged(DeliveryFixtureEvent({streamUrl:"https://redirect.example/unknown.mkv",measuredBitrate:18000000}))
    Harness_Ok(not PlaybackStatus().delivery.available,"unmatched redirected URL remains unknown rather than guessed")
    onDeliveryStreamInfoChanged(DeliveryFixtureEvent({measuredBitrate:18000000}))
    Harness_Ok(not PlaybackStatus().delivery.available,"event without source correlation remains unknown")
    nextInfo = {streamUrl:second,measuredBitrate:18000000,streamBitrate:11000000,isUnderrun:true,isResume:false}
    m.playArmed = true
    onDeliveryStreamInfoChanged(DeliveryFixtureEvent(nextInfo))
    Harness_Ok(not PlaybackStatus().delivery.available,"queued event before play kick is ignored")
    m.playArmed = false:m.retryPending = true
    onDeliveryStreamInfoChanged(DeliveryFixtureEvent(nextInfo))
    Harness_Ok(not PlaybackStatus().delivery.available,"retry teardown cannot accept a native event")
    m.retryPending = false:m.playbackActive = false
    onDeliveryStreamInfoChanged(DeliveryFixtureEvent(nextInfo))
    Harness_Ok(not PlaybackStatus().delivery.available,"inactive playback cannot accept a native event")
    m.playbackActive = true:m.video.state = "stopped"
    onDeliveryStreamInfoChanged(DeliveryFixtureEvent(nextInfo))
    Harness_Ok(not PlaybackStatus().delivery.available,"stopped native player cannot accept a native event")
    m.video.state = "buffering"
    onDeliveryStreamInfoChanged(DeliveryFixtureEvent(nextInfo))
    Harness_Ok(PlaybackStatus().delivery.available,"fresh matching buffering event is observable")
    Harness_Equal(PlaybackStatus().delivery.isUnderrun,true,"native underrun evidence is preserved")
    onDeliveryStreamInfoChanged(DeliveryFixtureEvent(nextInfo))
    Harness_Equal(PlaybackStatus().delivery.measuredAtSelectionBitsPerSecond,18000000,"duplicate notification is idempotent")
    ResetDeliveryInfo()
    onDeliveryStreamInfoChanged(DeliveryFixtureEvent(nextInfo))
    Harness_Ok(not PlaybackStatus().delivery.available,"notification after teardown cannot revive old telemetry")
    BeginDeliveryInfo(second)
    Harness_Ok(not PlaybackStatus().delivery.available,"same-URL retry also waits for a fresh notification")

    Harness_Suite("Malformed native measurements stay unknown and bounded")
    onDeliveryStreamInfoChanged(DeliveryFixtureEvent({streamUrl:second,measuredBitrate:"18000000",streamBitrate:-5,isUnderrun:"true",isResume:1}))
    snapshot = PlaybackStatus().delivery
    Harness_Ok(snapshot.available,"source-correlated event can be present with unknown measurements")
    Harness_Equal(snapshot.measuredAtSelectionBitsPerSecond,invalid,"numeric string is not trusted as native rate")
    Harness_Equal(snapshot.streamBitrateNative,invalid,"negative rate remains unknown")
    Harness_Equal(snapshot.isUnderrun,invalid,"string boolean cannot claim underrun")
    Harness_Equal(snapshot.isResume,invalid,"integer boolean cannot claim trickplay resume")
    for each bad in [invalid,0,-1,1.5,2147483648.0,true,"9000",{},[]]
        Harness_Equal(DeliveryInfo_Bitrate(bad),invalid,"non-positive, non-integer or malformed rates remain unknown")
    end for
    Harness_Equal(DeliveryInfo_Bitrate(1),1,"positive native integer boundary is accepted")
    Harness_Equal(DeliveryInfo_Bitrate(2147483647),2147483647,"documented integer maximum is accepted")
    ResetDeliveryInfo()
    for each malformed in [invalid,1,"native-text",[],{}]
        onDeliveryStreamInfoChanged(DeliveryFixtureEvent(malformed))
        Harness_Ok(not DeliveryInfo_Status().available,"malformed or uncorrelated notification is harmless")
    end for
    m.video = invalid
    Harness_Ok(not PlaybackStatus().delivery.available,"status remains safe after Video teardown")
    RunDeliveryTraceTests(first,second)
    RunDeliveryDurationTests(first,second)
    Harness_Finish()
end sub

function DeliveryDurationEvent(value as dynamic) as object
    event = DeliveryFixtureEvent(value)
    event.field = "duration"
    return event
end function

sub RunDeliveryDurationTests(first as string,second as string)
    Harness_Suite("Fresh native duration to real file-facts boundary")
    m.video = DeliveryFixtureVideo(first)
    m.playbackActive = true:m.retryPending = false:m.playArmed = false:m.sourceIndex = 0
    m.resolvedPlayback = {media:{declaredFileBytes:5000000000#},streamFormat:"mkv"}
    InitDeliveryInfo()
    Harness_Equal(m.video.observations[3].field,"duration","native duration observer is registered")
    Harness_Equal(m.video.observations[3].callback,"onDeliveryDurationChanged","duration uses its dedicated read-only callback")
    Harness_Equal(m.video.observations[3].context[0],"crimsonDeliveryGeneration","duration captures the attempt generation at event creation")
    BeginDeliveryInfo(first)
    Harness_Equal(DeliveryInfo_Duration(),invalid,"retained duration is unknown before a fresh event")
    Harness_Equal(PlaybackStatus().file.declaredFileBytes,5000000000#,"inspection size remains available independently")
    Harness_Equal(PlaybackStatus().file.nativeDurationSeconds,invalid,"real status never pairs size with retained duration")
    Harness_Equal(PlaybackStatus().file.averageContainerBitsPerSecond,invalid,"no average rate is invented without fresh duration")
    firstDuration = DeliveryDurationEvent(1000)
    onDeliveryDurationChanged(firstDuration)
    Harness_Equal(DeliveryInfo_Duration(),1000,"matching event supplies source-correlated duration")
    Harness_Equal(PlaybackStatus().file.nativeDurationSeconds,1000,"fresh event crosses the real file-facts boundary")
    Harness_Equal(PlaybackStatus().file.averageContainerBitsPerSecond,40000000#,"average container rate uses correlated duration")
    m.video.duration = 300
    Harness_Equal(DeliveryInfo_Duration(),1000,"cached native field changes are never polled")

    BeginDeliveryInfo(second)
    m.resolvedPlayback.media.declaredFileBytes = 10000000000#
    Harness_Equal(DeliveryInfo_Duration(),invalid,"new source clears prior duration immediately")
    onDeliveryDurationChanged(DeliveryDurationEvent(2000))
    Harness_Equal(DeliveryInfo_Duration(),invalid,"event cannot apply while native content still belongs to previous source")
    m.video.content = {url:second}
    onDeliveryDurationChanged(firstDuration)
    Harness_Equal(PlaybackStatus().file.nativeDurationSeconds,invalid,"queued A duration cannot attach to B size")
    Harness_Equal(PlaybackStatus().file.averageContainerBitsPerSecond,invalid,"A-to-B transition cannot produce a stale average rate")
    secondDuration = DeliveryDurationEvent(2000)
    onDeliveryDurationChanged(secondDuration)
    Harness_Equal(PlaybackStatus().file.averageContainerBitsPerSecond,40000000#,"B gets its own fresh duration")
    BeginDeliveryInfo(second)
    m.video.duration = 2000
    onDeliveryDurationChanged(secondDuration)
    Harness_Equal(DeliveryInfo_Duration(),invalid,"same-URL previous-generation event is rejected")
    Harness_Equal(PlaybackStatus().file.averageContainerBitsPerSecond,invalid,"same unchanged native duration remains unknown without a new event")
    onDeliveryDurationChanged(DeliveryDurationEvent(2000))
    Harness_Equal(DeliveryInfo_Duration(),2000,"fresh notification can confirm the same numeric duration on retry")
    ResetDeliveryInfo()
    Harness_Equal(DeliveryInfo_Duration(),invalid,"teardown clears duration")

    Harness_Suite("Duration event ownership, inactive states and invalid values")
    BeginDeliveryInfo(second)
    wrongNode = DeliveryDurationEvent(1000)
    wrongNode.node = DeliveryFixtureVideo(second)
    onDeliveryDurationChanged(wrongNode)
    Harness_Equal(DeliveryInfo_Duration(),invalid,"duration from another native node is ignored")
    wrongField = DeliveryDurationEvent(1000):wrongField.field = "position"
    onDeliveryDurationChanged(wrongField)
    Harness_Equal(DeliveryInfo_Duration(),invalid,"other native fields cannot become duration")
    missingGeneration = DeliveryDurationEvent(1000):missingGeneration.info = {}
    onDeliveryDurationChanged(missingGeneration)
    Harness_Equal(DeliveryInfo_Duration(),invalid,"missing generation cannot prove freshness")
    m.playArmed = true
    onDeliveryDurationChanged(DeliveryDurationEvent(1000))
    Harness_Equal(DeliveryInfo_Duration(),invalid,"pre-play callback cannot establish duration")
    m.playArmed = false:m.retryPending = true
    onDeliveryDurationChanged(DeliveryDurationEvent(1000))
    Harness_Equal(DeliveryInfo_Duration(),invalid,"retry teardown cannot establish duration")
    m.retryPending = false:m.playbackActive = false
    onDeliveryDurationChanged(DeliveryDurationEvent(1000))
    Harness_Equal(DeliveryInfo_Duration(),invalid,"inactive callback cannot establish duration")
    m.playbackActive = true:m.video.state = "stopped"
    onDeliveryDurationChanged(DeliveryDurationEvent(1000))
    Harness_Equal(DeliveryInfo_Duration(),invalid,"stopped native player cannot establish duration")
    m.video.state = "buffering"
    for each bad in [invalid,0,-1,0.5,604801,2147483648.0,true,"1000",{},[]]
        onDeliveryDurationChanged(DeliveryDurationEvent(1000))
        onDeliveryDurationChanged(DeliveryDurationEvent(bad))
        Harness_Equal(DeliveryInfo_Duration(),invalid,"malformed fresh duration clears the previously accepted value")
    end for
    for each good in [1,1000.5,604800]
        onDeliveryDurationChanged(DeliveryDurationEvent(good))
        Harness_Equal(DeliveryInfo_Duration(),good,"bounded duration supports fractional seconds and endpoint values")
    end for
    m.playbackActive = false
    Harness_Equal(DeliveryInfo_Duration(),invalid,"stored duration is hidden once playback becomes inactive")
    m.playbackActive = true:m.video.content = {url:first}
    Harness_Equal(DeliveryInfo_Duration(),invalid,"stored duration cannot cross changed native content")
    m.video = invalid
    Harness_Equal(DeliveryInfo_Duration(),invalid,"duration getter is safe after Video node teardown")
end sub

function DeliveryTraceEvent(field as string, data as dynamic, context as object) as object
    event = DeliveryFixtureEvent(data)
    event.field = field
    event.info = context
    event.info.crimsonDeliveryGeneration = m.deliveryGeneration
    return event
end function

sub RunDeliveryTraceTests(first as string,second as string)
    Harness_Suite("Event snapshots and current native values remain distinguishable")
    m.video = DeliveryFixtureVideo(first)
    m.playbackActive = true:m.retryPending = false:m.playArmed = false:m.sourceIndex = 2
    InitDeliveryInfo()
    Harness_Equal(m.video.observations[1].field,"state","diagnostic observer subscribes to state transitions")
    Harness_Equal(m.video.observations[2].field,"bufferingStatus","diagnostic observer subscribes to buffering updates")
    Harness_Equal(m.video.observations[1].callback,"onDeliveryPlaybackEvent","dedicated observer cannot change production playback handlers")
    Harness_Equal(m.video.observations[1].context.Count(),5,"native event creation captures generation and relevant playback fields")
    BeginDeliveryInfo(first)
    m.video.state = "playing"
    m.video.position = 101
    m.video.positionInfo = {audio:100.9,video:101,clip_id:2,epoch:0}
    m.video.bufferingStatus = invalid
    context = {state:"buffering",position:100,positionInfo:{audio:99.5,video:100,clip_id:2,epoch:0},bufferingStatus:{isUnderrun:true,percentage:20}}
    event = DeliveryTraceEvent("state","buffering",context)
    m.deliveryTraceClock.elapsed = 75
    onDeliveryPlaybackEvent(event)
    status = PlaybackStatus().delivery
    Harness_Equal(status.trace.Count(),1,"trace is available before optional streamInfo measurement")
    sample = status.trace[0]
    Harness_Equal(sample.receiptMilliseconds,75,"trace reports monotonic callback receipt time")
    Harness_Equal(status.traceTimeBase,"callback-receipt-ms-since-source-begin","time basis does not imply a native event timestamp")
    Harness_Equal(sample.eventState,"buffering","queued state comes from the event payload")
    Harness_Equal(sample.currentState,"playing","later current native state is independently visible")
    Harness_Equal(sample.eventIsUnderrun,true,"captured underrun flag survives current field clearing")
    Harness_Equal(sample.currentIsUnderrun,invalid,"cleared current native flag stays unknown")
    Harness_Equal(sample.eventPercentage,20,"captured buffer percentage is preserved")
    Harness_Equal(sample.eventPosition,100,"event context preserves earlier position")
    Harness_Equal(sample.currentPosition,101,"current position is separate from event context")
    Harness_Equal(sample.eventAudioPosition,99.5,"captured rendered audio position remains numeric")
    Harness_Equal(sample.currentVideoPosition,101,"current rendered video position remains numeric")
    Harness_Equal(sample.eventClipId,2,"clip context is retained as a bounded scalar")
    Harness_Equal(sample.eventEpoch,0,"relative timestamp epoch is explicit")
    Harness_Equal(sample.attempt,3,"attempt ordinal is recorded without stream identity")
    Harness_Equal(sample.generation,m.deliveryGeneration,"trace belongs to the active attempt generation")
    event.data = "private-state":context.position = 900
    status.trace[0].eventPosition = 999
    Harness_Equal(DeliveryInfo_Status().trace[0].eventPosition,100,"returned and input objects cannot mutate stored trace")
    event = DeliveryTraceEvent("bufferingStatus",{isUnderrun:false,percentage:80},{state:"buffering",bufferingStatus:{isUnderrun:true,percentage:1}})
    onDeliveryPlaybackEvent(event)
    sample = DeliveryInfo_Status().trace[1]
    Harness_Equal(sample.eventIsUnderrun,false,"buffering event payload overrides separately captured status context")
    Harness_Equal(sample.eventPercentage,80,"buffering payload percentage is used without polling")

    Harness_Suite("Trace bounds, redaction and current-source ownership")
    stale = DeliveryTraceEvent("state","buffering",{})
    BeginDeliveryInfo(first)
    onDeliveryPlaybackEvent(stale)
    Harness_Equal(DeliveryInfo_Status().trace.Count(),0,"stale same-URL trace event cannot cross source generations")
    event = DeliveryTraceEvent("state","buffering",{})
    event.node = DeliveryFixtureVideo(first)
    onDeliveryPlaybackEvent(event)
    Harness_Equal(DeliveryInfo_Status().trace.Count(),0,"another Video node cannot write active trace")
    event = DeliveryTraceEvent("state","buffering",{})
    event.info = {}
    onDeliveryPlaybackEvent(event)
    Harness_Equal(DeliveryInfo_Status().trace.Count(),0,"missing generation context is rejected")
    event = DeliveryTraceEvent("state","buffering",{})
    event.info.crimsonDeliveryGeneration = "private-generation"
    onDeliveryPlaybackEvent(event)
    Harness_Equal(DeliveryInfo_Status().trace.Count(),0,"malformed generation context is rejected")
    event = DeliveryTraceEvent("position",123,{})
    onDeliveryPlaybackEvent(event)
    Harness_Equal(DeliveryInfo_Status().trace.Count(),0,"unrequested event types are rejected")
    BeginDeliveryInfo(second)
    onDeliveryPlaybackEvent(DeliveryTraceEvent("state","buffering",{}))
    Harness_Equal(DeliveryInfo_Status().trace.Count(),0,"mismatched native content blocks trace before handoff")
    m.video.content = {url:second}
    m.playArmed = true
    onDeliveryPlaybackEvent(DeliveryTraceEvent("state","buffering",{}))
    Harness_Equal(DeliveryInfo_Status().trace.Count(),0,"pre-play events cannot populate trace")
    m.playArmed = false:m.retryPending = true
    onDeliveryPlaybackEvent(DeliveryTraceEvent("state","buffering",{}))
    Harness_Equal(DeliveryInfo_Status().trace.Count(),0,"retry teardown excludes trace callbacks")
    m.retryPending = false:m.playbackActive = false
    onDeliveryPlaybackEvent(DeliveryTraceEvent("state","buffering",{}))
    Harness_Equal(DeliveryInfo_Status().trace.Count(),0,"inactive playback excludes trace callbacks")
    m.playbackActive = true
    for i = 0 to 69
        m.deliveryTraceClock.elapsed = i
        onDeliveryPlaybackEvent(DeliveryTraceEvent("state","playing",{position:i}))
    end for
    status = DeliveryInfo_Status()
    Harness_Equal(status.trace.Count(),64,"trace is bounded at64 records")
    Harness_Equal(status.traceDropped,6,"dropped count explains bounded history")
    Harness_Equal(status.trace[0].receiptMilliseconds,6,"oldest records are evicted first")
    Harness_Equal(status.trace[63].receiptMilliseconds,69,"newest event is retained")
    private = "https://private.invalid/source?token=fixture-secret"
    m.video.bufferingStatus = {isUnderrun:private,percentage:private,headers:{Authorization:private}}
    m.video.positionInfo = {audio:private,video:-1,clip_id:private,epoch:private}
    m.video.position = private
    malicious = DeliveryTraceEvent("state",private,{state:private,position:private,positionInfo:{audio:private,video:{url:private},clip_id:private,epoch:7},bufferingStatus:{isUnderrun:private,percentage:101},token:private})
    onDeliveryPlaybackEvent(malicious)
    sample = DeliveryInfo_Status().trace[63]
    Harness_Equal(sample.eventState,"unknown","arbitrary native state is not exposed")
    Harness_Equal(sample.eventPosition,invalid,"non-numeric event position is not exposed")
    Harness_Equal(sample.currentPosition,invalid,"non-numeric current position is not exposed")
    Harness_Equal(sample.eventIsUnderrun,invalid,"non-boolean flag is not exposed")
    Harness_Equal(sample.eventPercentage,invalid,"out-of-range percentage is not exposed")
    Harness_Equal(sample.eventEpoch,invalid,"unknown epoch remains unknown")
    Harness_Equal(DeliveryInfo_Integer(0.5,1),invalid,"fractional epoch cannot be reported as a valid clock basis")
    json = FormatJson(PlaybackStatus())
    Harness_Ok(json.InStr("private.invalid") < 0 and json.InStr("fixture-secret") < 0,"all trace snapshots exclude URLs, tokens, headers and arbitrary text")
    m.deliveryTraceClock = {TotalMilliseconds:function() as longinteger
        return 275&
    end function}
    Harness_Equal(Type(m.deliveryTraceClock.TotalMilliseconds()),"LongInteger","fixture reproduces Roku OS15.3 native64-bit timer result")
    onDeliveryPlaybackEvent(DeliveryTraceEvent("state","playing",{}))
    Harness_Equal(DeliveryInfo_Status().trace[63].receiptMilliseconds,275,"native64-bit callback receipt time survives bounded scalar validation")
    boxedTimer = CreateObject("roLongInteger")
    boxedTimer.SetLongInt(275&)
    normalizedTimer = DeliveryInfo_Number(boxedTimer,2147483647)
    Harness_Equal(normalizedTimer,275,"boxed64-bit native scalar is accepted within bounds")
    Harness_Equal(FormatJson({receiptMilliseconds:normalizedTimer}),"{" + Chr(34) + "receiptMilliseconds" + Chr(34) + ":275}","boxed64-bit callback timing is serialized as a JSON number")
    Harness_Equal(DeliveryInfo_Number(2147483648&,2147483647),invalid,"64-bit values beyond the diagnostic budget remain unknown")
    m.noDeliveryClock = true
    BeginDeliveryInfo(second)
    onDeliveryPlaybackEvent(DeliveryTraceEvent("state","playing",{}))
    Harness_Equal(DeliveryInfo_Status().trace[0].receiptMilliseconds,invalid,"missing clock produces unknown receipt time without inventing duration")
    m.noDeliveryClock = false
    ResetDeliveryInfo()
    Harness_Equal(DeliveryInfo_Status().trace.Count(),0,"teardown clears trace")
end sub
