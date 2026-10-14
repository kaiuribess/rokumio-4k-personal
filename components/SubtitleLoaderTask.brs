' SubtitleLoaderTask — fetch the caption tracks for the playing video off the
' UI thread. The screen already picked the add-on that advertises the
' "subtitles" resource, so only its address comes in. The store + transport are
' built fresh inside the task scope — no object created on the render thread is
' shared across the thread boundary. The result never gates playback: subtitles
' attach whenever they arrive, before or after the stream starts.
'
' Why the request is retried here, and why the answer says whether it was worth
' retrying. A provider that could not be reached used to be indistinguishable
' from one that has no captions for this title: both arrived as { ok: false,
' subtitles: [] }, the screen's only test was `not result.ok`, and the drain read
' both as "this provider has nothing" and moved on. So one timed-out request
' cost the user captions for the rest of the play, and nothing anywhere said the
' request had failed — which is exactly what it looks like on a flaky link, and
' what it looked like in the field: no captions on one entry into a title, and 98
' tracks from the same provider seconds later on the next entry.
'
' The classification is on the store's three-state `status`, not on the error
' string, because the string cannot answer it (see SubtitlesStore.Subtitles).
'
' The wait between attempts is bounded by a COUNT, never by a clock reading —
' StreamResolveTask's probe loop is the same shape and says why. Waiting is the
' point of a Task: Wait() aborts the brs interpreter's run and Ticks() does not
' exist in it, so a wait loop in store code would be neither exercised by the
' suite nor timed. Two arguments because that is the signature BrighterScript
' checks against (BS1002); an invalid port is Roku's own one-argument Wait.
sub init()
    m.top.functionName = "load"
end sub

' Trace one line of the retry loop to the console.
'
' Wrapped because it runs on the fetch path, inside the loop whose whole job is to
' succeed: a print that raised would be caught by the catch below and reported as a
' definite failure, turning the diagnostic into the fault. It is the only thing in
' this task allowed to fail silently, and it cannot affect the result either way.
'
' No other task or store in this app prints, so there is no precedent proving a
' print works from a Task's own interpreter. That is why this is defensive rather
' than because the language cannot do it: if the field turns out not to be
' available here, the line is lost and the fetch is untouched.
sub Trace(message as string)
    try
        print message
    catch ignored
    end try
end sub

sub load()
    try
        http = Transport()
        store = SubtitlesStore(http)

        attempts = 0
        kind = ""
        lastError = ""
        lastStatus = 0
        lastIssued = false

        ' Three is a literal rather than a computed bound so the ceiling reads in
        ' one place. Two intervals: 1s, then 3s — long enough that a link still
        ' coming up gets a real chance, short enough that pressing play is not
        ' followed by a long silence before the third try.
        for attempt = 1 to 3
            ' Stop-aware, and the check has to be here rather than trusting the
            ' node to be gone: removing a Task node does not kill its running
            ' thread, so a cancelled fetch would keep retrying and then write a
            ' result onto a detached node — racing the fresh task the screen binds
            ' to the next play. LinkStremioTask guards the same hazard.
            if m.top.control = "STOP" then return

            attempts = attempt
            Trace("[subs] attempt " + attempt.ToStr() + "/3 -> " + RedactUrl(m.top.addonAddress))
            answer = store.Subtitles(m.top.addonAddress, m.top.metaType, m.top.videoId)
            lastError = answer.error
            lastStatus = answer.status
            lastIssued = false
            if answer.issued = true then lastIssued = true

            if answer.ok
                ' Per-attempt, not just per-provider. The result is written ONCE,
                ' after the loop, so a rescue on attempt 3 is otherwise
                ' indistinguishable from a clean first try — the earlier failures
                ' are gone by the time the screen sees anything. That invisibility
                ' is the whole problem this file was written to remove, and it
                ' would be reintroduced by the retry that hides the flake.
                raw = 0
                if answer.subtitles <> invalid then raw = answer.subtitles.Count()
                Trace("[subs] attempt " + attempt.ToStr() + "/3 ok — " + raw.ToStr() + " track(s)")
                ' An empty array is a real answer, not a failure: the add-on was
                ' asked a well-formed question about this title and reported that
                ' it holds no captions for it. Reaching here is the screen's
                ' "honest no data obtained", and it carries kind "" so nothing
                ' downstream mistakes it for an error worth reporting.
                m.top.result = {
                    ok: true
                    subtitles: answer.subtitles
                    error: ""
                    status: answer.status
                    issued: true
                    reached: true
                    kind: ""
                    attempts: attempts
                }
                return
            end if

            kind = ClassifyFailure(answer)
            ' A definite answer ends the search: this is not a condition another
            ' identical request would change.
            if kind <> "retry" and kind <> "server" then
                Trace("[subs] attempt " + attempt.ToStr() + "/3 FAILED and not retryable — kind=" + kind + " status=" + lastStatus.ToStr() + " error=[" + lastError + "]")
                exit for
            end if

            Trace("[subs] attempt " + attempt.ToStr() + "/3 FAILED — kind=" + kind + " status=" + lastStatus.ToStr() + " error=[" + lastError + "]")

            ' Skipped on the last attempt, where it would only be a pause before
            ' giving up.
            if attempt = 1 then
                Wait(1000, invalid)
            else
                Wait(3000, invalid)
            end if
        end for

        m.top.result = {
            ok: false
            subtitles: []
            error: lastError
            status: lastStatus
            issued: lastIssued
            ' Whether an HTTP response came back at all — false for a timeout, a
            ' DNS/connect/TLS failure or a rejected request, and true for any
            ' status the add-on actually produced, including 4xx and a 200 whose
            ' body was not the protocol. This is the field that separates "we
            ' could not reach it" from "it had nothing", which `ok` alone does
            ' not: both are false in the two cases a user cares about.
            reached: lastStatus >= 200
            kind: kind
            attempts: attempts
        }
    catch e
        ' A throw is our own bug, not the add-on's answer, so it is definite:
        ' retrying the same call would throw the same way. Nothing was issued.
        m.top.result = {
            ok: false
            subtitles: []
            error: e.message
            status: 0
            issued: false
            reached: false
            kind: "definite"
            attempts: 0
        }
    end try
end sub

' Which of three failures this is, because they call for different behaviour from
' the caller. Driven by the store's `issued` + `status` pair, and the ORDER matters:
' `issued` is asked first because it is the only question the sign of status cannot
' answer.
'
'   "definite" — we never made the request at all (`issued = false`): our own bad
'                input. The next request would be byte-identical.
'   "retry"    — we asked and never heard back. status < 0 is the transport saying
'                it could not complete the transfer at all (DNS, refused
'                connection, TLS); status 0 is a timeout or a transfer that would
'                not start. Worth another go — and cheap: these fail in
'                milliseconds, not after the timeout ceiling.
'   "server"   — it answered 5xx. Transient on its side, so another go is
'                reasonable, but this is the add-on being unwell rather than the
'                device being unable to reach it.
'   "definite" — it answered 4xx. Another identical request changes nothing.
'   "definite" — it answered 2xx in something the protocol is not. The only
'                failure a 2xx can carry is Transport's "invalid JSON response",
'                and in this app's field that is mostly the dead
'                opensubtitles.strem.io endpoint serving its HTML landing page
'                for the stremio/v1 path. Retrying is pure waste — the same URL
'                returns the same page — so "it answered and had nothing" is as
'                final as a 4xx. (This is the one case the position of `status`
'                in the ladder alone cannot express: a 2xx HTML body reads as a
'                reachable answer, not a transport failure, so it would otherwise
'                fall to the bottom `return "retry"` and spam the request — and
'                the ParseJson console error — three times per play.)
'
' A successful empty list is not a failure and has no kind at all.
'
' NOTE: an earlier version of this tested `if answer.status < 0 then return
' "definite"`, intending to catch only its own -1 pre-request sentinel. Transport
' reports a NEGATIVE status for every transport failure, so that one line
' classified every connect refusal as non-retryable — the exact opposite of what it
' was for. A refused connection never got a second try.
'
' `issued` and `status` are read defensively rather than tested for truth: a
' missing field throws &h18 on this runtime (the trap MainScene.onAddonSyncResult
' documents), so `if not answer.issued` is not safe against a result that predates
' the flag.
function ClassifyFailure(answer as object) as string
    issued = false
    if answer.issued = true then issued = true
    status = -1
    if answer.status <> invalid then status = answer.status

    if not issued then return "definite"
    if status < 0 then return "retry"
    if status = 0 then return "retry"
    if status >= 500 then return "server"
    if status >= 400 then return "definite"
    ' Read defensively, same shape as `issued` above: an answer from an older
    ' shape without the error field must not throw somewhere the classification
    ' ladder was previously total.
    answeredHtml = false
    if answer.error <> invalid and answer.error = "invalid JSON response" then answeredHtml = true
    if status >= 200 and answeredHtml then return "definite"
    return "retry"
end function
