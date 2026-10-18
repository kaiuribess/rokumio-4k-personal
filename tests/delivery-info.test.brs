function DeliveryFixtureVideo(url as string) as object
    if m.fixtureNodeSequence = invalid then m.fixtureNodeSequence = 0
    m.fixtureNodeSequence = m.fixtureNodeSequence + 1
    return {
        fixtureNodeId:m.fixtureNodeSequence
        state:"playing"
        content:{url:url}
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
    Harness_Equal(m.video.observations.Count(),1,"init observes one native field")
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
    Harness_Equal(snapshot.Count(),6,"status has only fixed scalar fields")
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
    Harness_Finish()
end sub
