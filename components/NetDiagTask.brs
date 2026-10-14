' NetDiagTask — TEMPORARY network probe. See NetDiagTask.xml.
'
' Why this exists: outbound requests intermittently fail with status=-7 ("Could
' not connect to server") in tens of milliseconds — a refusal, not a slow link or
' a timeout. Rung A (the LAN streaming server, IP literal) is the known-good
' baseline and answers reliably; the WAN rungs are the ones that drop.
'
' A wired run produced this measurement, which should be read as a measurement
' and nothing more:
'
'   versions  AUTO 5/6, http2 5/6, 1.1 6/6 at burst width 6.
'   sweep     clean to 2 wide, first loss at 3.
'   soak      12/12 sequential.
'
' It was first read as proof that the HTTP version was the mechanism: AUTO
' negotiates HTTP/2, which shares one connection across transfers; Roku's docs
' require every transfer on a shared connection to come from the SAME thread,
' and the app issues from many Task threads at once. That reading did not
' replicate — a second run was clean at every width and for every version — and
' the -7s behind the first run turned out to be the device overheating.
' Transport.bs does not pin the version and should not be given one on this
' evidence: a spread of one transfer on a six-wide burst is noise-sized, and
' "1.1" is not among the values Roku documents for SetHttpVersion ("http2" and
' "AUTO" are), so a clean 1.1 is equally consistent with the string being
' ignored outright. The comparison stays because it is still the cheapest way
' to separate connection sharing from a bad link.
'
' Two earlier conclusions were wrong and are retracted, because both were drawn
' from a probe whose verdict could not tell them apart:
'
'   "DNS is not the cause" — the resolver answering 3/3 does show resolution
'   works, but the claim rested on B (the IP literal) coming back connected, and
'   `connected` was `status <> 0`, which counts a -7 as connected. B was failing.
'   The DNS verdict now only speaks when one of B/C connects and the other does
'   not, and reports both-red as inconclusive instead of blaming DNS.
'
'   "The CA bundle is not the fix / might be the fix" — D vs E only compares
'   certificate outcomes when D and E both got a RESPONSE. A -7 is the TCP
'   connect refused before any handshake, so a bundle cannot explain it, and
'   "CA bundle fixes HTTPS" was once emitted off a rung that never connected.
'   That recommendation would have added SetCertificatesFile to Transport for a
'   connection that was never made.
'
' What was left is the shape the failures cluster in: one sequential request is
' reliable, but the same request under six-at-once, or alongside the app's own
' parallel startup tasks, fails. So this version measures CONCURRENCY directly:
'
'   dev      roDeviceInfo verbatim (RSSI, txFailed, protocol, gateway, DNS
'            servers), link/internet status, and whether the device has wired
'            hardware. Names the radio quality and the resolver in use.
'   A-E      the five-rung sequential ladder below.
'   dns      explicit resolution of each host, three times.
'   soak     N sequential requests, nothing else in flight. If these all pass,
'            single connections are reliable and the problem is concurrency;
'            if some fail, the link itself drops under no load.
'   sweep    bursts of 1/2/3/4/6/8 at once, drained between, to find the size at
'            which connections start dropping.
'   versions the size-6 burst under AUTO (default), forced "http2" (connection
'            sharing on one connection), and forced "1.1" (one connection per
'            transfer). Roku's docs say HTTP/2 sharing requires all transfers
'            from the same thread; the app issues from many Task threads.
'
' The probe ladder (A..E) is a control ladder, each rung changing ONE thing:
'
'   A  LAN, plain HTTP, IP literal        known-good baseline
'   B  WAN, plain HTTP, IP literal        internet reachable WITHOUT DNS
'   C  WAN, plain HTTP, hostname          internet reachable WITH DNS
'   D  WAN, HTTPS, hostname, no CA bundle how the app behaves today
'   E  WAN, HTTPS, hostname, + CA bundle  the certificate hypothesis
'
' B against C isolates DNS, and D against E isolates certificates — but ONLY when
' the pair differs in the way it is meant to. Both-red says nothing about DNS, and
' a rung that failed to connect says nothing about certificates; the verdict below
' reports those as inconclusive instead of reading intent into them.
'
' Everything is self-contained so it can be deleted in one move: no probe goes
' through Transport, and every probe builds its own roUrlTransfer.

' Roku's documented shared root bundle for public CAs. Reached through
' CABundlePath() rather than duplicated, so the path the probe applies and the
' path the verdict names cannot drift apart.
function CABundlePath() as string
    return "common:/certs/ca-bundle.crt"
end function

' The one host every load test targets. Same URL as probe D, so a soak/sweep
' result is directly comparable to the sequential rung that always passed.
function TargetUrl() as string
    return "https://v3-cinemeta.strem.io/manifest.json"
end function

sub init()
    m.top.functionName = "runProbes"
end sub

sub runProbes()
    report = {
        done: false
        lines: []
        probes: []
        summary: "Running..."
        verdict: ""
        device: {}
        dns: []
        soak: {}
        sweep: []
        versions: []
    }
    m.top.result = report
    Say("start: dev + A-E + dns + soak + sweep + versions")

    ' Device facts first. If the radio is the problem this is already most of
    ' the answer, and it is the only place the resolver in use is visible.
    report.device = RunDeviceInfo()
    m.top.result = report

    probes = BuildProbes()
    for each probe in probes
        ' Bail between probes so cancelling does not cost another full timeout
        ' per remaining probe.
        if m.top.cancelRequested then
            report.verdict = "cancelled"
            report.summary = "cancelled after " + report.lines.Count().ToStr() + " probe(s)"
            report.done = true
            m.top.result = report
            return
        end if

        ' A beat between probes so a failure belongs to this probe and not to
        ' the keep-alive state of the one before it.
        Wait(Rnd(1200) + 400, invalid)

        if probe.skip <> "" then
            outcome = SkippedOutcome(probe)
        else
            ' A throw inside a probe used to kill the whole task and leave the
            ' rest unreported — which is exactly what calling the non-existent
            ' SetHttpFollowRedirect did on the device. A diagnostic has to
            ' survive its own faults and still print what it learned.
            try
                outcome = RunProbe(probe)
            catch e
                outcome = FaultedOutcome(probe, e)
            end try
        end if
        report.lines.Push(Describe(outcome))
        report.probes.Push(outcome)
        report.summary = Summarize(report.probes)
        m.top.result = report
        Say(report.lines[report.lines.Count() - 1])
    end for

    ' Explicit DNS measurement, independent of any HTTP transfer.
    report.dns = RunDnsChecks()
    m.top.result = report

    ' Sequential soak, nothing else in flight: link reliability without load.
    report.soak = RunSoak(TargetUrl(), 12)
    m.top.result = report

    ' Concurrency sweep: the size at which connections start dropping.
    report.sweep = RunBurstSweep(TargetUrl())
    m.top.result = report

    ' HTTP-version comparison: AUTO vs shared-HTTP/2 vs one-connection-per-xfer.
    report.versions = RunHttpVersionComparison(TargetUrl())

    report.summary = Summarize(report.probes)
    report.verdict = Verdict(report.probes, report.dns, report.soak, report.sweep, report.versions)
    report.done = true
    m.top.result = report

    Say("result: " + report.summary)
    Say("soak: " + SoakText(report.soak))
    Say("sweep: " + SweepText(report.sweep))
    Say("versions: " + VersionsText(report.versions))
    Say("verdict: " + report.verdict)
end sub

' ----------------------------------------------------------------------------
' Device / connection facts
' ----------------------------------------------------------------------------

function RunDeviceInfo() as object
    record = {
        type: ""
        signal: ""
        txFailed: ""
        txRetries: ""
        protocol: ""
        ssid: ""
        ip: ""
        gateway: ""
        dns: ""
        ipv6: ""
        link: false
        internet: false
        ethernet: false
        raw: ""
        error: ""
    }
    try
        di = CreateObject("roDeviceInfo")
        record.type = BoxStr(di.GetConnectionType())
        record.link = di.GetLinkStatus()
        try
            record.internet = di.GetInternetStatus()
        catch e
        end try
        try
            record.ethernet = di.HasFeature("ethernet_hardware")
        catch e
        end try

        info = di.GetConnectionInfo()
        if info <> invalid then
            ' Dump the whole assocarray once. Guessing key names and case is how
            ' the first version printed an all-empty dev line even though the
            ' platform call had clearly succeeded — the raw dump cannot be
            ' wrong about what the device returned.
            try
                record.raw = FormatJson(info)
            catch e
                record.raw = "(FormatJson failed)"
            end try

            if info.DoesExist("signal") then record.signal = BoxStr(info.signal)
            if info.DoesExist("txFailed") then record.txFailed = BoxStr(info.txFailed)
            if info.DoesExist("txRetries") then record.txRetries = BoxStr(info.txRetries)
            if info.DoesExist("protocol") then record.protocol = BoxStr(info.protocol)
            if info.DoesExist("ssid") then record.ssid = BoxStr(info.ssid)
            if info.DoesExist("ip") then record.ip = BoxStr(info.ip)
            if info.DoesExist("gateway") then record.gateway = BoxStr(info.gateway)

            ' DNS server keys are dns.0, dns.1, ... (zero-based), so walk from 0
            ' until one is missing. The first version started at 1 and reported
            ' an empty resolver list on a device that plainly had one.
            servers = []
            serverIndex = 0
            while info.DoesExist("dns." + serverIndex.ToStr())
                servers.Push(BoxStr(info["dns." + serverIndex.ToStr()]))
                serverIndex = serverIndex + 1
            end while
            record.dns = Join(servers, ",")

            if info.DoesExist("ipv6") then
                v6 = info.ipv6
                if Type(v6) = "roArray" then record.ipv6 = Join(v6, ",")
            end if
        end if
    catch e
        message = e.message
        if message = invalid then message = "unknown"
        record.error = "device info: " + message
    end try

    Say("dev type=" + record.type + " link=" + BoxStr(record.link) + " internet=" + BoxStr(record.internet) + " ethernet=" + BoxStr(record.ethernet) + " signal=" + record.signal + " txFailed=" + record.txFailed + " protocol=" + record.protocol + " ip=" + record.ip + " gateway=" + record.gateway + " dns=[" + record.dns + "] ipv6=[" + record.ipv6 + "]")
    if record.error <> "" then Say("dev error=[" + record.error + "]")
    if record.raw <> "" then Say("dev raw=" + record.raw)
    return record
end function

' ----------------------------------------------------------------------------
' The sequential probe ladder
' ----------------------------------------------------------------------------

function BuildProbes() as object
    address = TrimBox(m.top.serverAddress)
    probes = []
    if address = "" then
        probes.Push({
            tag: "A"
            label: "LAN http (IP)"
            url: ""
            certs: false
            skip: "skipped: no streaming server address set"
        })
    else
        probes.Push({
            tag: "A"
            label: "LAN http (IP)"
            url: address + "/heartbeat"
            certs: false
            skip: ""
        })
    end if
    ' B is a bare IP literal: no DNS in the path. Cloudflare's 1.1.1.1 answers
    ' plain HTTP and has a valid certificate for the redirect target, so this
    ' measures "can we reach the internet at all without asking a resolver".
    probes.Push({ tag: "B", label: "net http (IP 1.1.1.1)", url: "http://1.1.1.1/", certs: false, skip: "" })
    ' C is the same kind of request, same port, but by hostname. B vs C is the
    ' DNS comparison.
    probes.Push({ tag: "C", label: "net http (host)", url: "http://httpforever.com/", certs: false, skip: "" })
    ' D and E differ in exactly one call. E is the certificate hypothesis.
    probes.Push({ tag: "D", label: "net https (host, no CA)", url: TargetUrl(), certs: false, skip: "" })
    probes.Push({ tag: "E", label: "net https (host, +CA)", url: TargetUrl(), certs: true, skip: "" })
    return probes
end function

' One blocking GET on its own transfer and port. roUrlTransfer is not
' re-entrant, so each probe gets its own pair — the same reason Transport builds
' a fresh transfer per request. GET follows redirects on its own and there is no
' API to stop it (ifUrlTransfer exposes none), so "connected" is judged on a
' response having arrived rather than on 2xx: a redirect that was answered still
' proves the socket opened, which is all B needs.
'
' NetDiagConnected is that decision, kept as its own function because it is the
' one piece of RunProbe that decides the whole DNS verdict, and RunProbe needs a
' live roUrlTransfer — as an inline expression it was unreachable without one,
' which is how it stayed wrong. It was `status <> 0`, which counts
' CURLE_COULDNT_CONNECT (-7) — a connection that never opened — as connected, so
' a wired run where BOTH the IP-literal and hostname probes came back -7 still
' reported the internet as reachable and closed the DNS question on a probe that
' had failed.
'
' The comparison has to exclude zero AND negatives: a real HTTP response code is
' always >= 100, while a redirect answered on the way to a 2xx still counts.
function NetDiagConnected(status as integer) as boolean
    return status > 0
end function

function RunProbe(probe as object) as object
    outcome = OutcomeRecord(probe)

    transfer = CreateObject("roUrlTransfer")
    if not transfer.SetUrl(probe.url)
        outcome.error = "SetUrl rejected the url"
        return outcome
    end if

    if probe.certs then
        ' Recorded either way: "the bundle could not be applied" and "the bundle
        ' was applied and it still failed" are different answers, and a silent
        ' failure here would collapse them into one.
        applied = false
        try
            applied = transfer.SetCertificatesFile(CABundlePath())
        catch e
            applied = false
        end try
        if applied then
            outcome.certsOk = "applied"
        else
            outcome.certsOk = "CALL FAILED"
        end if
    end if

    transfer.RetainBodyOnError(true)
    port = CreateObject("roMessagePort")
    transfer.SetMessagePort(port)

    if not transfer.AsyncGetToString()
        outcome.error = "request could not be issued"
        return outcome
    end if

    event = Wait(5000, port)
    if event = invalid
        transfer.AsyncCancel()
        outcome.error = "request timed out"
        return outcome
    end if
    if Type(event) <> "roUrlEvent"
        outcome.error = "unexpected port message"
        return outcome
    end if

    outcome.status = event.GetResponseCode()
    outcome.ok = outcome.status >= 200 and outcome.status < 300
    ' A NEGATIVE status is the transfer never completing: the socket never
    ' opened. CURLE_COULDNT_CONNECT (-7) is what this device returns, and it is
    ' non-zero, so `status <> 0` counted it as connected — which is how a run
    ' where both the IP-literal and hostname probes came back -7 still printed
    ' "Both IP and hostname reach the internet".
    '
    ' The comparison has to be against 0 with status strictly positive: a real
    ' HTTP response code is always >= 100, and a redirect answered on the way to
    ' a 2xx still counts, which is all B needs to prove the socket opened.
    outcome.connected = NetDiagConnected(outcome.status)
    if not outcome.ok
        if outcome.status < 0
            reason = event.GetFailureReason()
            if reason = invalid or reason = "" then reason = "transfer failed"
            outcome.error = reason
        else
            outcome.error = "HTTP " + outcome.status.ToStr()
        end if
    end if
    return outcome
end function

' ----------------------------------------------------------------------------
' Explicit DNS resolution, independent of HTTP
' ----------------------------------------------------------------------------

' Resolve each host three times and count how many attempts yielded an address.
' This is the same lookup roUrlTransfer performs internally, through the same
' stack (roSocketAddress is IPv4-only, which is also all roUrlTransfer uses), so
' a flaky count here is DNS failing before any HTTP is involved.
function RunDnsChecks() as object
    hosts = ["v3-cinemeta.strem.io", "httpforever.com", "opensubtitles-v3.strem.io"]
    records = []
    for each host in hosts
        attempts = 3
        successes = 0
        ips = []
        for i = 1 to attempts
            resolved = ResolveOnce(host)
            if resolved.ok then
                successes = successes + 1
                ips.Push(resolved.ip)
            end if
        end for
        record = { host: host, attempts: attempts, ok: successes, ips: Join(ips, ",") }
        records.Push(record)
        Say("dns " + host + " ok=" + successes.ToStr() + "/" + attempts.ToStr() + " ips=[" + record.ips + "]")
    end for
    return records
end function

function ResolveOnce(host as string) as object
    result = { ok: false, ip: "" }
    try
        addr = CreateObject("roSocketAddress")
        addr.SetAddress(host)
        if addr.IsAddressValid() then
            result.ok = true
            result.ip = BoxStr(addr.GetAddress())
        end if
    catch e
        result.ok = false
    end try
    return result
end function

' ----------------------------------------------------------------------------
' Sequential soak
' ----------------------------------------------------------------------------

' count single requests, a beat apart, with nothing else in flight. The whole
' point is to remove concurrency: if this is clean, the link is fine when asked
' for one connection at a time and every failure under load is contention. If
' some of these fail, the radio itself is dropping connections and no amount of
' app-side serialization will fix it.
function RunSoak(url as string, count as integer) as object
    record = { url: url, count: count, ok: 0, statuses: "", error: "" }
    collected = []
    for i = 1 to count
        probe = { tag: "S" + i.ToStr(), label: "soak", url: url, certs: false, skip: "" }
        outcome = invalid
        try
            outcome = RunProbe(probe)
        catch e
            outcome = FaultedOutcome(probe, e)
        end try
        if outcome.ok then record.ok = record.ok + 1
        collected.Push(outcome.status.ToStr())
        Say("soak " + i.ToStr() + "/" + count.ToStr() + " status=" + outcome.status.ToStr() + " " + outcome.error)
        Wait(350, invalid)
    end for
    record.statuses = Join(collected, ",")
    return record
end function

' ----------------------------------------------------------------------------
' Concurrency burst
' ----------------------------------------------------------------------------

' Issue count transfers to one URL at once, all parked on one port, then drain
' every event. The app's failures cluster when several tasks are live together,
' so if the network can carry several simultaneous requests without loss then
' the problem is contention inside the app, not the link.
'
' httpVersion left empty uses the platform default (AUTO). Passed explicitly, it
' is applied to each fresh transfer — SetHttpVersion must precede the instance's
' first transfer — and a rejected version is recorded rather than thrown, so an
' OS that refuses "1.1" still leaves the rest of the run intact.
function RunBurst(url as string, count as integer, httpVersion = "" as string) as object
    record = { url: url, version: httpVersion, count: 0, ok: 0, statuses: "", error: "" }
    if url = "" then
        record.error = "no url"
        return record
    end if

    port = CreateObject("roMessagePort")
    ' Every transfer must stay referenced until its event arrives — an
    ' roUrlTransfer that goes out of scope cancels its own transfer.
    transfers = []
    statuses = []
    successes = 0

    for i = 1 to count
        transfer = CreateObject("roUrlTransfer")
        if httpVersion <> "" then
            rejected = false
            try
                transfer.SetHttpVersion(httpVersion)
            catch e
                rejected = true
            end try
            if rejected then
                record.error = "SetHttpVersion(" + httpVersion + ") rejected"
                record.count = transfers.Count()
                record.statuses = Join(statuses, ",")
                return record
            end if
        end if
        transfer.SetUrl(url)
        transfer.RetainBodyOnError(true)
        transfer.SetMessagePort(port)
        if transfer.AsyncGetToString() then transfers.Push(transfer)
    end for

    issued = transfers.Count()
    record.count = issued
    for i = 1 to issued
        event = Wait(5000, port)
        if event <> invalid and Type(event) = "roUrlEvent" then
            code = event.GetResponseCode()
            statuses.Push(code.ToStr())
            if code >= 200 and code < 300 then successes = successes + 1
        else
            statuses.Push("timeout")
        end if
    end for
    record.ok = successes
    record.statuses = Join(statuses, ",")
    Say("burst ver=" + VersionLabel(httpVersion) + " n=" + issued.ToStr() + " ok=" + successes.ToStr() + " [" + record.statuses + "]")
    return record
end function

' ----------------------------------------------------------------------------
' Burst size sweep and HTTP-version comparison
' ----------------------------------------------------------------------------

' Sizes from one up to eight, each from a drained state. A single size that
' succeeds proves the host is reachable; the first size that loses transfers is
' the concurrency threshold this device can sustain.
function RunBurstSweep(url as string) as object
    sizes = [1, 2, 3, 4, 6, 8]
    records = []
    for each size in sizes
        ' Drain between bursts, otherwise a burst inherits the previous burst's
        ' half-closed sockets and the sweep measures recovery time instead of
        ' the threshold.
        Wait(1200, invalid)
        records.Push(RunBurst(url, size))
    end for
    return records
end function

' The same size-6 burst under three transfer configurations. AUTO is the
' platform default. "http2" enables the connection-sharing feature, which Roku
' documents as requiring all transfers to originate from one thread — true here
' and false in the app. "1.1" forces a separate connection per transfer. The
' difference between these three is the cleanest read on whether the failures
' are too many simultaneous connections or HTTP/2 sharing gone wrong.
function RunHttpVersionComparison(url as string) as object
    versions = ["AUTO", "http2", "1.1"]
    records = []
    for each version in versions
        Wait(1200, invalid)
        records.Push(RunBurst(url, 6, version))
    end for
    return records
end function

' ----------------------------------------------------------------------------
' Reporting
' ----------------------------------------------------------------------------

function Describe(outcome as object) as string
    text = outcome.tag + " " + outcome.label + " status=" + outcome.status.ToStr()
    if outcome.certs then text = text + " certs=" + outcome.certsOk
    if outcome.error <> "" then text = text + " error=[" + outcome.error + "]"
    return text
end function

' The compact "A=200 B=200 C=-7 D=-7 E=200" form, which is the whole ladder on
' one line.
function Summarize(probes as object) as string
    parts = []
    for each probe in probes
        if probe.skipped then
            parts.Push(probe.tag + "=skip")
        else
            parts.Push(probe.tag + "=" + probe.status.ToStr())
        end if
    end for
    return Join(parts, "  ")
end function

function SoakText(soak as object) as string
    if soak = invalid or soak.count = 0 then return "(none)"
    return soak.ok.ToStr() + "/" + soak.count.ToStr()
end function

function SweepText(sweep as object) as string
    parts = []
    for each record in sweep
        parts.Push(record.count.ToStr() + ":" + record.ok.ToStr())
    end for
    return Join(parts, " ")
end function

function VersionsText(versions as object) as string
    parts = []
    for each record in versions
        text = VersionLabel(record.version) + " " + record.ok.ToStr() + "/" + record.count.ToStr()
        if record.error <> "" then text = text + " (" + record.error + ")"
        parts.Push(text)
    end for
    return Join(parts, "  ")
end function

function VersionLabel(httpVersion as string) as string
    if httpVersion = "" then return "auto"
    return httpVersion
end function

function FindVersion(versions as object, version as string) as object
    for each record in versions
        if record.version = version then return record
    end for
    return invalid
end function

function Join(parts as object, glue as string) as string
    out = ""
    for each part in parts
        if out <> "" then out = out + glue
        out = out + part
    end for
    return out
end function

' The interpretation, built from the records rather than from the printed text.
function Verdict(probes as object, dns as object, soak as object, sweep as object, versions as object) as string
    byTag = {}
    for each probe in probes
        byTag[probe.tag] = probe
    end for

    b = invalid
    c = invalid
    d = invalid
    e = invalid
    if byTag.DoesExist("B") then b = byTag["B"]
    if byTag.DoesExist("C") then c = byTag["C"]
    if byTag.DoesExist("D") then d = byTag["D"]
    if byTag.DoesExist("E") then e = byTag["E"]

    parts = []

    ' DNS: B is IP literal, C is hostname. The comparison is only meaningful when
    ' one connects and the other does not. Both-green proves reachability; both-red
    ' says nothing about DNS at all — an unreachable internet blocks the IP probe
    ' and the hostname probe equally — so it must not be reported as a DNS result,
    ' and previously it was, because a -7 counted as connected.
    if b <> invalid and c <> invalid then
        if b.connected and not c.connected then
            parts.Push("IP literal works, hostname does not -> DNS.")
        else if b.connected and c.connected then
            parts.Push("Both IP and hostname reach the internet.")
        else if not b.connected and not c.connected then
            parts.Push("Neither IP nor hostname connected -> not DNS; see the http versions below.")
        end if
    end if

    dnsFailures = 0
    dnsAttempts = 0
    for each record in dns
        if record.attempts > 0 then
            dnsAttempts = dnsAttempts + record.attempts
            dnsFailures = dnsFailures + (record.attempts - record.ok)
        end if
    end for
    if dnsAttempts > 0 then
        if dnsFailures > 0 then
            parts.Push("resolver failed " + dnsFailures.ToStr() + "/" + dnsAttempts.ToStr() + " lookups.")
        else
            parts.Push("resolver answered every lookup.")
        end if
    end if

    ' Certificates: D is no bundle, E is bundle.
    '
    ' Only a TLS-level answer can say anything about certificates. A negative
    ' status is the TCP connect refused BEFORE any handshake, so a bundle cannot
    ' possibly be what changed the outcome — certificate validation does not
    ' exist yet at that point. Reading "D=-7, E=200" as "the bundle fixes HTTPS"
    ' would send someone to add SetCertificatesFile to Transport for a connection
    ' that was never made, which is what this verdict did on a wired run.
    '
    ' A positive non-2xx (a TLS or HTTP-layer rejection) is a real answer and is
    ' compared as before.
    if d <> invalid and e <> invalid then
        dTls = d.status > 0
        eTls = e.status > 0
        if not dTls and not eTls then
            parts.Push("Both HTTPS probes failed before the handshake -> not certificates.")
        else if not dTls and eTls then
            parts.Push("CA bundle appears to fix HTTPS, but D never connected -> inconclusive, not certificates.")
        else if dTls and not eTls then
            parts.Push("D got a response and E never connected -> inconclusive, not certificates.")
        else
            if d.ok and e.ok then
                parts.Push("HTTPS works with and without a CA bundle -> not certificates.")
            else if not d.ok and not e.ok then
                parts.Push("HTTPS fails with and without a CA bundle -> not certificates.")
            else if d.ok and not e.ok then
                parts.Push("CA bundle BREAKS working HTTPS -> do not add it to Transport.")
            else
                parts.Push("CA bundle fixes an HTTPS-layer failure -> consider SetCertificatesFile in Transport.")
            end if
        end if
    end if

    ' Soak: the concurrency control.
    if soak <> invalid and soak.count > 0 then
        if soak.ok = soak.count then
            parts.Push("soak " + soak.ok.ToStr() + "/" + soak.count.ToStr() + " sequential -> single connections reliable, failures need load.")
        else
            parts.Push("soak lost " + (soak.count - soak.ok).ToStr() + "/" + soak.count.ToStr() + " sequential -> link drops with NO concurrency.")
        end if
    end if

    ' Sweep: the concurrency threshold.
    if sweep <> invalid and sweep.Count() > 0 then
        lastAllOk = -1
        firstLoss = -1
        for each record in sweep
            if record.count > 0 then
                if record.ok = record.count then
                    lastAllOk = record.count
                else if firstLoss = -1 then
                    firstLoss = record.count
                end if
            end if
        end for
        parts.Push("sweep " + SweepText(sweep) + " (largest clean=" + lastAllOk.ToStr() + ", first loss=" + firstLoss.ToStr() + ").")
    end if

    ' HTTP version: the mechanism test.
    if versions <> invalid and versions.Count() > 0 then
        parts.Push("http versions " + VersionsText(versions) + ".")
        autoRecord = FindVersion(versions, "AUTO")
        h2Record = FindVersion(versions, "http2")
        h1Record = FindVersion(versions, "1.1")
        if autoRecord <> invalid and h2Record <> invalid then
            if autoRecord.ok < autoRecord.count and h2Record.ok = h2Record.count then
                parts.Push("Forcing HTTP/2 recovered the burst -> connection sharing fixes the connects.")
            end if
        end if
        if h1Record <> invalid and h1Record.error <> "" then
            parts.Push("OS rejected HTTP/1.1 (" + h1Record.error + ").")
        else if h1Record <> invalid and h1Record.count > 0 then
            ' HTTP/1.1 is the actionable result and it used to be printed but never
            ' interpreted: AUTO and http2 both lost transfers on a wired run while
            ' 1.1 was clean, and the verdict said nothing about it.
            '
            ' 1.1 gives each transfer its own connection, so a clean burst here
            ' points at HTTP/2's shared-connection pool as what loses the
            ' connects. Report it as a finding, not as an instruction: the app
            ' does not pin the version, and it cannot be justified from this
            ' alone. Roku documents only "http2" and "AUTO" as accepted values
            ' for SetHttpVersion, so "1.1" is unverified, and a spread of one
            ' transfer on a six-wide burst is noise-sized.
            if h1Record.ok = h1Record.count and (autoRecord = invalid or autoRecord.ok < autoRecord.count) then
                parts.Push("HTTP/1.1 ran the burst clean while AUTO lost transfers -> the loss looks like HTTP/2 connection sharing rather than a bad link; re-run at a larger burst before treating the version as the cause.")
            else if h1Record.ok = h1Record.count and autoRecord <> invalid and autoRecord.ok = autoRecord.count then
                parts.Push("HTTP/1.1 and AUTO both ran clean at this width -> no version effect at this width; raise the burst to find it.")
            else if h1Record.ok < h1Record.count then
                parts.Push("HTTP/1.1 also lost transfers -> not the HTTP version; look at the sweep threshold.")
            end if
        end if
    end if

    if parts.Count() = 0 then return "inconclusive"
    return Join(parts, " ")
end function

function OutcomeRecord(probe as object) as object
    return {
        tag: probe.tag
        label: probe.label
        url: probe.url
        certs: probe.certs
        certsOk: ""
        connected: false
        ok: false
        status: 0
        error: ""
        skipped: false
    }
end function

function SkippedOutcome(probe as object) as object
    outcome = OutcomeRecord(probe)
    outcome.error = probe.skip
    outcome.skipped = true
    return outcome
end function

' A probe that threw before it could report. The message is surfaced rather
' than swallowed because on a diagnostic the fault is itself the finding.
function FaultedOutcome(probe as object, e as dynamic) as object
    outcome = OutcomeRecord(probe)
    message = e.message
    if message = invalid then message = "unknown error"
    outcome.error = "threw: " + message
    return outcome
end function

' A safe stringify for values from platform AAs, which may be absent or not the
' type the docs imply.
'
' Booleans are handled explicitly: `"" + true` is a runtime Type Mismatch (&h18),
' not the implicit "true" a string concat gives for numbers. GetLinkStatus(),
' GetInternetStatus() and HasFeature() all return booleans, so the lazy concat
' crashed the whole task the moment the device line ran.
function BoxStr(value as dynamic) as string
    if value = invalid then return ""
    valueType = Type(value)
    if valueType = "Boolean" or valueType = "roBoolean" then
        if value then return "true"
        return "false"
    end if
    try
        return value.ToStr()
    catch e
        return "?"
    end try
end function

' Whitespace without Trim(), because the caller is an optional string from a
' node field and Trim() on a non-string raises rather than helping. Mid() with a
' zero length is a legal empty string, where Left(s, 0) is not dependable.
function TrimBox(value as dynamic) as string
    s = value
    if s = invalid then return ""
    s = "" + s
    while Len(s) > 0
        head = Left(s, 1)
        if head <> " " and head <> Chr(9) then exit while
        s = Mid(s, 2)
    end while
    while Len(s) > 0
        tail = Right(s, 1)
        if tail <> " " and tail <> Chr(9) then exit while
        s = Mid(s, 1, Len(s) - 1)
    end while
    return s
end function

' One console line per event, so a telnet reader sees the run as it happens. The
' try is not for the print; it is so a formatting fault in a diagnostic can
' never be the thing that stops the diagnostic.
sub Say(text as string)
    try
        print "[netdiag] " + text
    catch ignored
    end try
end sub