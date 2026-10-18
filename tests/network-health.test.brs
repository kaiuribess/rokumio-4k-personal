function NetworkFixtureDevice(info as dynamic) as object
    return {
        info:info
        memory:"normal"
        connectionCalls:0
        memoryCalls:0
        failConnection:false
        failMemory:false
        GetConnectionInfo:function() as dynamic
            m.connectionCalls = m.connectionCalls + 1
            if m.failConnection then throw "private-fixture-error"
            return m.info
        end function
        GetGeneralMemoryLevel:function() as dynamic
            m.memoryCalls = m.memoryCalls + 1
            if m.failMemory then throw "private-fixture-memory-error"
            return m.memory
        end function
    }
end function

function NetworkFixtureReadDevice() as dynamic
    return m.networkFixtureDevice
end function

function NetworkFixtureAppInfo() as object
    return {GetVersion:function() as string
        return "fixture-version"
    end function}
end function

sub Main()
    Harness_Suite("Passive native connection reader, bounded cache and redaction")
    NetworkHealth_Reset()
    native = {type:"WiFiConnection",protocol:"IEEE 802.11ac",signal:-52,txFailed:12,txRetries:35,expectedThroughput:65000,ssid:"private-fixture-network",ip:"192.0.2.12",gateway:"192.0.2.1",dns:{token:"private-fixture-token"},url:"https://media.example/private-fixture",mac:"fixture-identifier"}
    device = NetworkFixtureDevice(native)
    status = NetworkHealth_Read(device, 100)
    Harness_Ok(status.available,"valid connection response is available")
    Harness_Equal(status.connectionType,"WiFiConnection","connection enum is preserved")
    Harness_Equal(status.protocol,"802.11ac","protocol is normalized to a fixed enum")
    Harness_Equal(status.signal,-52,"RSSI is preserved without a guessed threshold")
    Harness_Equal(status.expectedThroughputNative,65000,"native rate remains unscaled")
    Harness_Equal(status.expectedThroughputUnits,"unspecified","unknown rate units are explicit")
    Harness_Equal(status.memoryLevel,"normal","documented memory enum is read independently")
    Harness_Equal(status.counterStatus,"baseline","first counters establish only a baseline")
    Harness_Ok(not status.counterDeltaAvailable,"first sample cannot imply zero loss")
    Harness_Equal(status.txFailedDelta,invalid,"first delta is unknown")
    Harness_Equal(status.sampleAgeSeconds,0,"fresh sample has zero age")
    Harness_Equal(status.Count(),15,"only the fixed scalar allowlist is returned")
    Harness_Equal(device.connectionCalls,1,"exactly one native connection query")
    Harness_Equal(device.memoryCalls,1,"exactly one native memory query")
    Harness_Ok(FormatJson(status).InStr("private-fixture") < 0,"returned status contains no identifiers or arbitrary text")
    Harness_Ok(FormatJson(m.networkHealthCache).InStr("private-fixture") < 0,"cache contains no raw native record")
    native.signal = -90
    status.signal = -1
    cached = NetworkHealth_Read(device, 109.5)
    Harness_Equal(cached.signal,-52,"input and output mutations cannot corrupt the cached scalar")
    Harness_Equal(cached.sampleAgeSeconds,9.5,"cache exposes sample age")
    Harness_Equal(device.connectionCalls,1,"repeated status polls reuse the ten-second cache")
    Harness_Equal(device.memoryCalls,1,"memory query is cached too")
    native.txFailed = 14:native.txRetries = 45
    fresh = NetworkHealth_Read(device, 110)
    Harness_Equal(device.connectionCalls,2,"exact ten-second boundary refreshes once")
    Harness_Equal(fresh.signal,-90,"refresh replaces the prior native value")
    Harness_Ok(fresh.counterDeltaAvailable,"monotonic same-type samples provide a bounded delta")
    Harness_Equal(fresh.txFailedDelta,2,"dropped-frame delta is a count")
    Harness_Equal(fresh.txRetriesDelta,10,"retry delta is a separate count")
    Harness_Equal(fresh.elapsedSeconds,10,"delta exposes its measurement interval")
    Harness_Equal(fresh.counterStatus,"monotonic-same-type","delta does not claim unchanged access point or source speed")

    Harness_Suite("Counter reset, reconnect, missing values and clock discontinuity")
    native.txFailed = 1:native.txRetries = 3
    reset = NetworkHealth_Read(device,120)
    Harness_Ok(not reset.counterDeltaAvailable,"decreased counter is not a negative delta")
    Harness_Equal(reset.counterStatus,"reset-or-wrap","reset or wrap remains explicitly uncertain")
    Harness_Equal(reset.elapsedSeconds,invalid,"counter reset has no valid interval result")
    native.txFailed = 2:native.txRetries = 4
    after = NetworkHealth_Read(device,130)
    Harness_Equal(after.txFailedDelta,1,"next monotonic sample uses the reset baseline")
    native.type = "WiredConnection"
    changed = NetworkHealth_Read(device,140)
    Harness_Ok(not changed.counterDeltaAvailable,"connection-type transition invalidates the comparison")
    Harness_Equal(changed.counterStatus,"connection-type-changed","type transition is visible")
    Harness_Equal(changed.signal,invalid,"wire connection does not repeat stale Wi-Fi RSSI")
    Harness_Equal(changed.protocol,invalid,"wire connection does not repeat stale Wi-Fi protocol")
    native.txFailed = invalid
    missing = NetworkHealth_Read(device,150)
    Harness_Equal(missing.counterStatus,"unknown","missing counter is not guessed from previous sample")
    native.txFailed = 20:native.txRetries = 50
    baseline = NetworkHealth_Read(device,160)
    Harness_Ok(not baseline.counterDeltaAvailable,"missing previous counter forces a new baseline")
    rollback = NetworkHealth_Read(device,1)
    Harness_Ok(not rollback.counterDeltaAvailable,"clock rollback discards the earlier counter interval")
    Harness_Equal(rollback.counterStatus,"baseline","rollback re-establishes a baseline")
    same = NetworkHealth_Read(device,11)
    Harness_Equal(same.txFailedDelta,0,"valid unchanged counters report a real zero count")
    Harness_Equal(same.txRetriesDelta,0,"valid unchanged retry counters report zero")

    Harness_Suite("Native API failure, malformed data and recovery remain honest")
    device.failConnection = true:device.memory = "low"
    failed = NetworkHealth_Read(device,21)
    Harness_Ok(not failed.available,"native query exception reports unknown connection")
    Harness_Equal(failed.signal,invalid,"failure clears previously healthy signal")
    Harness_Equal(failed.memoryLevel,"low","memory reader still works when connection query fails")
    Harness_Ok(FormatJson(failed).InStr("private-fixture") < 0,"native exception details are never returned")
    failedCalls = device.connectionCalls
    NetworkHealth_Read(device,29)
    Harness_Equal(device.connectionCalls,failedCalls,"failed query also has the ten-second throttle")
    device.failConnection = false:device.failMemory = true
    recovered = NetworkHealth_Read(device,31)
    Harness_Ok(recovered.available,"connection can recover after query failure")
    Harness_Ok(not recovered.counterDeltaAvailable,"counter comparison cannot span a failed sample")
    Harness_Equal(recovered.memoryLevel,invalid,"independent memory exception remains unknown")
    for each malformed in [invalid,[],"private-fixture-text",12,true,{}]
        NetworkHealth_Reset()
        device.info = malformed
        unknown = NetworkHealth_Read(device,100)
        Harness_Ok(not unknown.available,"malformed native response stays unavailable")
        Harness_Equal(unknown.txFailed,invalid,"malformed response has no counter")
    end for
    NetworkHealth_Reset()
    device.info = {type:"WiFiConnection",protocol:"private-fixture-protocol",signal:"-45",txFailed:1.5,txRetries:-1,expectedThroughput:true}
    unknown = NetworkHealth_Read(device,100)
    Harness_Equal(unknown.protocol,invalid,"arbitrary protocol text is rejected")
    Harness_Equal(unknown.signal,invalid,"numeric strings are not native RSSI")
    Harness_Equal(unknown.txFailed,invalid,"fractional counters remain unknown")
    Harness_Equal(unknown.txRetries,invalid,"negative counters remain unknown")
    Harness_Equal(unknown.expectedThroughputNative,invalid,"boolean is not a native rate")

    Harness_Suite("Numeric and enum boundaries, unavailable clock and teardown")
    for each bad in [invalid,true,"12",{},[],-1,2147483648.0,1.5]
        Harness_Equal(NetworkHealth_Number(bad,0,2147483647,true),invalid,"malformed or overflowing integer counters are rejected")
    end for
    Harness_Equal(NetworkHealth_Number(0,0,2147483647,true),0,"zero counter is valid")
    Harness_Equal(NetworkHealth_Number(2147483647,0,2147483647,true),2147483647,"bounded integer maximum is valid")
    Harness_Equal(NetworkHealth_Number(275&,0,2147483647,true),275,"native64-bit counter is preserved")
    boxedCounter = CreateObject("roLongInteger")
    boxedCounter.SetLongInt(275&)
    Harness_Equal(NetworkHealth_Number(boxedCounter,0,2147483647,true),275,"boxed64-bit counter becomes a safe scalar")
    Harness_Equal(NetworkHealth_Number(2147483648&,0,2147483647,true),invalid,"native64-bit overflow stays unknown")
    Harness_Equal(NetworkHealth_Number(-100,-100,0,false),-100,"RSSI lower boundary is retained")
    Harness_Equal(NetworkHealth_Number(0,-100,0,false),0,"RSSI upper boundary is retained")
    Harness_Equal(NetworkHealth_Number(-101,-100,0,false),invalid,"out-of-range RSSI stays unknown")
    Harness_Equal(NetworkHealth_Protocol("802.11ax"),"802.11ax","modern protocol stays allowlisted")
    Harness_Equal(NetworkHealth_ConnectionType(""),"none","explicit no-connection response stays distinct from unavailable")
    Harness_Equal(NetworkHealth_ConnectionType("private-fixture-type"),invalid,"arbitrary connection type is rejected")
    for each level in ["normal","low","critical"]
        Harness_Equal(NetworkHealth_MemoryLevel(level),level,"documented memory level survives sanitizing")
    end for
    for each level in ["private-fixture-memory",invalid,1,{},[]]
        Harness_Equal(NetworkHealth_MemoryLevel(level),invalid,"unexpected memory field is unknown")
    end for
    calls = device.connectionCalls
    invalidClock = NetworkHealth_Read(device,-1)
    Harness_Ok(not invalidClock.available,"unusable timer cannot produce a fresh sample")
    Harness_Equal(device.connectionCalls,calls,"invalid clock never creates unbounded native polling")
    NetworkHealth_Reset()
    Harness_Equal(m.networkHealthCache,invalid,"teardown clears sanitized cache")
    Harness_Equal(m.networkHealthSampleTime,invalid,"teardown clears sample timestamp")
    Harness_Equal(m.networkHealthClock,invalid,"teardown clears timer")

    Harness_Suite("Real playback-status boundary exposes only cached passive facts")
    m.networkFixtureDevice = NetworkFixtureDevice({type:"WiFiConnection",protocol:"802.11ac",signal:-54,txFailed:7,txRetries:30,expectedThroughput:42000,ssid:"private-fixture-network",url:"https://media.example/private-fixture"})
    m.networkHealthClock = {milliseconds:0,TotalMilliseconds:function() as integer
        return m.milliseconds
    end function}
    m.playerScreen = {callFunc:function(name as string) as object
        return {state:"playing"}
    end function}
    m.streamsScreen = {callFunc:function(name as string) as object
        return {pending:0}
    end function}
    exported = ReadPlaybackDiagnostic()
    Harness_Ok(exported.network.available,"real status callback reads the production helper")
    Harness_Equal(exported.network.signal,-54,"native scalar crosses the public status boundary")
    Harness_Equal(exported.playback.state,"playing","native fact read leaves playback state untouched")
    Harness_Equal(exported.sources.pending,0,"source loading status is preserved")
    Harness_Equal(m.networkFixtureDevice.connectionCalls,1,"status callback performs one bounded native query")
    Harness_Ok(FormatJson(exported).InStr("private-fixture") < 0,"complete status response contains no native identifiers")
    exported.network.signal = -1
    m.networkHealthClock.milliseconds = 3000
    again = ReadPlaybackDiagnostic()
    Harness_Equal(again.network.signal,-54,"status response cannot mutate cached network facts")
    Harness_Equal(again.network.sampleAgeSeconds,3,"real status exposes cached sample age")
    Harness_Equal(m.networkFixtureDevice.connectionCalls,1,"repeated status request cannot force a Wi-Fi read")
    m.networkHealthClock.milliseconds = 10000
    m.networkFixtureDevice.info.txRetries = 33
    later = ReadPlaybackDiagnostic()
    Harness_Equal(later.network.txRetriesDelta,3,"real status callback delivers only fresh monotonic interval counts")
    Harness_Equal(later.network.elapsedSeconds,10,"status interval tracks the passive cache clock")
    Harness_Equal(m.networkFixtureDevice.connectionCalls,2,"real status refreshes after ten seconds")
    Harness_Finish()
end sub
