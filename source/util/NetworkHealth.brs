' Passive, bounded device facts for the local playback diagnostic. This does
' not test the Internet or download media. No native record, network name,
' address, identifier, exception text or provider URL is retained or emitted.
' https://developer.roku.com/dev/docs/ifdeviceinfo documents these fields,
' but does not specify expectedThroughput units or counter reset semantics.
sub NetworkHealth_Reset()
    m.networkHealthCache = invalid
    m.networkHealthSampleTime = invalid
    m.networkHealthClock = invalid
end sub

function NetworkHealth_Empty() as object
    return {
        available:false
        connectionType:invalid
        protocol:invalid
        signal:invalid
        txFailed:invalid
        txRetries:invalid
        expectedThroughputNative:invalid
        expectedThroughputUnits:"unspecified"
        memoryLevel:invalid
        counterDeltaAvailable:false
        counterStatus:"unknown"
        txFailedDelta:invalid
        txRetriesDelta:invalid
        elapsedSeconds:invalid
        sampleAgeSeconds:invalid
    }
end function

' Optional device/clock inputs are deterministic test seams. Production uses
' one roDeviceInfo read per ten seconds, including failed reads. The cache
' contains only the scalar allowlist; callers always receive a separate copy.
function NetworkHealth_Read(device = invalid as dynamic, nowSeconds = invalid as dynamic) as object
    if nowSeconds = invalid then nowSeconds = NetworkHealth_Now()
    now = NetworkHealth_Number(nowSeconds, 0, 2147483647, false)
    if now = invalid then return NetworkHealth_Empty()

    previous = m.networkHealthCache
    previousTime = m.networkHealthSampleTime
    elapsed = invalid
    if Type(previous) = "roAssociativeArray" and previousTime <> invalid
        if now >= previousTime
            elapsed = now - previousTime
            if elapsed < 10 then return NetworkHealth_Copy(previous, elapsed)
        else
            ' Timer wrap/reset must not turn old counters into a fresh delta.
            previous = invalid
        end if
    end if

    result = NetworkHealth_Empty()
    try
        if device = invalid then device = CreateObject("roDeviceInfo")
        if device <> invalid
            info = device.GetConnectionInfo()
            if Type(info) = "roAssociativeArray"
                result.connectionType = NetworkHealth_ConnectionType(info.type)
                result.available = result.connectionType <> invalid
                if result.connectionType = "WiFiConnection"
                    result.protocol = NetworkHealth_Protocol(info.protocol)
                    result.signal = NetworkHealth_Number(info.signal, -100, 0, false)
                end if
                if result.connectionType = "WiFiConnection" or result.connectionType = "WiredConnection"
                    result.txFailed = NetworkHealth_Number(info.txFailed, 0, 2147483647, true)
                    result.txRetries = NetworkHealth_Number(info.txRetries, 0, 2147483647, true)
                    result.expectedThroughputNative = NetworkHealth_Number(info.expectedThroughput, 0, 2147483647, false)
                end if
            end if
        end if
    catch e
        ' A failed API read is unknown, never a retained healthy sample.
    end try
    try
        if device <> invalid then result.memoryLevel = NetworkHealth_MemoryLevel(device.GetGeneralMemoryLevel())
    catch e
        ' Memory availability is independent from connection information.
    end try

    if result.txFailed <> invalid and result.txRetries <> invalid
        result.counterStatus = "baseline"
        if Type(previous) = "roAssociativeArray" and elapsed <> invalid
            if result.connectionType <> previous.connectionType
                result.counterStatus = "connection-type-changed"
            else if previous.txFailed <> invalid and previous.txRetries <> invalid
                if result.txFailed >= previous.txFailed and result.txRetries >= previous.txRetries
                    result.counterDeltaAvailable = true
                    result.counterStatus = "monotonic-same-type"
                    result.txFailedDelta = result.txFailed - previous.txFailed
                    result.txRetriesDelta = result.txRetries - previous.txRetries
                    result.elapsedSeconds = elapsed
                else
                    result.counterStatus = "reset-or-wrap"
                end if
            end if
        end if
    end if
    ' No SSID is retained to identify roaming. Even a same-type monotonic
    ' delta is an observed counter difference, not a packet-loss percentage,
    ' proof of one unchanged access point, or a media-host speed measurement.
    m.networkHealthCache = result
    m.networkHealthSampleTime = now
    return NetworkHealth_Copy(result, 0)
end function

function NetworkHealth_Now() as dynamic
    try
        if m.networkHealthClock = invalid then m.networkHealthClock = CreateObject("roTimespan")
        if m.networkHealthClock <> invalid then return m.networkHealthClock.TotalMilliseconds() / 1000.0
    catch e
    end try
    return invalid
end function

function NetworkHealth_Copy(snapshot as object, ageSeconds as dynamic) as object
    copy = NetworkHealth_Empty()
    for each key in copy
        copy[key] = snapshot[key]
    end for
    copy.sampleAgeSeconds = ageSeconds
    return copy
end function

function NetworkHealth_Number(value as dynamic, minimum as dynamic, maximum as dynamic, whole as boolean) as dynamic
    kind = Type(value)
    if kind <> "Integer" and kind <> "roInt" and kind <> "roInteger" and kind <> "LongInteger" and kind <> "roLongInteger" and kind <> "roInt64" and kind <> "Float" and kind <> "roFloat" and kind <> "Double" and kind <> "roDouble" then return invalid
    ' Return a scalar even if Roku supplies a boxed numeric interface. Double
    ' arithmetic preserves every integer in this helper's bounded range.
    value = value + 0#
    ' Comparisons reject NaN and infinities as well as out-of-range values.
    if value >= minimum and value <= maximum
        if not whole then return value
        if Int(value) = value then return value
    end if
    return invalid
end function

function NetworkHealth_ConnectionType(value as dynamic) as dynamic
    if GetInterface(value, "ifString") = invalid then return invalid
    if value = "WiFiConnection" or value = "WiredConnection" then return value
    if value = "" then return "none"
    return invalid
end function

function NetworkHealth_Protocol(value as dynamic) as dynamic
    if GetInterface(value, "ifString") = invalid then return invalid
    if Len(value) > 16 then return invalid
    protocol = LCase(value.Trim())
    if Left(protocol, 5) = "ieee " then protocol = Mid(protocol, 6)
    for each allowed in ["802.11a", "802.11b", "802.11g", "802.11n", "802.11ac", "802.11ax", "802.11be", "802.11ad", "802.11ay"]
        if protocol = allowed then return allowed
    end for
    return invalid
end function

function NetworkHealth_MemoryLevel(value as dynamic) as dynamic
    if GetInterface(value, "ifString") = invalid then return invalid
    if value = "normal" or value = "low" or value = "critical" then return value
    return invalid
end function
