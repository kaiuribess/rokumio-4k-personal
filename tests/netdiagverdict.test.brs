' Verdict() is pure: it takes plain associative arrays and builds a string, with
' no roUrlTransfer, no device globals and no Rnd. So it runs in the interpreter
' against the exact numbers a real run produced, which is what makes the three
' bugs it used to have catchable.
'
' The fixtures below are the wired run verbatim:
'
'   result:  A=200  B=-7  C=-7  D=-7  E=200
'   soak:    12/12
'   sweep:   1:1 2:2 3:2 4:3 6:4 8:5
'   versions AUTO 5/6  http2 5/6  1.1 6/6
'
' On that run the verdict claimed "Both IP and hostname reach the internet" and
' "CA bundle fixes HTTPS -> add SetCertificatesFile to Transport". Both were
' wrong, and both would have sent debugging at the wrong layer.

function NetDiag_Probe(tag as string, status as integer) as object
    return {
        tag: tag
        label: tag
        url: ""
        certs: false
        certsOk: ""
        ' The SAME function RunProbe uses, so the fixture cannot quietly encode a
        ' more forgiving definition of "connected" than production does.
        connected: NetDiagConnected(status)
        ok: status >= 200 and status < 300
        status: status
        error: ""
        skipped: false
    }
end function

function NetDiag_WiredProbes() as object
    return [
        NetDiag_Probe("A", 200)
        NetDiag_Probe("B", -7)
        NetDiag_Probe("C", -7)
        NetDiag_Probe("D", -7)
        NetDiag_Probe("E", 200)
    ]
end function

function NetDiag_CleanProbes() as object
    return [
        NetDiag_Probe("A", 200)
        NetDiag_Probe("B", 200)
        NetDiag_Probe("C", 200)
        NetDiag_Probe("D", 200)
        NetDiag_Probe("E", 200)
    ]
end function

function NetDiag_Version(v as string, ok as integer, total as integer) as object
    return { url: "", version: v, count: total, ok: ok, statuses: "", error: "" }
end function

function NetDiag_WiredVersions() as object
    return [
        NetDiag_Version("AUTO", 5, 6)
        NetDiag_Version("http2", 5, 6)
        NetDiag_Version("1.1", 6, 6)
    ]
end function

function NetDiag_WiredSweep() as object
    return [
        { count: 1, ok: 1 }
        { count: 2, ok: 2 }
        { count: 3, ok: 2 }
        { count: 4, ok: 3 }
        { count: 6, ok: 4 }
        { count: 8, ok: 5 }
    ]
end function

function NetDiag_AllResolved() as object
    return [
        { host: "v3-cinemeta.strem.io", attempts: 3, ok: 3, ips: [] }
        { host: "httpforever.com", attempts: 3, ok: 3, ips: [] }
        { host: "opensubtitles-v3.strem.io", attempts: 3, ok: 3, ips: [] }
    ]
end function

function NetDiag_Contains(haystack as string, needle as string) as boolean
    ' InStr's 3-arg form. Roku's compare is case-insensitive by default, which is
    ' what we want here — these assertions are about what the verdict concluded,
    ' not about the exact casing of a sentence.
    return InStr(0, haystack, needle) > 0
end function

sub Test_NetDiag_Verdict_OnTheWiredRun()
    Harness_Suite("NetDiag verdict (wired run)")

    verdict = Verdict(NetDiag_WiredProbes(), NetDiag_AllResolved(), { count: 12, ok: 12 }, NetDiag_WiredSweep(), NetDiag_WiredVersions())

    ' The bug: `connected` was `status <> 0`, so -7 counted as connected and a run
    ' where B and C both FAILED reported the internet as reachable.
    Harness_Ok(not NetDiag_Contains(verdict, "Both IP and hostname reach the internet"),
        "a -7 on both the IP-literal and hostname probes is not reported as reaching the internet")

    Harness_Ok(not NetDiag_Contains(verdict, "-> DNS."),
        "both-red is not blamed on DNS — an unreachable internet fails the IP probe and the hostname probe equally")

    Harness_Ok(NetDiag_Contains(verdict, "not DNS"),
        "both-red says so explicitly instead of staying silent or blaming the resolver")

    ' The trap: D failed at the TCP connect, before any handshake, so a CA bundle
    ' cannot explain it. Recommending SetCertificatesFile here would add a
    ' startup stall to every request to fix a connection that was never made.
    Harness_Ok(not NetDiag_Contains(verdict, "add SetCertificatesFile"),
        "a connect-level -7 is never reported as fixed by the CA bundle")

    Harness_Ok(NetDiag_Contains(verdict, "inconclusive"),
        "the D/E comparison reports inconclusive when one rung never connected")

    ' The result that actually mattered, and used to be printed but never read.
    Harness_Ok(NetDiag_Contains(verdict, "HTTP/1.1 ran the burst clean"),
        "a clean 1.1 burst against a lossy AUTO burst is named as the finding")

    Harness_Ok(NetDiag_Contains(verdict, "connection sharing"),
        "the verdict attributes the loss to HTTP/2 connection sharing, not the link")

    ' The parts that were already right must stay right.
    Harness_Ok(NetDiag_Contains(verdict, "resolver answered every lookup"),
        "3/3 on every resolver lookup still reports as answered")

    Harness_Ok(NetDiag_Contains(verdict, "single connections reliable"),
        "a perfect sequential soak still means the failures need load")

    Harness_Ok(NetDiag_Contains(verdict, "largest clean=2"),
        "the sweep threshold is still reported")

    Harness_Ok(NetDiag_Contains(verdict, "first loss=3"),
        "the width at which connections start dropping is still reported")
end sub

' The control: the ladder must still be able to reach a real diagnosis, or the
' fixes above have just replaced one wrong answer with no answer.
sub Test_NetDiag_Verdict_StillReachesRealConclusions()
    Harness_Suite("NetDiag verdict (controls)")

    ' B connects, C does not -> that is a DNS answer and must survive.
    dnsProbes = [
        NetDiag_Probe("A", 200)
        NetDiag_Probe("B", 200)
        NetDiag_Probe("C", -7)
        NetDiag_Probe("D", -7)
        NetDiag_Probe("E", -7)
    ]
    dnsVerdict = Verdict(dnsProbes, NetDiag_AllResolved(), { count: 12, ok: 12 }, NetDiag_WiredSweep(), NetDiag_WiredVersions())
    Harness_Ok(NetDiag_Contains(dnsVerdict, "-> DNS."),
        "an IP literal that works while the hostname does not is still diagnosed as DNS")

    ' Both D and E got real responses -> the certificate comparison is meaningful
    ' and the honest exoneration still prints.
    bothResponded = [
        NetDiag_Probe("A", 200)
        NetDiag_Probe("B", 200)
        NetDiag_Probe("C", 200)
        NetDiag_Probe("D", 200)
        NetDiag_Probe("E", 200)
    ]
    certVerdict = Verdict(bothResponded, NetDiag_AllResolved(), { count: 12, ok: 12 }, NetDiag_WiredSweep(), NetDiag_WiredVersions())
    Harness_Ok(NetDiag_Contains(certVerdict, "works with and without a CA bundle"),
        "HTTPS that answers on both rungs is still exonerated of certificates")
    Harness_Ok(NetDiag_Contains(certVerdict, "Both IP and hostname reach the internet"),
        "an all-green ladder still reports the internet reachable")

    ' AUTO losing while 1.1 is clean is the shape that produced the fix. When BOTH
    ' are clean the verdict must not claim a version effect, or it will keep
    ' recommending a pin it cannot justify.
    bothCleanVersions = [
        NetDiag_Version("AUTO", 6, 6)
        NetDiag_Version("http2", 6, 6)
        NetDiag_Version("1.1", 6, 6)
    ]
    noEffect = Verdict(bothResponded, NetDiag_AllResolved(), { count: 12, ok: 12 }, NetDiag_WiredSweep(), bothCleanVersions)
    Harness_Ok(NetDiag_Contains(noEffect, "no version effect at this width"),
        "a clean AUTO burst does not get blamed on connection sharing")
    Harness_Ok(not NetDiag_Contains(noEffect, "ran the burst clean while AUTO lost"),
        "a version effect is only reported when AUTO actually lost transfers")

    ' If 1.1 loses too, HTTP/2 is not the mechanism and the verdict has to say so
    ' rather than pointing at the version anyway.
    allLossyVersions = [
        NetDiag_Version("AUTO", 4, 6)
        NetDiag_Version("http2", 4, 6)
        NetDiag_Version("1.1", 4, 6)
    ]
    notVersion = Verdict(bothResponded, NetDiag_AllResolved(), { count: 12, ok: 12 }, NetDiag_WiredSweep(), allLossyVersions)
    Harness_Ok(NetDiag_Contains(notVersion, "not the HTTP version"),
        "a lossy 1.1 burst rules the HTTP version out instead of pinning anyway")

    ' A lossy SEQUENTIAL soak is a different failure entirely: the link drops
    ' with nothing in flight, so concurrency is not the explanation.
    soakLossy = Verdict(bothResponded, NetDiag_AllResolved(), { count: 12, ok: 10 }, NetDiag_WiredSweep(), NetDiag_WiredVersions())
    Harness_Ok(NetDiag_Contains(soakLossy, "NO concurrency"),
        "a sequential soak that loses requests reports the link dropping under no load")

    ' A rejected 1.1 has to be reported, or a device that refuses the pin would
    ' leave the reader thinking the comparison ran.
    rejected = [
        NetDiag_Version("AUTO", 5, 6)
        NetDiag_Version("http2", 5, 6)
        { url: "", version: "1.1", count: 0, ok: 0, statuses: "", error: "SetHttpVersion(1.1) rejected" }
    ]
    rejectedVerdict = Verdict(bothResponded, NetDiag_AllResolved(), { count: 12, ok: 12 }, NetDiag_WiredSweep(), rejected)
    Harness_Ok(NetDiag_Contains(rejectedVerdict, "OS rejected HTTP/1.1"),
        "a platform that refuses HTTP/1.1 is reported instead of passing silently")
    Harness_Ok(not NetDiag_Contains(rejectedVerdict, "ran the burst clean"),
        "a refused 1.1 is never reported as a clean burst")

    ' Nothing to report at all has to say so rather than returning an empty
    ' string that reads like a truncated log.
    empty = Verdict([], [], { count: 0, ok: 0 }, [], [])
    Harness_Equal(empty, "inconclusive", "no evidence at all reports as inconclusive")
end sub

' The definition of "connected" is what made the verdict report a -7 as a
' reachable internet. It cannot be reached through RunProbe without a live
' roUrlTransfer, which is exactly why it was inline and untested; factoring it
' out is what makes it checkable.
sub Test_NetDiag_Connected_MeansAResponseArrived()
    Harness_Suite("NetDiag connected definition")

    Harness_Equal(NetDiagConnected(-7), false, "-7 (CURLE_COULDNT_CONNECT) is not connected")
    Harness_Equal(NetDiagConnected(0), false, "0 (no response at all) is not connected")
    Harness_Equal(NetDiagConnected(200), true, "200 is connected")
    Harness_Equal(NetDiagConnected(404), true, "a real response code is connected even when it is an error answer")
    Harness_Equal(NetDiagConnected(302), true, "a redirect answered on the way to a 2x still proves the socket opened")
end sub
