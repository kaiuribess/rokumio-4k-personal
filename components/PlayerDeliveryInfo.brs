' Read-only, source-correlated native delivery facts. Roku streamInfo reports
' the network estimate at stream selection, not a continuous throughput test.
' The native URL is compared privately and never copied into status or logs.
' See https://developer.roku.com/dev/docs/video (streamInfo).
sub InitDeliveryInfo()
    ResetDeliveryInfo()
    if m.video = invalid then return
    if not m.video.HasField("streamInfo") then return
    if not m.video.HasField("crimsonDeliveryGeneration")
        if not m.video.AddField("crimsonDeliveryGeneration","integer",false) then return
    end if
    m.video.crimsonDeliveryGeneration = m.deliveryGeneration
    ' ObserveField context is captured when the event occurs, so a queued
    ' notification cannot cross attempts even when both use the same URL.
    ' https://developer.roku.com/dev/docs/ifsgnodefield (infoFields, OS 9.3+).
    m.video.ObserveField("streamInfo","onDeliveryStreamInfoChanged",["crimsonDeliveryGeneration"])
end sub

sub ResetDeliveryInfo()
    m.deliveryExpectedUrl = ""
    m.deliveryInfo = invalid
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

sub onDeliveryStreamInfoChanged(event as object)
    if not DeliveryInfo_Active() then return
    source = event.GetRoSGNode()
    if source = invalid then return
    if not source.IsSameNode(m.video) then return
    if LCase(event.GetField()) <> "streaminfo" then return
    context = event.GetInfo()
    if Type(context) <> "roAssociativeArray" then return
    if context.crimsonDeliveryGeneration <> m.deliveryGeneration then return
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
    result = {available:false,measurement:"native-stream-selection-estimate",measuredAtSelectionBitsPerSecond:invalid,streamBitrateNative:invalid,isUnderrun:invalid,isResume:invalid}
    if not DeliveryInfo_Active() or Type(m.deliveryInfo) <> "roAssociativeArray" then return result
    ' Copy only these fixed scalar fields. Never return the stored associative
    ' array by reference, raw native metadata, provider text or native URLs.
    result.available = m.deliveryInfo.available = true
    result.measuredAtSelectionBitsPerSecond = m.deliveryInfo.measuredAtSelectionBitsPerSecond
    result.streamBitrateNative = m.deliveryInfo.streamBitrateNative
    result.isUnderrun = m.deliveryInfo.isUnderrun
    result.isResume = m.deliveryInfo.isResume
    return result
end function
