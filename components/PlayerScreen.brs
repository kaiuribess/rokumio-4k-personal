' PlayerScreen — minimal video playback for a stream handed over by StreamsScreen.
'
' StreamsScreen pushes { stream, serverAddress, … } and playback resolution
' (ResolvePlayback) happens HERE, not on the picker: ResolvePlayback passes a
' direct URL through as-is and creates a torrent engine on the streaming server
' (up to the 120s long timeout on a cold engine) off the render thread. While it
' waits the media logo beats from transparent to solid (the Stremio pre-buffer
' pulse); on success the video starts, on failure the player stays with the
' Stremio wording and Back returns to the stream list.
'
' Tracks position, and on Back (or exit) records where the user stopped through
' LibraryStore.SetPosition so Continue Watching / Resume can pick it up. Leaving
' during the resolve phase never saves — hasPlayed guards the write. Resume
' positions are stored in seconds and carried into the content node's playStart
' field; playback state is surfaced through the status label so a broken stream
' is a message, not a black screen.
'
' Transport is the platform's: the Video runs with enableUI and enableTrickPlay
' on, so OK/play-pause show the native pause screen, Left/Right and FF/RW use
' the native seek/trick-play UI, and "*" opens Roku's Options overlay with its
' certification-mandated captions dialog. The screen only owns the resolve
' (pre-video) phase and teardown; Back records the position and pops.
'
' Subtitle captions are fetched off-thread (SubtitleLoaderTask) from an add-on
' advertising the "subtitles" resource (OpenSubtitles v3 is the built-in, an
' installed add-on wins) and attached to the video through SubtitleTracks /
' SubtitleConfig. The initial default selects a track while preserving Roku's
' caption mode; late providers preserve the native track choice. A list in hand
' when the stream starts rides on the ContentNode (Roku's documented home for
' SubtitleTracks) before play. The native Options dialog lists Off + every
' track from SubtitleTracks, so the Roku OS owns track selection from there.
' Auto-pick is by device locale, else English, else the first track.
'
' Params: { stream, serverAddress, metaType, metaId, videoId, season, episode,
'           position, name, poster, logo }.

sub init()
    m.video = m.top.FindNode("video")
    m.status = m.top.FindNode("playerStatus")
    m.bufferingGroup = m.top.FindNode("bufferingGroup")
    m.logoBack = m.top.FindNode("logoBack")
    m.logoFront = m.top.FindNode("logoFront")
    m.resolvePulse = m.top.FindNode("resolvePulse")
    m.toastGroup = m.top.FindNode("toastGroup")
    m.toastPlate = m.top.FindNode("toastPlate")
    m.toastLabel = m.top.FindNode("toastLabel")
    m.toastFade = m.top.FindNode("toastFade")
    m.playbackInfoGroup = m.top.FindNode("playbackInfoGroup")
    m.playbackInfoText = m.top.FindNode("playbackInfoText")
    m.playingSegment = invalid
    m.resolvedPlayback = invalid
    m.devicePlaybackInfo = invalid

    t = Theme()
    m.top.FindNode("playerBg").color = t.playerBg
    m.status.color = t.textPrimary
    if m.toastPlate <> invalid then m.toastPlate.color = t.scrim
    if m.toastLabel <> invalid then m.toastLabel.color = t.textPrimary

    ' Two of these, both observed here rather than armed at the call site: the
    ' Animation is what actually fades the toast, the Timer is what guarantees it
    ' is gone even if the Animation is a silent no-op on this OS.
    m.toastHideTimer = m.top.FindNode("toastHideTimer")
    if m.toastHideTimer <> invalid then m.toastHideTimer.ObserveField("fire", "onToastHideFire")

    ' Observed here rather than in CreateVideo: this screen is a static child
    ' that survives every pop, so CreateVideo runs once per play and observing
    ' there would re-observe the same two fields on each one.
    m.video.ObserveField("state", "onVideoStateChanged")
    m.video.ObserveField("bufferingStatus", "onBufferingStatusChanged")
    for each field in ["videoFormat", "audioFormat", "streamingSegment"]
        if m.video.HasField(field) then m.video.ObserveField(field, "onPlaybackFactsChanged")
    end for
    for each field in ["availableAudioTracks", "currentAudioTrack"]
        if m.video.HasField(field) then m.video.ObserveField(field, "onEnglishAudioFactsChanged")
    end for
    m.audioGuardTimer = m.top.FindNode("englishAudioCheck")
    if m.audioGuardTimer <> invalid then m.audioGuardTimer.ObserveField("fire", "onEnglishAudioTimeout")
    m.audioGuardActive = false
    m.audioGuardArmed = false
    m.audioGuardBlocked = false
    m.audioChoiceMade = false
    m.audioDialog = invalid
    m.retryTimer = m.top.FindNode("autoSourceRetry")
    m.startupLimit = m.top.FindNode("sourceStartupLimit")
    if m.retryTimer <> invalid then m.retryTimer.ObserveField("fire", "onAutoSourceRetry")
    if m.startupLimit <> invalid then m.startupLimit.ObserveField("fire", "onSourceStartupTimeout")
    m.sourceQueue = []
    m.sourceIndex = 0
    m.retryPending = false
    m.playbackActive = false
    m.sourceAccepted = false
    m.lastEnglishTrack = ""
    InitSourceMemory()
    InitAudioRecovery()
    InitNextEpisode()

    m.resolveTask = invalid
    m.subtitleTask = invalid
    m.subtitleParams = invalid
    m.subtitleCandidates = []
    m.subtitleCursor = 0
    m.subtitleTracks = invalid
    m.subtitleIndex = -1
    m.subtitleNodesApplied = false
    m.subtitleSelectionApplied = false
    m.subtitleAsked = ""
    m.subtitleReached = 0
    m.subtitleTried = 0
    m.subtitlePicker = SubtitlesStore(invalid)

    ' The tick boundary StartPlayback defers `control = "play"` across. Observed
    ' here rather than in CreateVideo so it is armed exactly once, and armed
    ' before any play can ask for it.
    m.playTimer = m.top.FindNode("playKick")
    m.playArmed = false
    m.workerSequence = 0
    if m.playTimer <> invalid then m.playTimer.ObserveField("fire", "onPlayKickFire")
end sub

function OnEnter(params as object) as void
    if params = invalid or params.stream = invalid then return
    ResetAudioRecovery()
    m.playParams = params
    PrepareNextEpisode(params)
    m.audioGuardBlocked = false
    m.audioGuardActive = false
    m.audioGuardArmed = false
    m.playbackActive = true
    m.retryPending = false
    m.sourceQueue = AutoPlayback_Candidates(params.stream, params.candidates)
    if params.diagnosticControl = true then m.sourceQueue = [params.stream]
    m.sourceIndex = 0
    m.sourceAccepted = false
    m.saved = false
    m.hasPlayed = false
    m.playingSegment = invalid
    m.resolvedPlayback = invalid
    m.devicePlaybackInfo = invalid
    HidePlaybackInfo()
    ' The status line is cleared here, not left to the first onVideoStateChanged.
    ' "playing" is the only branch that clears it (see below), and a stream that
    ' cannot resolve never reaches it — so without this, a dead source's message
    ' outlives the pop and is still on screen for the WHOLE of the next play's
    ' resolve, which for a torrent is up to the long timeout. ResetVideoNode
    ' clears it too; this is the belt to that braces, since a play entered
    ' without a preceding OnExit (the very first one) still starts clean.
    m.status.text = "Opening selected source…" + Chr(10) + "Back returns to sources"
    if params.rememberedSource = true then m.status.text = "Opening your previous working source…" + Chr(10) + "Back cancels"

    ' The pre-buffer pulse (logo beating transparent to solid, Stremio-style)
    ' only has something to show when a logo URL is available; otherwise the
    ' status text remains visible while the source opens, including titles that
    ' have no artwork. The pulse complements that feedback.
    logo = params.logo
    if logo = invalid or logo = "" then logo = params.poster
    if logo <> invalid and logo <> ""
        m.logoBack.uri = logo
        m.logoFront.uri = logo
        m.bufferingGroup.visible = true
        StartResolvePulse()
    else
        m.logoBack.uri = ""
        m.logoFront.uri = ""
        m.bufferingGroup.visible = false
    end if

    StartResolve(params.stream, params.serverAddress, ResolveOrdinal(params.season), ResolveOrdinal(params.episode))
    if params.diagnostic <> true then StartSubtitles(params)
    ArmSourceStartupLimit(true)
end function

' Kick the stream resolution off the render thread. The task frees the UI as the
' create/torrent warm-up parks (up to the long timeout); a direct URL resolves
' instantly through the same path.
'
' Season and episode go across as INTEGERS, not as the name fragments the server
' will match release names against. Two reasons, and the second is the one that
' bites: the fragments are the streaming server's protocol, so the store builds
' them; and a Task field is assigned through AddReplace, which enforces its
' declared type and rejects an array on the device with a runtime "Type
' mismatch" the test suite cannot see.
sub StartResolve(stream as object, serverAddress as dynamic, season = 0 as integer, episode = 0 as integer)
    if stream = invalid then
        m.status.text = "No playable source was selected. Press Back and choose a direct HTTPS stream."
        return
    end if
    if serverAddress = invalid then serverAddress = ""
    PrepareSourceMemoryAttempt(stream)
    task = AsyncTask_Launch(m.top, "StreamResolveTask", "onResolveResult", {
        stream: stream
        serverAddress: serverAddress
        season: season
        episode: episode
        audioMode: PlaybackInfo_Text(m.playParams.audioMode)
    }, NextPlayerWorkerId("playerResolve"))
    m.resolveTask = task
end sub

' Season and episode as whole numbers, 0 when the play has neither. Coerced
' rather than passed through because the Task fields are declared integer and
' AddReplace will not coerce a float on the player's behalf.
function ResolveOrdinal(value as dynamic) as integer
    if value = invalid then return 0
    try
        return Int(value)
    catch notANumber
        return 0
    end try
end function

sub StartResolvePulse()
    if m.resolvePulse = invalid then return
    ' The pulse is logoBack alone — the front (reveal) copy is hidden so it can't
    ' sit solid on top and mask the beat. StopResolvePulse brings it back for the
    ' buffering fill.
    if m.logoFront <> invalid then m.logoFront.visible = false
    m.resolvePulse.control = "stop"
    m.resolvePulse.control = "start"
end sub

' Freeze the pulse and restore the resting buffering pose: the back returns to
' its faint opacity (0.22), the solid front is back on top but fully clipped so
' it is "not shown" yet — onBufferingStatusChanged reveals it from the left as
' buffering % arrives.
sub StopResolvePulse()
    if m.resolvePulse <> invalid then m.resolvePulse.control = "stop"
    if m.logoFront <> invalid
        m.logoFront.visible = true
        m.logoFront.clippingRect = [0, 0, 0, 506]
    end if
    if m.logoBack <> invalid then m.logoBack.opacity = 0.22
end sub

' The resolve finished. Success starts playback; a failure (e.g. "request timed
' out") stays on the player with the Stremio wording and Back returns to the
' stream list. Results that land after a Back-out are dropped by the
' m.resolveTask guard.
'
' The handoff to the player is wrapped in a try. Uncaught, a throw between here
' and the first frame killed playback with nothing on screen to say why — the
' status line kept whatever the pre-resolve text was, so a dead player and a
' player that had not started yet looked identical. This says which it was.
sub onResolveResult(event as object)
    if m.resolveTask = invalid then return
    task = event.GetRoSGNode()
    if task = invalid then return
    if task.id <> m.resolveTask.id then return
    result = event.GetData()
    ' An alwaysNotify field can notify before the worker writes its answer.
    ' Keep the task reference and observer until an actual result arrives.
    if result = invalid then return
    m.resolveTask = invalid
    try
        AsyncTask_Reap(task, m.top, false)
        StopResolvePulse()

        ' The engine warm-up, printed on both paths and unconditionally within
        ' them. The transport trace deliberately stays quiet about a 2xx, so
        ' without this line a warm-up that worked leaves no trace at all — and
        ' "did the HEAD reach the server" is the first thing to establish when a
        ' torrent is slow to start, since everything downstream of it assumes the
        ' engine exists.
        '
        ' `trackers` is the field that decides what the answer meant. A cold engine
        ' given trackers resolves in seconds; one given none has DHT alone to find
        ' metadata, which is a wait no timeout here should be tuned against.
        '
        ' `range` is the second request in that warm-up: a ranged GET of the first
        ' 64KB of the file, which is what actually waits out the metadata. The HEAD
        ' above only reports that the engine was CREATED — it returns in
        ' milliseconds and says nothing about whether the engine can then answer.
        ' Printed next to it because the pair is the diagnosis: HEAD 200 with a
        ' dead range means the engine was created and never became ready (the
        ' stream is not coming), and both 200 means the engine was ready and
        ' anything after this is the player''s own problem.
        if result <> invalid and result.warmup <> invalid then
            warmTrackers = -1
            if result.warmup.trackers <> invalid then warmTrackers = result.warmup.trackers
            warmIdx = -1
            if result.warmup.fileIdx <> invalid then warmIdx = result.warmup.fileIdx
            print "[resolve] engine warm-up HEAD -> status=" ; result.warmup.status ; " ok=" ; result.warmup.ok ; " trackers=" ; warmTrackers ; " fileIdx=" ; warmIdx
            ' Printed on its own line rather than folded into the one above, because
            ' a range of `invalid` is a warm-up that never got to run the request
            ' and concatenating a missing field would throw &h18 — the same trap
            ' MainScene.onAddonSyncResult documents.
            if result.warmup.range <> invalid then
                print "[resolve] engine metadata read -> status=" ; result.warmup.range.status ; " ok=" ; result.warmup.range.ok
            end if
        end if

        ' The probe's own account, and it is printed for the SUCCESS case too. That used to
        ' be gated to the failure branch on the reasoning that a probe which gave up
        ' is always an unsuccessful resolve — which is true, and which meant the
        ' successful case reported nothing at all. A play that timed out once and
        ' then recovered on attempt 2 is a SUCCESS, so its one timeout was visible
        ' only as a stray [http] line with nothing to say how many attempts it took
        ' or what the first one answered. That is exactly the distinction needed to
        ' tell a cold engine (first attempt expires, engine not ready yet) from a
        ' flaky link (an already-warm engine still loses a request), and it was the
        ' thing that made the two indistinguishable in the log.
        '
        ' Read only when result is known valid: a field read on invalid throws &h18
        ' (the trap MainScene.onAddonSyncResult documents). Printed only when the
        ' probe took more than one attempt — a first-try success is the expected
        ' case and printing it every play would be noise, so its absence from the
        ' log IS the signal that nothing went wrong.
        if result <> invalid and result.probe <> invalid then
            probeStatus = -1
            if result.probe.status <> invalid then probeStatus = result.probe.status
            probeAttempts = 0
            if result.probe.attempts <> invalid then probeAttempts = result.probe.attempts
            if result.probe.gaveUp = true then
                print "[resolve] probe gave up after " ; probeAttempts ; " attempt(s) — status=" ; probeStatus
            else if probeAttempts > 1 then
                print "[resolve] probe recovered after " ; probeAttempts ; " attempt(s) — status=" ; probeStatus
            end if
        end if

        if result = invalid or not result.ok or result.url = invalid or result.url = ""
            message = "This source could not be opened. Press Back and choose another source."
            if result <> invalid and result.error = "no streaming server address" then
                message = "This torrent source needs a server. Choose a direct HTTPS source from your provider."
            else if result <> invalid and result.error = "unsupported stream URL scheme" then
                message = "This source is not a direct HTTP/HTTPS video. Press Back and choose another source."
            end if
            m.status.text = message
            ScheduleNextSource("resolve-failed")
            return
        end if

        m.resolvedPlayback = result
        ' A provider's 2160p label cannot override a measured lower-resolution
        ' file when the user explicitly selected the 4K-only filter. Unknown
        ' dimensions remain unknown; this guard does not certify a 4K master.
        if Type(m.playParams) = "roAssociativeArray" and m.playParams.fourKOnly = true
            if NativeMedia_KnownBelowUhd(result.media)
                ScheduleNextSource("below-UHD")
                return
            end if
        end if
        if Type(result.audioPolicy) = "roAssociativeArray" and result.audioPolicy.compatible = false
            ScheduleNextSource("file-audio-incompatible")
            return
        end if
        StartPlayback(result.url, result.streamFormat)
    catch e
        m.status.text = "The player could not start. Press Back and choose another source."
        ScheduleNextSource("handoff-failed")
    end try
end sub

sub CancelResolve()
    if m.resolveTask <> invalid
        task = m.resolveTask
        m.resolveTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
    StopResolvePulse()
end sub

' Kick the caption fetch off the render thread. Subtitles never gate playback:
' StartPlayback applies whatever had arrived by then and a late result applies
' to the live Video node the moment it reports in.
'
' The candidate list comes from SubtitlesAddresses, which RANKS by what a
' provider is rather than taking whatever the registry happened to yield first.
'
' Every ranked provider is asked, in that order, and their tracks are MERGED
' rather than raced: first provider's captions are usable after one round trip,
' and each later provider only adds to them. So the ranking decides which captions
' appear first in the list and which provider's pick wins by default, not which
' provider is the only one that gets a say — a provider that cannot answer costs
' one round trip and contributes nothing rather than ending the search.
sub StartSubtitles(params as object)
    if m.stores = invalid then return
    if m.subtitleTask <> invalid then return
    if params.metaType = invalid or params.videoId = invalid then return
    if params.metaType = "" or params.videoId = "" then return

    ' A merge is append-only, so it has to start from nothing. Reusing the
    ' previous play's tracks would mix two videos' captions into one list and
    ' leave m.subtitleIndex pointing into the older half.
    m.subtitleTracks = invalid
    m.subtitleIndex = -1
    m.subtitleNodesApplied = false
    m.subtitleSelectionApplied = false

    m.subtitleParams = { metaType: params.metaType, videoId: params.videoId }
    m.subtitleCandidates = SubtitlesAddresses(m.stores.addons.callFunc("AddonsGetAll"))
    m.subtitleCursor = 0
    ' What this play's drain is able to report when it ends. `reached` counts the
    ' providers that actually produced an HTTP response; `tried` counts every
    ' provider asked. The pair is what separates "nobody has captions for this
    ' title" (tried > 0, reached > 0) from "we could not get to anyone" (tried >
    ' 0, reached = 0) — the two are the same empty list to the player and only one
    ' of them is worth telling the user about.
    m.subtitleReached = 0
    m.subtitleTried = 0
    print "[subs] enter " ; params.metaType ; "/" ; params.videoId ; " — registry has " ; AddonsCount() ; " addon(s), " ; m.subtitleCandidates.Count() ; " offer subtitles"
    LaunchSubtitleFetch()
end sub

' Put a message over the video for two seconds and fade it out. Armed through
' `control` rather than Start()/Stop(): an roSGNode Timer and Animation have no
' such methods and calling one is a runtime &hf4 "Member function not found" —
' the same trap playKick below documents.
'
' Opacity is forced back to 1 first because the fade leaves it at 0, and a second
' toast inside that window would otherwise be born invisible.
sub ShowToast(message as string)
    if m.toastGroup = invalid or m.toastLabel = invalid then return
    m.toastLabel.text = message
    m.toastGroup.opacity = 1
    m.toastGroup.visible = true
    if m.toastFade <> invalid
        m.toastFade.control = "stop"
        m.toastFade.control = "start"
    end if
    if m.toastHideTimer <> invalid
        m.toastHideTimer.control = "stop"
        m.toastHideTimer.control = "start"
    end if
end sub

sub onToastHideFire()
    if m.toastGroup <> invalid
        m.toastGroup.visible = false
        m.toastGroup.opacity = 1
    end if
end sub

' How many add-ons the registry holds right now. Reporting it separately from the
' subtitle count is the whole diagnostic: a provider list of 0 against a registry
' of 12 means the ranking found nothing to ask, and a registry of 0 means the
' snapshot was taken before the sync registered anything (see
' EnsureSubtitleProviders). Print, because this app is debugged over telnet.
function AddonsCount() as integer
    addons = m.stores.addons.callFunc("AddonsGetAll")
    if addons = invalid then return 0
    return addons.Count()
end function

' The display name of the add-on behind an address, or "" when the registry no
' longer holds that address. The subtitle queue ranks addresses, but a failure
' toast that named only the address would lecture with a URL; the name is what
' the user installed and recognises.
function SubtitleProviderName(address as string) as string
    addons = m.stores.addons.callFunc("AddonsGetAll")
    if addons = invalid then return ""
    for each addon in addons
        if addon <> invalid and addon.address <> invalid and addon.address = address
            if addon.name <> invalid and addon.name <> "" then return addon.name
        end if
    end for
    return ""
end function

' The provider list was snapshotted once, at OnEnter — during the stream resolve,
' which is the busiest moment in the app's startup. When the add-on sync has not
' registered its descriptors by then, SubtitlesAddresses returns an empty list,
' LaunchSubtitleFetch has nothing to ask, MoreSubtitleCandidates is false, and
' SubtitlesAddresses has no other caller: the caption search is over for that
' play and the Options dialog lists nothing, permanently. Nothing had failed, so
' nothing said so — it only ever showed on a stremio session whose subtitle
' provider is an account add-on, because the built-in seeds cover every other case.
'
' MainScene calls this from the two points the registry actually moves (the sync
' install loop, and a Rokumio import), next to its own HomeScreen call. Re-derive
' the list and append whatever is new, so a provider that arrived mid-play is
' asked then and its tracks land on the live node through the existing late-arrival
' path (onSubtitleResult -> ApplySubtitleIndex(invalid)).
'
' Appending, not re-queuing: the cursor only moves forward, so pushing onto the
' tail asks the new provider without re-asking one already tried, and AddressIn
' keeps a provider that merely appears twice from being fetched twice. m.subtitleIndex
' is untouched — onSubtitleResult picks the default once, on the first provider
' that yields tracks, so a list that grows later cannot renumber a selection the
' user has already made.
sub EnsureSubtitleProviders()
    if m.stores = invalid then return
    ' Not a play, or the play is over: OnExit's CancelSubtitles blanked the
    ' params, and there is nothing left to attach captions to.
    if m.subtitleParams = invalid then return
    ' One request in flight at a time. The drain resumes from onSubtitleResult
    ' when this one settles, against a candidate list this call has already
    ' extended, so there is nothing to do but wait.
    if m.subtitleTask <> invalid then return

    fresh = SubtitlesAddresses(m.stores.addons.callFunc("AddonsGetAll"))
    added = 0
    for each address in fresh
        if not AddressIn(m.subtitleCandidates, address)
            m.subtitleCandidates.Push(address)
            added = added + 1
            print "[subs] new provider joined the queue: " ; RedactUrl(address)
        end if
    next
    if added = 0
        print "[subs] registry moved but offered nothing new"
        return
    end if
    print "[subs] resuming: " ; added ; " new provider(s), queue now " ; m.subtitleCandidates.Count() ; " at cursor " ; m.subtitleCursor
    LaunchSubtitleFetch()
end sub

' Is there another ranked provider left to ask? Kept as one predicate because
' two branches need it — a provider that answered with nothing, and a provider
' that answered with something and still has company — and they must agree.
sub MoreSubtitleCandidates() as boolean
    if m.subtitleCandidates = invalid then return false
    return m.subtitleCursor < m.subtitleCandidates.Count()
end sub

' Ask the next queued provider. One candidate is in flight at a time and the
' cursor only ever moves forward, so a registry full of dead providers costs one
' request each and still terminates.
sub LaunchSubtitleFetch()
    if m.subtitleParams = invalid then return
    if m.subtitleTask <> invalid then return
    if m.subtitleCandidates = invalid then return
    if m.subtitleCursor >= m.subtitleCandidates.Count() then return

    address = m.subtitleCandidates[m.subtitleCursor]
    m.subtitleCursor = m.subtitleCursor + 1
    if address = invalid or address = "" then
        LaunchSubtitleFetch()
        return
    end if
    m.subtitleAsked = address
    m.subtitleTried = m.subtitleTried + 1
    print "[subs] asking #" ; m.subtitleCursor ; "/" ; m.subtitleCandidates.Count() ; " -> " ; RedactUrl(address)

    task = AsyncTask_Launch(m.top, "SubtitleLoaderTask", "onSubtitleResult", {
        addonAddress: address
        metaType: m.subtitleParams.metaType
        videoId: m.subtitleParams.videoId
    }, NextPlayerWorkerId("playerSubtitles"))
    m.subtitleTask = task
end sub

' Ranked list of addresses worth asking for captions, best first.
'
' This used to answer "the first add-on advertising subtitles, and prefer it
' over the built-in" — a winner decided by POSITION, in a list that has no
' position. The registry is an roAssociativeArray, so on a Roku device "the
' first" was whichever entry the hash order produced: a different pick on every
' device, and one no test in this repo could have caught because the brs
' interpreter only has a single ordering. Guest sessions escaped it because the
' two built-in seeds head the list and the winner fell out of that deterministic
' part. A stremio session is hash-ordered end to end, so it was the only session
' where the pick was arbitrary — and the symptom was the working provider
' sitting right there in the registry, never being asked.
'
' Ranked by capability now:
'   1. the official built-in, recognised by ID. The built-in is the one provider
'      proven to need no credentials, so it leads.
'   2. everything else advertising subtitles, ordered by name then id.
'
' Duplicates collapse, so a provider that answered under two records is asked
' once rather than twice.
function SubtitlesAddresses(addons as object) as object
    ranked = []
    rest = []
    if addons = invalid then return ranked
    for each addon in addons
        if addon <> invalid and addon.address <> invalid and addon.address <> ""
            if addon.resources <> invalid and m.stores.addons.callFunc("AddonsHasResource", addon.resources, "subtitles")
                if m.stores.addons.callFunc("AddonsIsBuiltin", addon.id)
                    if not AddressIn(ranked, addon.address) then ranked.Push(addon.address)
                else
                    if not AddressIn(rest, addon.address) then rest.Push(addon.address)
                end if
            end if
        end if
    end for
    SortAddressesByName(rest)
    for each address in rest
        ranked.Push(address)
    end for
    return ranked
end function

function AddressIn(list as object, address as string) as boolean
    if list = invalid then return false
    for each entry in list
        if entry = address then return true
    end for
    return false
end function

' Insertion sort so the tail of the candidate list is ordered by something the
' screen controls outright, rather than by however the registry happened to
' iterate.
sub SortAddressesByName(list as object) as void
    for i = 1 to list.Count() - 1
        item = list[i]
        j = i - 1
        while j >= 0
            if not (list[j] > item) then exit while
            list[j + 1] = list[j]
            j = j - 1
        end while
        list[j + 1] = item
    end for
end sub

' One provider answered. Its tracks are APPENDED to whatever earlier providers
' contributed, and the drain continues: the ranking decides the order tracks
' appear in and which provider's pick wins by default, not which provider gets to
' be the only one with a say. First-hit-wins meant a perfectly good second
' provider was never asked, so a user with one flaky add-on and one good one
' sometimes got captions and sometimes did not, with nothing on screen to explain
' which.
'
' Two properties make append-only safe rather than merely different:
'
'   m.subtitleIndex is chosen ONCE, on the first provider that yields tracks, and
'   never recomputed. Later providers only push to the end of the list, so every
'   index the user could already be looking at still means the same track. A
'   re-pick per provider would renumber the list underneath a selection the user
'   had already made, silently switching them to a different caption.
'
'   BuildSubtitleTracks numbers duplicates per language as it walks the list
'   ("English 1", "English 2"), so two providers offering English produce two
'   distinguishable entries rather than two identical-looking ones. No dedup is
'   wanted: the same caption offered twice is not an error, and dropping the
'   second copy would make the count depend on provider order.
sub onSubtitleResult(event as object)
    if m.subtitleTask = invalid then return
    task = event.GetRoSGNode()
    if task = invalid then return
    if task.id <> m.subtitleTask.id then return
    result = event.GetData()

    ' An empty result means "not yet", not "nothing to report": `result` is
    ' alwaysNotify with no value, so it also notifies before this worker wrote
    ' anything, and that notification is dispatched on the event loop — i.e. while
    ' the request is still in flight. Reaping here unobserves the field and
    ' removes the node, and removing a running Task does not kill its worker, so
    ' the real answer would land on a node nobody is watching. See
    ' MainScene.onAddonSyncResult for the same defect and the same fix.
    if result = invalid then return
    m.subtitleTask = invalid
    AsyncTask_Reap(task, m.top, false)

    raw = 0
    if result.subtitles <> invalid then raw = result.subtitles.Count()
    have = 0
    if m.subtitleTracks <> invalid then have = m.subtitleTracks.Count()

    ' Every outcome is reported with its classification, its attempt count and the
    ' transport's own error string. Those three together are what makes this
    ' diagnosable from a telnet trace: `kind` says whether the request could have
    ' been retried, `attempts` says whether it was, and `error` says what actually
    ' happened at the socket — none of which reached the screen before, because the
    ' only test on this branch was `not result.ok`, which cannot tell a timeout
    ' from a 404 from a malformed body.
    kind = "?"
    if result.kind <> invalid then kind = result.kind
    attempts = 0
    if result.attempts <> invalid then attempts = result.attempts
    reached = false
    if result.reached = true then reached = true
    status = -1
    if result.status <> invalid then status = result.status
    if result.reached = true then m.subtitleReached = m.subtitleReached + 1

    if not result.ok or result.subtitles = invalid or result.subtitles.Count() = 0
        print "[subs] provider gave nothing — kind=" ; kind ; " status=" ; status ; " attempts=" ; attempts ; " reached=" ; reached ; " raw=" ; raw ; " merged so far: " ; have

        ' An empty list from a provider that DID answer is not a fault and gets no
        ' toast: the add-on was asked a well-formed question about this title and
        ' reported it holds no captions, which is an answer, not a failure. Only a
        ' provider that never got to answer is worth apologising for, and by this
        ' point it has already been retried.
        ' The failure is one provider's, not subtitles as a whole: the drain keeps
        ' asking the rest of the queue and tracks merged so far stay put, so a
        ' verdict like "Could not fetch subtitles" would denounce the whole system
        ' for one add-on's answer. Say which add-on could not be reached, in terms
        ' the user would recognise — a URL on a toast reads as noise.
        if not result.ok and (kind = "retry" or kind = "server") then
            name = SubtitleProviderName(m.subtitleAsked)
            if name = "" then
                ShowToast("One subtitle add-on could not be reached")
            else
                ShowToast("One subtitle add-on could not be reached: " + name)
            end if
        end if

        ' This provider had nothing to give. Another candidate still queued means
        ' the search is not over: choosing the wrong provider must not read the
        ' same as owning no subtitles at all, which is exactly what made an
        ' unreachable pick indistinguishable from a device with no subtitle
        ' add-ons. Tracks already merged from an EARLIER provider are kept — a
        ' later provider coming back empty is not a reason to throw away captions
        ' the user can already see.
        if MoreSubtitleCandidates() then
            LaunchSubtitleFetch()
            return
        end if

        print "[subs] drain exhausted after " ; m.subtitleTried ; " provider(s), " ; m.subtitleReached ; " reached, " ; have ; " track(s)"

        ' The end of the drain is the only place a verdict is possible, and it needs
        ' both counts: tried = 0 means this play never had a provider to ask at
        ' all (nothing to apologise for — EnsureSubtitleProviders will resume the
        ' search if the registry is still filling), and tried > 0 with reached = 0
        ' means every provider was asked and not one of them could be reached. That
        ' last case is worth a word on screen, because the list the Options dialog
        ' shows is empty and otherwise says nothing about why.
        if m.subtitleTried > 0 and m.subtitleReached = 0 then
            ShowToast("Some subtitle add-ons could not be loaded")
        end if

        if m.subtitleTracks = invalid or m.subtitleTracks.Count() = 0 then ClearSubtitles()
        return
    end if

    ' First tracks of this play? Then this is the one provider whose preference
    ' wins the default pick.
    firstTracks = m.subtitleTracks = invalid or m.subtitleTracks.Count() = 0
    if m.subtitleTracks = invalid then m.subtitleTracks = []
    for each track in result.subtitles
        subtitleUrl = PlaybackInfo_SubtitleUrl(track)
        if subtitleUrl = "" then continue for
        ' Provider values are untyped. Normalize the fields used by the native
        ' picker so a malformed caption cannot prevent the movie from playing.
        track = { url: subtitleUrl, lang: PlaybackInfo_Text(track.lang), langName: PlaybackInfo_Text(track.langName) }
        m.subtitleTracks.Push(track)
    end for
    ' The built array is a snapshot of the raw list, so it has to be rebuilt
    ' before the newly appended tracks can reach the content node.
    m.subtitleNodesApplied = false
    if firstTracks then m.subtitleIndex = m.subtitlePicker.PickTrack(m.subtitleTracks, DeviceLocale())

    ' Everyone ranked is still worth asking, even though the list already has
    ' tracks in it.
    if MoreSubtitleCandidates() then LaunchSubtitleFetch()

    ' Playback never waits for this fetch, so a list that lands here applies to
    ' the live content node (and writes video.subtitleTrack) mid-play; the
    ' native Options dialog picks the tracks up from the updated SubtitleTracks.
    ApplySubtitleIndex(invalid)
    picked = SelectedSubtitleTrack()
    usable = "none"
    if picked <> "" then usable = "ok"
    print "[subs] LANDED " ; raw ; " from " ; RedactUrl(m.subtitleAsked) ; " on attempt " ; attempts ; "/3 — merged " ; have ; " + " ; raw ; " = " ; m.subtitleTracks.Count() ; ", picked index " ; m.subtitleIndex ; " (url " ; usable ; ")"
end sub

' IDs never reset on entry/cancel. A canceled worker can already have queued
' an event; its scalar id must never match a replacement movie/provider task.
function NextPlayerWorkerId(prefix as string) as string
    if m.workerSequence = invalid then m.workerSequence = 0
    m.workerSequence = m.workerSequence + 1
    return prefix + m.workerSequence.ToStr()
end function

sub CancelSubtitles()
    m.subtitleCandidates = []
    m.subtitleCursor = 0
    m.subtitleParams = invalid
    m.subtitleAsked = ""
    if m.subtitleTask <> invalid
        task = m.subtitleTask
        m.subtitleTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

' Drop the caption state back to none without touching the Video node's current
' config — a per-play node starts clean, so there is nothing to undo.
sub ClearSubtitles()
    m.subtitleTracks = invalid
    m.subtitleIndex = -1
    m.subtitleNodesApplied = false
    m.subtitleSelectionApplied = false
end sub

' Push the current subtitle selection onto the video's content. SubtitleTracks is
' content metadata on the ContentNode the Video plays. Roku's native player
' expects each entry as an associative array with TrackName set to the
' downloadable subtitle URL; tracks already in hand ride the node pre-play (the
' reliable sideloaded path), and a list that arrives later targets the live
' content node instead. Selection is matched from the raw list by URL because
' BuildSubtitleTracks drops entries without one, so the pick index does not
' always line up with the built array. Visibility is driven through
' globalCaptionMode (Roku's global caption setting); the native Options dialog
' takes over track selection from there.
sub ApplySubtitleIndex(content as object)
    if content = invalid then content = CurrentContent()
    if content = invalid then return

    if m.subtitleTracks = invalid or m.subtitleTracks.Count() = 0
        ' Nothing is written to the content node here, and that is the whole
        ' point. This runs on the node that is about to become m.video.content,
        ' so an empty subtitleTracks array and an empty subtitleConfig are two
        ' fields handed to the Video node for it to accept or reject on the very
        ' tick that decides whether it plays at all — and an empty collection is
        ' exactly the kind of value a node has cause to refuse. A player with no
        ' captions needs no fields set; it already starts caption-free. Writing
        ' nothing is what the rest of this sub argues for, and this path never
        ' did it.
        ' Embedded tracks and the user's global caption mode belong to Roku.
        ' A source without add-on subtitles must not switch captions off.
        return
    end if

    ' Build the track list BEFORE the content node is touched, and bail out
    ' entirely when it comes back empty. BuildSubtitleTracks drops every entry
    ' without a usable URL, so a provider can hand back a non-empty raw list
    ' that yields nothing playable — and the old order wrote that empty array
    ' onto the LIVE content node anyway, blanking the caption state of a video
    ' that was already playing. Writing nothing at all is the correct answer
    ' when there is no track to select; the player already starts caption-free.
    tracks = invalid
    if not m.subtitleNodesApplied then tracks = BuildSubtitleTracks()
    if tracks <> invalid and tracks.Count() = 0 then
        m.subtitleNodesApplied = false
        ClearSubtitles()
        return
    end if
    if tracks <> invalid
        content.subtitleTracks = tracks
        m.subtitleNodesApplied = true
    end if

    ' Later providers append choices only. Reapplying the original default
    ' would override a user who chose another track or Off in Roku Options.
    if m.subtitleSelectionApplied then return
    if m.hasPlayed and m.video <> invalid and m.video.HasField("subtitleTrack") then
        if PlaybackInfo_Text(m.video.subtitleTrack) <> "" then
            m.subtitleSelectionApplied = true
            return
        end if
    end if

    selected = SelectedSubtitleTrack()
    if selected = ""
        return
    end if

    content.subtitleConfig = { TrackName: selected }
    SelectSubtitleTrack(selected)
    ' Choosing an available track must not change Roku's global caption mode.
    ' Off, On and Instant replay remain the user's choices in native Options.
    m.subtitleSelectionApplied = true
end sub

' The TrackName URL of the picked raw track — the same URL BuildSubtitleTracks
' wrote into the built array — or "" when there is nothing to select.
function SelectedSubtitleTrack() as string
    if m.subtitleTracks = invalid then return ""
    if m.subtitleIndex < 0 or m.subtitleIndex >= m.subtitleTracks.Count() then return ""
    rawTrack = m.subtitleTracks[m.subtitleIndex]
    if rawTrack = invalid then return ""
    return PlaybackInfo_SubtitleUrl(rawTrack)
end function

' The content node currently driving the player, or invalid before StartPlayback.
function CurrentContent() as object
    if m.video <> invalid then return m.video.content
    return invalid
end function

' Live-node track switch for lists applied after playback has begun:
' Video.subtitleTrack is the documented read/write field that selects a track on
' the fly. Before play the ContentNode carries the tracks, so this is a no-op
' there.
sub SelectSubtitleTrack(trackName as string)
    if m.video = invalid then return
    if not m.video.HasField("subtitleTrack") then return
    if trackName = "" then return
    m.video.subtitleTrack = trackName
end sub

function BuildSubtitleTracks() as object
    tracks = []
    if m.subtitleTracks = invalid then return tracks
    languageCounts = {}
    for each track in m.subtitleTracks
        subtitleUrl = PlaybackInfo_SubtitleUrl(track)
        if subtitleUrl = "" then
            continue for
        end if

        language = TrackDisplayName(track)
        count = 1
        if languageCounts.DoesExist(language) then count = languageCounts[language] + 1
        languageCounts[language] = count

        ' Roku's native Video expects subtitleTracks as an array of associative
        ' arrays. TrackName must be the downloadable subtitle URL; Url plus
        ' ContentNode children are not reliably enumerated by the native menu.
        tracks.Push({
            Language: m.subtitlePicker.TrackLang(track)
            Description: language + " " + count.ToStr()
            TrackName: subtitleUrl
        })
    end for
    return tracks
end function

function TrackDisplayName(track as object) as string
    if Type(track) = "roAssociativeArray"
        name = PlaybackInfo_Text(track.langName)
        if name <> "" then return name
        language = PlaybackInfo_Text(track.lang)
        if language <> "" then return language
    end if
    return "Captions"
end function

' The Roku locale for the default caption pick, e.g. "es_ES"; a two-letter
' prefix is what SubtitlesStore.PickTrack matches against the tracks.
function DeviceLocale() as string
    device = CreateObject("roDeviceInfo")
    if device <> invalid
        locale = device.GetCurrentLocale()
        if locale <> invalid then return locale.ToStr()
    end if
    return ""
end function

sub CustomizeVideoNode()
    if m.video = invalid then return
    ' trickPlayBar is a member READ, and a read of a member the running Roku OS
    ' does not have THROWS — where a set of a missing member (see
    ' enablePositionTracking in StartPlayback) only warns and is discarded. The
    ' throw used to land here, inside CreateVideo, which runs BEFORE
    ' m.video.content is assigned: the player was therefore never handed a URL
    ' at all. What that looks like from the room is the resolve logo pulse ending
    ' on schedule and then nothing playing, with no message, because nothing
    ' failed that anything was watching — the buffer indicator is hidden by the
    ' "finished"/"stopped" state handler, and direct streams and torrents fail
    ' identically because neither ever reached the player.
    '
    ' Guarded with HasField and additionally wrapped, because a trick-play bar
    ' tint is decoration and decoration is not
    ' allowed to be the reason a video does not start. On a Roku OS that does have
    ' trickPlayBar this changes nothing.
    if not m.video.HasField("trickPlayBar") then return
    try
        m.video.trickPlayBar.filledBarBlendColor = Theme().accent
    catch e
        ' Decoration only. A tint this firmware will not take is not a reason to
        ' refuse playback.
    end try
end sub

' The Video node is declared in XML so Roku owns its native UI lifecycle. The
' screen is a static child reused across plays, so the node outlives a pop and is
' re-armed here on every play.
sub CreateVideo()
    if m.video = invalid then return
    m.video.visible = true
    CustomizeVideoNode()
end sub

' The resolved URL is the only thing that ever touches the Video node: build the
' content (title, resume offset, resolved stream format), then play. Captions do
' not gate playback — a list already in hand rides the content pre-play, and a
' result still in flight applies to the live node the moment it lands.
'
' The format is resolved by PlaybackStore and rides the resolve result, the same
' one path a direct URL and a torrent take. It must not be re-sniffed here: Roku
' defaults an unset streamFormat to MP4, so an MKV or an HLS manifest handed over
' with nothing declared buffers and then errors.
sub StartPlayback(url as string, streamFormat = "" as string)
    m.status.text = "Starting playback…" + Chr(10) + "Back returns to sources"
    m.playArmed = false
    if m.playTimer <> invalid then m.playTimer.control = "stop"
    if m.video = invalid then return
    ' This Video is reused. An explicit choice from the last file outranks
    ' language preferences, so every new handoff returns to native selection
    ' while the old content is stopped. This never runs during an accepted
    ' movie's normal pause, buffering, seek or metadata changes.
    m.audioGuardActive = false
    m.video.mute = true
    m.video.control = "stop"
    if m.video.HasField("audioTrack") then m.video.audioTrack = ""
    ' Native seamless changes apply to HLS with the same audio format only.
    ' Configure before the new content/play commands, and clear the previous
    ' item's setting for progressive or other transports.
    if m.video.HasField("seamlessAudioTrackSelection") then m.video.seamlessAudioTrackSelection = LCase(streamFormat.Trim()) = "hls"
    m.playingSegment = invalid
    m.devicePlaybackInfo = ReadDevicePlaybackInfo()
    CreateVideo()
    m.video.autoplayAfterSeek = true
    if m.video.HasField("enableDecoderStats") then m.video.enableDecoderStats = true
    m.audioGuardActive = true
    m.audioGuardArmed = false
    m.audioChoiceMade = false
    m.audioGuardBlocked = false
    m.audioLogSignature = ""
    m.lastEnglishTrack = ""
    BeginAudioRecovery()
    m.video.mute = true
    if m.audioGuardTimer <> invalid then m.audioGuardTimer.control = "stop"
    ' Roku OS 12.5+ handles language matching and supported-track selection.
    ' This preference cannot supply English when a file has no English track.
    if m.video.HasField("audioSelectionPreferences")
        m.video.audioSelectionPreferences = {
            values: [{ language: ["en-US", "en-GB", "en-UK", "en", "en-*"] }, { descriptive: "false" }]
            overrideSystem: true
        }
    end if

    content = CreateObject("roSGNode", "ContentNode")
    content.url = url
    ' A fresh, video-only HTTP agent prevents one provider's headers/cookies
    ' leaking into another media item or into metadata/add-on requests.
    httpAgent = CreateObject("roHttpAgent")
    m.video.SetHttpAgent(httpAgent)
    content.httpCertificatesFile = "common:/certs/ca-bundle.crt"
    content.httpSendClientCertificates = false
    content.httpHeaders = []
    if m.playParams <> invalid and m.playParams.diagnosticControl <> true
        content.audioWhitelist = "en,eng"
        ' Do not narrow the published renditions to one codec. An inspected
        ' AAC track can still fail natively, and the same file's English MP3
        ' or PCM alternative must remain visible for bounded track recovery.
    end if
    if m.resolvedPlayback <> invalid and Type(m.resolvedPlayback.headers) = "roArray" then
        content.httpHeaders = m.resolvedPlayback.headers
    end if
    params = m.playParams
    content.title = PlaybackInfo_Text(params.name)
    startOffset = PlaybackInfo_ResumeOffset(params.position)
    if startOffset > 0 then content.playStart = startOffset
    if streamFormat <> "" then content.streamFormat = streamFormat

    ' Guarded for the same reason trickPlayBar is, and because the warning this
    ' used to print on every single play ("Tried to set nonexistent field
    ' enablepositiontracking") was the loudest thing in the console and buried
    ' anything real. A set of a missing field is discarded, so losing it costs
    ' nothing; position still reads back, it just is not tracked by the node.
    if m.video.HasField("enablePositionTracking") then m.video.enablePositionTracking = true
    ApplySubtitleIndex(content)
    m.video.content = content
    m.video.SetFocus(true)

    ' Play is asked for on the NEXT tick, not this one. Handing the node its
    ' content and its control in the same tick lets it act on `control` before it
    ' has taken the content in, and the symptom of that is precisely the one
    ' being chased: the buffer indicator comes up, the node goes straight to a
    ' terminal state, and nothing plays with no error anywhere to find. A
    ' one-shot timer is a guaranteed tick boundary. m.playArmed makes it at most
    ' one kick per StartPlayback, and disarms a kick still in flight when a new
    ' play starts before it lands.
    ' Armed through `control`, not Start()/Stop(): an roSGNode Timer has no such
    ' methods and calling one is a runtime &hf4 "Member function not found",
    ' which is what the first version of this did — thrown inside StartPlayback,
    ' so the player died on the one function that must never throw.
    m.playArmed = true
    if m.playTimer <> invalid
        m.playTimer.control = "stop"
        m.playTimer.control = "start"
    else
        m.playArmed = false
        m.video.control = "play"
    end if
end sub

' The deferred half of StartPlayback. Kept to the one assignment it exists for,
' so a failure in it cannot be anything else.
sub onPlayKickFire()
    if not m.playArmed then return
    m.playArmed = false
    if m.video = invalid then return
    if m.video.content = invalid then return
    m.video.control = "play"
end sub

' The stream format is resolved by PlaybackStore.ResolvePlayback, not sniffed
' here — see StartPlayback for why an unset format is not a safe default.

' Surface playback state on the status line for the grab-before-video resolve
' phase and for failures: a broken stream is a message, not a silent black
' frame. The native chrome owns everything once the platform has a stream.
sub onVideoStateChanged()
    if m.video = invalid or m.playbackActive <> true then return
    if m.retryPending = true or m.audioGuardBlocked = true then return
    state = m.video.state
    if state = invalid then return
    onEnglishAudioFactsChanged()
    if state = "playing"
        m.naturalEnd = false
        if m.nextEpisodePending = true then CancelNextEpisode()
        ' A physical Play press after a paused voice seek restores the normal
        ' native remote seek behavior for later playback.
        m.video.autoplayAfterSeek = true
        m.status.text = ""
        HideBuffering()
        HidePlaybackInfo()
        onPlaybackFactsChanged()
        onEnglishAudioFactsChanged()
        if m.audioGuardActive and m.video.mute and not m.audioGuardArmed
            m.audioGuardArmed = true
            if m.audioGuardTimer <> invalid then m.audioGuardTimer.control = "start"
        end if
    else if state = "error"
        m.audioGuardActive = false
        if m.audioGuardTimer <> invalid then m.audioGuardTimer.control = "stop"
        ' Show the platform's error code on the status line; the diagnosis itself
        ' (category/errcode/dbgmsg) is printed by LogVideoError below. The status
        ' line alone cannot tell a network drop from a format the device refuses,
        ' but a capability verdict (unsupported container/codec on THIS box) gets
        ' its own wording so it is not blamed on the network.
        code = 0
        if m.video.HasField("errorCode") and m.video.errorCode <> invalid then code = m.video.errorCode
        category = ""
        if m.video.HasField("errorInfo") and m.video.errorInfo <> invalid then category = m.video.errorInfo.category
        message = PlaybackInfo_ErrorMessage(code, category, NotPlayableOnDevice())
        if code <> 0 then message = message + "  (code " + Str(code).Trim() + ")"
        m.status.text = message
        HideBuffering()
        HidePlaybackInfo()
        LogVideoError()
        ScheduleNextSource("native-playback-error")
    else if state = "buffering"
        StopResolvePulse()
        if HasLogo() then m.bufferingGroup.visible = true
        m.status.text = "Buffering…" + Chr(10) + "Back returns to sources"
        ' Repeated buffering notifications must not keep giving a stalled
        ' source another full deadline. The first one after accepted playback
        ' arms the rebuffer limit; startup already has its limit in progress.
        ArmSourceStartupLimit()
    else if state = "paused"
        StopSourceStartupLimit()
        if m.playParams <> invalid and m.playParams.diagnostic <> true then PublishWatchState()
        ShowPlaybackInfo()
    else if state = "finished"
        if m.sourceAccepted and m.video.HasField("duration") and m.video.HasField("position")
            duration = PlaybackInfo_ResumeOffset(m.video.duration)
            position = PlaybackInfo_ResumeOffset(m.video.position)
            ' A terminal Video node can report an absent/reset position. That
            ' cannot establish an early ending and must not restart a completed
            ' movie. A measured positive position before its end can.
            if duration > 60 and position > 0 and position < duration - 15
                ScheduleNextSource("unexpected-end")
                return
            end if
        end if
        if not m.sourceAccepted
            ScheduleNextSource("ended-before-audio")
            return
        end if
        StopSourceStartupLimit()
        if m.audioGuardTimer <> invalid then m.audioGuardTimer.control = "stop"
        m.status.text = "Playback finished." + Chr(10) + "Press Back to return to sources"
        HideBuffering()
        HidePlaybackInfo()
        m.naturalEnd = true
        ScheduleNextEpisode()
    else if state = "stopped"
        ' A fresh attempt is still allowed its resolve/play-kick deadline even
        ' if the static Video reports the previous source's stopped state.
        if m.resolveTask = invalid and m.playArmed <> true then StopSourceStartupLimit()
        if m.audioGuardTimer <> invalid then m.audioGuardTimer.control = "stop"
        HideBuffering()
        HidePlaybackInfo()
    end if
end sub

' True when the failure is this device's capability, not the network: the
' platform reports an unsupported container/codec as errorCode -5 ("unknown or
' unsupported media format") and — on the OS versions that phrase it — names it
' "no playable tracks". Either signature means no stream of this type will ever
' start on this box, so the status line says that instead of blaming the
' connection.
function NotPlayableOnDevice() as boolean
    if m.video = invalid then return false
    if m.video.HasField("errorCode") and m.video.errorCode <> invalid and m.video.errorCode = -5 then return true
    text = ""
    if m.video.HasField("errorStr") and m.video.errorStr <> invalid then text = m.video.errorStr
    if m.video.HasField("errorInfo") and m.video.errorInfo <> invalid and m.video.errorInfo.dbgmsg <> invalid then
        text = text + " " + m.video.errorInfo.dbgmsg
    end if
    text = LCase(text)
    if text.InStr("no playable tracks") >= 0 or text.InStr("not supported") >= 0 then return true
    return false
end function

' Print the platform's real verdict for a playback failure. The status line is
' one sentence for every cause — a bad container, a dropped connection, a DRM
' refusal — so a report of "it will not play" otherwise arrives with nothing to
' act on. The Video node carries the diagnosis: errorCode (-5 unknown or
' unsupported media format, -1 network, -2 timeout, -6 DRM), errorStr
' (category/errcode/source) and errorInfo (category/errcode/dbgmsg). Every read
' is guarded because a missing field on a node throws, and this is the one path
' that must not itself fail.
sub LogVideoError()
    if m.video = invalid then return
    code = 0
    if m.video.HasField("errorCode") then code = m.video.errorCode
    ' Roku error strings can embed signed URLs. Log numeric codes only.
    print "[video] error code=" ; code
    if m.video.HasField("errorInfo")
        info = m.video.errorInfo
        if info <> invalid and Type(info) = "roAssociativeArray"
            print "[video] internal error code=" ; info.errcode
        end if
    end if
end sub

sub onPlaybackFactsChanged()
    if m.video = invalid then return
    segmented = false
    if m.resolvedPlayback <> invalid then segmented = m.resolvedPlayback.streamFormat = "hls" or m.resolvedPlayback.streamFormat = "dash"
    if segmented and m.video.HasField("streamingSegment") then
        segment = m.video.streamingSegment
        if Type(segment) = "roAssociativeArray" then
            if PlaybackInfo_PositiveDimension(segment.width) and PlaybackInfo_PositiveDimension(segment.height) then m.playingSegment = segment
        end if
    end if
    if m.video.state = "paused" then ShowPlaybackInfo()
    onEnglishAudioFactsChanged()
end sub

function CurrentEnglishAudioFacts() as object
    ' The static Video retains old read-only track facts while a new file loads.
    ' Only facts from active playback may authorize sound for the new source.
    if m.video = invalid then return {verified:false,reason:"loading",englishTracks:[]}
    state = m.video.state
    if state <> "playing" and state <> "paused" and (state <> "buffering" or m.sourceAccepted <> true) then return {verified:false,reason:"loading",englishTracks:[]}
    tracks = invalid
    selected = invalid
    codec = invalid
    mode = "projector"
    if m.playParams <> invalid and m.playParams.audioMode = "surround" then mode = "surround"
    if m.video <> invalid
        if m.video.HasField("availableAudioTracks") then tracks = m.video.availableAudioTracks
        if m.video.HasField("currentAudioTrack") then selected = m.video.currentAudioTrack
        if m.video.HasField("audioFormat") then codec = m.video.audioFormat
    end if
    tracksUnavailable = Type(tracks) <> "roArray"
    if Type(tracks) = "roArray" then tracksUnavailable = tracks.Count() = 0
    result = EnglishAudio_Check(tracks, selected, codec, mode)
    if not result.verified and (m.sourceAccepted <> true or m.audioExplicitRejection <> true) and Type(m.resolvedPlayback) = "roAssociativeArray" and Type(m.resolvedPlayback.audioPolicy) = "roAssociativeArray"
        policy = m.resolvedPlayback.audioPolicy
        if policy.known = true and policy.compatible = true and policy.englishOnlyAac = true and EnglishAudio_ProjectorCodec(codec) and Left(LCase(PlaybackInfo_Text(codec)),3) = "aac" and tracksUnavailable
            result.verified = true
            result.reason = "file-English-AAC"
        end if
        if policy.known = true and policy.compatible = true and policy.englishOnlyMp3 = true and LCase(PlaybackInfo_Text(codec)) = "mp3" and tracksUnavailable
            result.verified = true
            result.reason = "file-English-MP3"
        end if
    end if
    emptyTracks = Type(tracks) <> "roArray"
    if Type(tracks) = "roArray" then emptyTracks = tracks.Count() = 0
    if not result.verified and m.sourceAccepted = true and m.audioExplicitRejection <> true and emptyTracks
        selectedId = PlaybackInfo_Text(selected)
        sameOrMissingTrack = selected = m.lastEnglishTrack
        if selectedId = "" and m.lastEnglishCodec <> invalid and m.lastEnglishCodec <> "" then sameOrMissingTrack = AudioRecovery_Codec() = m.lastEnglishCodec
        if m.lastEnglishTrack <> invalid and m.lastEnglishTrack <> "" and sameOrMissingTrack and AudioRecovery_CodecAllowed(codec,mode)
            result.verified = true
            result.reason = "English-track-continuity"
        end if
    end if
    if not result.verified and m.sourceAccepted = true and m.audioExplicitRejection <> true and (state = "buffering" or state = "paused")
        temporary = result.reason = "unknown-language" or result.reason = "loading" or result.reason = "no-playable-audio"
        sameTrack = selected = m.lastEnglishTrack or PlaybackInfo_Text(selected) = ""
        emptyCodec = PlaybackInfo_Text(codec) = "" or LCase(PlaybackInfo_Text(codec)) = "none" or LCase(PlaybackInfo_Text(codec)) = "unknown"
        if temporary and sameTrack and (AudioRecovery_CodecAllowed(codec,mode) or emptyCodec)
            result.verified = true
            result.reason = "English-track-continuity"
        end if
    end if
    if m.playParams <> invalid and m.playParams.diagnosticControl = true and EnglishAudio_ProjectorCodec(codec)
        result.verified = true
        result.reason = "diagnostic-audio"
    end if
    if Type(m.devicePlaybackInfo) = "roAssociativeArray" and AudioCapabilities_ExplicitlyUnsupported(m.devicePlaybackInfo.audioCapabilities,codec)
        result.verified = false
        result.reason = "receiver-audio-unsupported"
    end if
    return result
end function

function CurrentEnglishAudioCheck() as object
    result = CurrentEnglishAudioFacts()
    if result.verified <> true or m.sourceAccepted = true then return result
    if m.audioProgressPassed = true and m.audioProvenTrack = AudioRecovery_TrackKey() and m.audioProvenCodec = AudioRecovery_Codec() then return result
    result.verified = false
    result.reason = "waiting-rendered-audio"
    return result
end function

sub onEnglishAudioFactsChanged()
    if not m.audioGuardActive or m.video = invalid or m.audioGuardBlocked then return
    AudioRecovery_SyncState()
    if m.audioRecoveryPending = true then return
    facts = CurrentEnglishAudioFacts()
    result = CurrentEnglishAudioCheck()
    signature = result.reason
    if m.video.HasField("audioFormat") then signature = signature + " / " + PlaybackInfo_Codec(m.video.audioFormat, true)
    if m.audioLogSignature <> signature
        m.audioLogSignature = signature
        print "[audio] "; signature
    end if
    ' Native English dialogue and a compatible decoder authorize provisional
    ' sound. Actual advancing samples are required before accepting the source,
    ' saving resume/history or remembering it. This avoids depending on mute
    ' semantics to produce positionInfo.audio on untested firmware.
    if m.sourceAccepted <> true then m.video.mute = facts.verified <> true
    if m.sourceAccepted = true
        mode = "projector"
        if Type(m.playParams) = "roAssociativeArray" and m.playParams.audioMode = "surround" then mode = "surround"
        if facts.verified = true
            m.video.mute = false
            m.audioExplicitRejection = false
            if AudioRecovery_TrackId() <> "" then m.lastEnglishTrack = AudioRecovery_TrackId()
            if AudioRecovery_CodecAllowed(AudioRecovery_Codec(),mode) then m.lastEnglishCodec = AudioRecovery_Codec()
        end if
        explicitFailure = facts.reason = "non-english" or facts.reason = "non-dialogue-audio" or facts.reason = "projector-codec" or facts.reason = "unsupported-audio" or facts.reason = "receiver-audio-unsupported"
        explicitTrackChange = facts.verified <> true and AudioRecovery_TrackId() <> "" and AudioRecovery_TrackId() <> m.lastEnglishTrack
        if explicitTrackChange then explicitFailure = true
        if explicitFailure or explicitTrackChange then m.audioExplicitRejection = true
        if m.video.state = "playing" and facts.reason = "no-playable-audio" then explicitFailure = true
        liveCodec = AudioRecovery_Codec()
        if liveCodec <> "" and liveCodec <> "none" and liveCodec <> "unknown" and not AudioRecovery_CodecAllowed(liveCodec,mode)
            explicitFailure = true
            m.audioExplicitRejection = true
        end if
        if m.video.state = "playing" and liveCodec = "none" then explicitFailure = true
        if explicitFailure
            m.video.mute = true
            m.status.text = "The selected audio track is unavailable or not English. Use Audio to change tracks."
        end if
        ' Missing track facts during buffering, pause or seek do not replace an
        ' already accepted movie or silently change its selected audio track.
        if m.audioGuardTimer <> invalid then m.audioGuardTimer.control = "stop"
        m.audioGuardArmed = false
        StopAudioRecoveryTimers()
        if facts.verified = true and m.video.state = "playing"
            StopSourceStartupLimit()
            m.status.text = ""
        end if
        return
    end if
    if result.verified
        if m.video.state = "playing" then StopSourceStartupLimit()
        m.sourceAccepted = true
        m.hasPlayed = true
        m.lastEnglishCodec = AudioRecovery_Codec()
        StopAudioRecoveryTimers()
        if m.video.state = "playing" and m.sourceProofTimer <> invalid and m.sourceProofWritten <> true and m.sourceProofArmed <> true
            m.sourceProofArmed = true
            m.sourceProofTimer.control = "start"
        end if
        if m.video.HasField("currentAudioTrack") and m.video.currentAudioTrack <> "" then m.lastEnglishTrack = m.video.currentAudioTrack
        if m.audioGuardTimer <> invalid then m.audioGuardTimer.control = "stop"
        m.audioGuardArmed = false
        if m.video.state = "playing" then m.status.text = ""
    else if m.video.state = "playing"
        m.status.text = "Checking English audio…" + Chr(10) + "Back cancels"
        ArmAudioProgress()
        if not m.audioGuardArmed
            m.audioGuardArmed = true
            if m.audioGuardTimer <> invalid then m.audioGuardTimer.control = "start"
        end if
    end if
end sub

sub onEnglishAudioTimeout()
    if not m.audioGuardActive or m.video = invalid or m.audioGuardBlocked then return
    if m.sourceAccepted = true then return
    if m.video.state <> "playing"
        AudioRecovery_SyncState()
        return
    end if
    result = CurrentEnglishAudioCheck()
    if result.verified
        onEnglishAudioFactsChanged()
        return
    end if
    if QueueAudioTrackRepair() then return
    if m.playbackActive and m.sourceQueue <> invalid and m.sourceQueue.Count() > 0
        ScheduleNextSource(result.reason)
        return
    end if
    m.audioGuardBlocked = true
    print "[audio] English-only playback blocked: "; result.reason
    m.video.mute = true
    m.video.control = "pause"
    m.video.visible = false
    m.top.SetFocus(true)
    m.status.text = "English audio could not be confirmed. Press Back and choose another source."
    if result.reason = "projector-codec" or result.reason = "no-playable-audio"
        m.status.text = "No compatible English audio selected. Choose an English AAC source for projector speakers. Press Back."
    end if
    if result.englishTracks.Count() > 0 and not m.audioChoiceMade then ShowEnglishAudioChoice(result.englishTracks)
end sub

' The native user picker remains available if no automatic source queue exists.
sub ShowEnglishAudioChoice(tracks as object)
    scene = m.top.getScene()
    if scene = invalid or scene.dialog <> invalid then return
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    if dialog = invalid then return
    m.audioChoices = []
    buttons = []
    for each track in tracks
        if m.audioChoices.Count() < 8
            m.audioChoices.Push(track)
            label = "English track " + m.audioChoices.Count().ToStr()
            name = LCase(PlaybackInfo_Text(track.Name))
            if name.InStr("aac") >= 0 then label = label + " (AAC)"
            if name.InStr("ac3") >= 0 or name.InStr("ac-3") >= 0 or name.InStr("dolby") >= 0 then label = label + " (Dolby)"
            buttons.Push(label)
        end if
    end for
    buttons.Push("Choose another source")
    dialog.title = "Choose English audio"
    dialog.message = ["Only tracks tagged English are listed. For projector speakers choose AAC when available."]
    dialog.buttons = buttons
    dialog.id = "englishAudioChoice"
    dialog.ObserveField("buttonSelected", "onEnglishAudioChoice")
    m.audioDialog = dialog
    scene.dialog = dialog
end sub

sub onEnglishAudioChoice()
    if m.audioDialog = invalid then return
    index = m.audioDialog.buttonSelected
    CloseEnglishAudioChoice()
    if not m.audioGuardActive or m.video = invalid then return
    if index < 0 or index >= m.audioChoices.Count() then return
    m.audioChoiceMade = true
    m.audioGuardBlocked = false
    m.audioGuardArmed = false
    ClearAudioProgress()
    m.video.mute = true
    m.video.audioTrack = m.audioChoices[index].Track
    m.video.visible = true
    m.video.SetFocus(true)
    m.video.control = "resume"
    ArmAudioProgress()
end sub

sub CloseEnglishAudioChoice()
    if m.audioDialog = invalid then return
    m.audioDialog.close = true
    m.audioDialog = invalid
end sub

sub ScheduleNextSource(reason as string)
    if m.playbackActive <> true or m.retryPending = true then return
    if m.sourceQueue = invalid then return
    if m.audioGuardBlocked = true and m.retryPending <> true then return
    StopAudioRecoveryTimers()
    m.audioGuardActive = false
    m.audioGuardBlocked = true
    m.playArmed = false
    if m.playTimer <> invalid then m.playTimer.control = "stop"
    m.retryPending = true
    ' Quality preference is not a broken file or a network failure. A measured
    ' 1080p source may still be a good choice when the 4K-only filter is off.
    if reason <> "below-UHD" then RememberSourceFailure()
    if m.audioGuardTimer <> invalid then m.audioGuardTimer.control = "stop"
    StopSourceStartupLimit()
    if m.video <> invalid
        if m.sourceAccepted and m.video.HasField("position") and m.video.position <> invalid then m.playParams.position = m.video.position
        m.video.mute = true
    end if
    print "[auto] failed attempt "; m.sourceIndex + 1; " reason "; reason
    if m.sourceIndex + 1 >= m.sourceQueue.Count()
        m.retryPending = false
        if m.video <> invalid
            m.video.control = "stop"
            m.video.visible = false
        end if
        m.status.text = "No compatible English stream found in " + m.sourceQueue.Count().ToStr() + " attempts. Play/Pause retries; Back cancels."
        if Type(m.playParams) = "roAssociativeArray" and m.playParams.fourKOnly = true
            m.status.text = "No compatible English 4K source found in " + m.sourceQueue.Count().ToStr() + " attempts. Play/Pause retries; Back cancels."
        end if
        m.top.SetFocus(true)
        return
    end if
    m.status.text = "Trying another English audio source automatically…" + Chr(10) + "Back cancels"
    if Type(m.playParams) = "roAssociativeArray" and m.playParams.fourKOnly = true
        m.status.text = "Trying another English 4K source automatically…" + Chr(10) + "Back cancels"
    end if
    if m.retryTimer <> invalid then m.retryTimer.control = "start"
end sub

' Tasks are launched from a timer, never from a native Video observer stack.
sub onAutoSourceRetry()
    if not m.playbackActive or not m.retryPending then return
    if m.sourceQueue = invalid or m.sourceIndex + 1 >= m.sourceQueue.Count() then return
    m.retryPending = false
    CancelResolve()
    ResetVideoNode()
    m.sourceIndex = m.sourceIndex + 1
    m.playParams.stream = m.sourceQueue[m.sourceIndex]
    m.playbackActive = true
    m.sourceAccepted = false
    m.status.text = AutoPlayback_Status(m.sourceIndex, m.sourceQueue.Count(), m.playParams.stream) + Chr(10) + "Back cancels"
    StartResolve(m.playParams.stream, m.playParams.serverAddress, ResolveOrdinal(m.playParams.season), ResolveOrdinal(m.playParams.episode))
    ArmSourceStartupLimit(true)
end sub

' The Timer has no documented running field. Track its ownership explicitly:
' one attempt gets one startup deadline, and one continuous rebuffer gets one
' rebuffer deadline. A source change must force a fresh deadline; ordinary
' buffering notifications may only arm an inactive one.
sub ArmSourceStartupLimit(force = false as boolean)
    if m.startupLimit = invalid then return
    if force <> true and m.startupLimitArmed = true then return
    m.startupLimitArmed = true
    m.startupLimit.control = "stop"
    m.startupLimit.control = "start"
end sub

sub StopSourceStartupLimit()
    m.startupLimitArmed = false
    if m.startupLimit <> invalid then m.startupLimit.control = "stop"
end sub

sub onSourceStartupTimeout()
    ' An already queued fire must not restart playback after Back, pause,
    ' acceptance, or another failure that is already being retried.
    if m.startupLimitArmed <> true then return
    StopSourceStartupLimit()
    if m.playbackActive <> true or m.retryPending = true or m.audioGuardBlocked = true then return
    if m.video <> invalid and m.sourceAccepted = true
        state = m.video.state
        if state = "playing" or state = "paused" or state = "finished" or state = "stopped" then return
    end if
    ScheduleNextSource("startup-or-buffering-timeout")
end sub

function PlaybackStatus() as object
    state = "idle"
    codec = "Not reported"
    if m.video <> invalid
        if m.video.HasField("state") then state = m.video.state
        if m.video.HasField("audioFormat") then codec = PlaybackInfo_Codec(m.video.audioFormat, true)
    end if
    audio = CurrentEnglishAudioCheck()
    media = invalid
    if m.resolvedPlayback <> invalid then media = m.resolvedPlayback.media
    format = ""
    if m.resolvedPlayback <> invalid then format = m.resolvedPlayback.streamFormat
    diagnostic = false
    if m.playParams <> invalid then diagnostic = m.playParams.diagnostic = true
    position = 0
    videoCodec = "Not reported"
    muted = true
    samples = {}
    if m.video <> invalid
        if m.video.HasField("position") then position = PlaybackInfo_ResumeOffset(m.video.position)
        if m.video.HasField("mute") then muted = m.video.mute
        if m.video.HasField("videoFormat") then videoCodec = PlaybackInfo_Codec(m.video.videoFormat)
        if m.video.HasField("positionInfo") and Type(m.video.positionInfo) = "roAssociativeArray"
            samples.audio = PlaybackInfo_ResumeOffset(m.video.positionInfo.audio)
            samples.video = PlaybackInfo_ResumeOffset(m.video.positionInfo.video)
        end if
    end if
    if state <> "playing" and state <> "paused"
        position = 0
        samples = {}
        codec = "Not reported"
        videoCodec = "Not reported"
    end if
    segment = PlaybackInfo_Segment(m.playingSegment)
    remembered = false
    if Type(m.playParams) = "roAssociativeArray" then remembered = m.playParams.rememberedSource = true
    return {rememberedSource:remembered,memorySaved:m.memorySaved = true,device:m.devicePlaybackInfo,segment:segment,position:position,videoCodec:videoCodec,muted:muted,samples:samples,diagnostic:diagnostic,inspection:NativeMedia_Reason(media),format:format,state:state,audioCodec:codec,englishVerified:audio.verified,audioReason:audio.reason,englishTrackCount:audio.englishTracks.Count(),attempt:m.sourceIndex + 1,retrying:m.retryPending,resolution:NativeMedia_Resolution(media),active:m.playbackActive}
end function

sub ShowPlaybackInfo()
    if m.playbackInfoGroup = invalid or m.playbackInfoText = invalid or m.video = invalid then return
    delivery = "Direct HTTP/HTTPS; no app transcoding"
    if m.resolvedPlayback <> invalid and m.resolvedPlayback.mode = "server" then delivery = "External server; served quality may differ"
    stream = invalid
    if m.playParams <> invalid then stream = m.playParams.stream
    videoCodec = invalid
    audioCodec = invalid
    if m.video.HasField("videoFormat") then videoCodec = m.video.videoFormat
    if m.video.HasField("audioFormat") then audioCodec = m.video.audioFormat
    nl = Chr(10)
    media = invalid
    if m.resolvedPlayback <> invalid then media = m.resolvedPlayback.media
    m.playbackInfoText.text = NativeMedia_Resolution(media) + nl + "Delivery: " + delivery + nl + "Source: " + PlaybackInfo_SourceLabel(stream) + nl + PlaybackInfo_Segment(m.playingSegment) + nl + "Video: " + PlaybackInfo_Codec(videoCodec) + nl + "Audio: " + PlaybackInfo_Codec(audioCodec, true) + nl + PlaybackInfo_DeviceFacts(m.devicePlaybackInfo) + nl + "Audio codec alone does not verify 5.1 or Atmos." + nl + "HDMI output resolution does not verify source resolution."
    m.playbackInfoGroup.visible = true
end sub

' Read-only local checks. Unsupported methods must not prevent a source from
' playing, and one failed check must not erase the other available facts.
function ReadDevicePlaybackInfo() as object
    facts = {audioCapabilities:AudioCapabilities_ReadDevice()}
    device = invalid
    try
        device = CreateObject("roDeviceInfo")
    catch e
        return facts
    end try
    if device = invalid then return facts
    try
        facts.outputMode = device.GetVideoMode()
    catch e
    end try
    try
        capability = device.CanDecodeVideo({ codec: "hevc" })
        if Type(capability) = "roAssociativeArray" then facts.hevcSupported = capability.result
    catch e
    end try
    try
        display = device.GetDisplayProperties()
        if Type(display) = "roAssociativeArray" then facts.hdr10Supported = display.hdr10
    catch e
    end try
    return facts
end function

sub HidePlaybackInfo()
    if m.playbackInfoGroup <> invalid then m.playbackInfoGroup.visible = false
end sub

' Native playback owns every remote key once a Video exists: the platform's
' pause screen, seek/trick-play, and Options (captions) dialog all handle their
' own keys when this handler lets them through, so nothing is intercepted and
' every key except Back falls through to the focused Video node.
'
' Before the stream resolves (or after a failure) there is no video: Back still
' pops (OnBackPressed returns false) and every other key is swallowed so a
' press routes nowhere else. Everything else falls through (Back reaches the
' stack → stop + save + pop).
function OnKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "play" and m.playbackActive and m.sourceQueue <> invalid and m.sourceIndex + 1 >= m.sourceQueue.Count() and m.audioGuardBlocked
        m.sourceIndex = -1
        m.retryPending = true
        if m.retryTimer <> invalid then m.retryTimer.control = "start"
        return true
    end if
    if m.video = invalid
        if key = "back" then return false
        return true
    end if
    return false
end function

' The buffering logo tracks Video.bufferingStatus for real: percentage (0-100)
' is "% buffering complete", reported on every segment fetch, so the left-to-right
' reveal mirrors actual throughput — a fast stream fills fast, a slow one crawls.
' The field turns invalid the moment buffering finishes (including rebuffers), so
' that is the "done" signal: hide and rewind the clip.
sub onBufferingStatusChanged()
    if m.video = invalid or m.playbackActive <> true then return
    if m.retryPending = true or m.audioGuardBlocked = true then return
    status = m.video.bufferingStatus
    if status = invalid
        HideBuffering()
        return
    end if
    if Type(status) <> "roAssociativeArray" then return
    pct = status.percentage
    kind = Type(pct)
    if kind <> "Integer" and kind <> "roInt" and kind <> "roInteger" and kind <> "Float" and kind <> "roFloat" and kind <> "Double" and kind <> "roDouble" then pct = 0
    if pct < 0 then pct = 0
    if pct > 100 then pct = 100
    if m.logoFront <> invalid then m.logoFront.clippingRect = [0, 0, Int(900 * pct / 100), 506]
    ' This is the platform's buffer completion, not a measured download speed
    ' or decoded resolution. Keep it legible even when a title has no logo.
    if m.video.state = "buffering" then m.status.text = "Buffering " + Int(pct).ToStr() + "%…" + Chr(10) + "Back returns to sources"
end sub

function HasLogo() as boolean
    if m.logoBack = invalid then return false
    return m.logoBack.uri <> invalid and m.logoBack.uri <> ""
end function

sub HideBuffering()
    if m.logoFront <> invalid then m.logoFront.clippingRect = [0, 0, 0, 506]
    if m.bufferingGroup <> invalid then m.bufferingGroup.visible = false
end sub

' Back records the position (while the node can still report one) and declines,
' so the stack pops. The stop itself is OnExit's business, which runs before the
' screen is hidden.
function OnBackPressed() as boolean
    CancelNextEpisode()
    if m.video = invalid then return false
    SavePosition()
    return false
end function

' Leaving cancels the resolve, records where we got to, and resets the Video
' node. Nothing is reaped: this screen and its node are static children of the
' Scene and survive the pop, so the next play re-arms them in CreateVideo.
function OnExit() as void
    CancelNextEpisode()
    m.playbackActive = false
    m.retryPending = false
    if m.retryTimer <> invalid then m.retryTimer.control = "stop"
    StopSourceStartupLimit()
    CancelResolve()
    CancelSubtitles()
    SavePosition()
    ResetVideoNode()
end function

' Leave the node as the next play expects to find it: stopped, and carrying
' nothing of the play that just ended.
'
' Blanking the content is the whole point. The node survives the pop, so whatever
' is still on it is what the NEXT entry starts from — and the screen becomes
' visible again before anything has been resolved, with the native chrome
' (enableUI) painting content.title off whatever ContentNode is attached. That is
' why the prebuffer showed the PREVIOUS title, correcting itself only once
' StartPlayback replaced the content. Clear it here, on the way out, where the
' screen is already hidden: ScreenStack.pop sets visible = false before it calls
' OnExit, so this cannot flicker.
'
' Order matters twice over: SavePosition has already read position and duration
' off the node by the time this runs, and the stop goes before the blank so the
' node is not still holding a stream when we detach from it.
sub ResetVideoNode()
    ResetSourceProof()
    ResetAudioRecovery()
    ' Back can arrive before the deferred play tick. Cancel that tick before
    ' clearing content, otherwise it can restart a player after the screen exits.
    m.playArmed = false
    m.audioGuardActive = false
    m.audioGuardArmed = false
    m.audioGuardBlocked = false
    if m.audioGuardTimer <> invalid then m.audioGuardTimer.control = "stop"
    CloseEnglishAudioChoice()
    if m.playTimer <> invalid then m.playTimer.control = "stop"
    ' Same cross-play leak the toast nodes below are swept for: playerStatus is a
    ' static child too, and onVideoStateChanged only ever blanks it on "playing".
    ' A source that failed to resolve — or a video that reached "error" — leaves
    ' its message behind, so the next entry would open already showing the last
    ' play's verdict while the new resolve is still running. The screen is
    ' already hidden here (ScreenStack.pop sets visible = false before OnExit),
    ' so clearing it cannot flicker.
    '
    ' Before the m.video guard, not after it: this is a Label, so it exists
    ' whether or not the Video node did, and a label left holding the previous
    ' play's verdict is exactly the bug. A missing Video would fail the play
    ' anyway — that is onVideoStateChanged's "The player could not start." — but
    ' it must not also inherit stale text on the way there.
    m.status.text = ""
    HidePlaybackInfo()
    m.playingSegment = invalid
    m.resolvedPlayback = invalid
    m.devicePlaybackInfo = invalid
    HideBuffering()
    ' The fade leaves toastGroup at opacity 0 with its Animation still counting.
    ' Stopped and re-opened so the next play cannot come back to a label frozen
    ' mid-fade, or worse, be born invisible because a previous toast already drove
    ' the opacity down and this play's ShowToast lands before the timer clears it.
    if m.toastFade <> invalid then m.toastFade.control = "stop"
    if m.toastHideTimer <> invalid then m.toastHideTimer.control = "stop"
    if m.toastGroup <> invalid
        m.toastGroup.visible = false
        m.toastGroup.opacity = 1
    end if
    if m.video = invalid then return
    m.video.control = "stop"
    if m.video.HasField("audioTrack") then m.video.audioTrack = ""
    m.video.content = invalid
    ClearSubtitleTrack()
end sub

' video.subtitleTrack is a read/write selector on the LIVE node, so unlike
' SubtitleTracks (which lives on the ContentNode and goes with it) its value
' outlives the play that set it. It is inert while the next play has no tracks at
' all — the native dialog has nothing to list — but the one place it could bite
' is a play that DOES get tracks: the stale name is not among them, so it
' selects nothing at best. Cleared with the rest of the node so every play
' starts at the platform default.
sub ClearSubtitleTrack()
    if m.video = invalid then return
    if not m.video.HasField("subtitleTrack") then return
    m.video.subtitleTrack = ""
end sub

sub BlurFocus()
end sub

sub SavePosition()
    if m.playParams <> invalid and m.playParams.diagnostic = true then return
    if m.sourceAccepted = false then return
    if m.saved then return
    if m.playParams = invalid or m.playParams.videoId = invalid then return
    if m.stores = invalid then return
    ' Leaving while the stream is still buffering means nothing was actually
    ' watched — the video node cannot even report a position yet. Skip the write
    ' so an existing resume point is never clobbered with a bogus one.
    if not m.hasPlayed then return

    params = m.playParams

    ' Live channels (Stremio types "channel"/"tv") are kept out of Continue
    ' Watching on every session, by policy: a live stream has no resume point,
    ' and on a linked session a position record would also propagate a
    ' meaningless resume marker to the account. Leaving the gate out here would
    ' resurrect them through either the local stack or the server push.
    metaType = params.metaType
    if metaType = invalid then metaType = ""
    if m.stores.library.callFunc("LibraryIsChannelType", metaType) then return

    position = m.video.position
    duration = m.video.duration
    if position = invalid then position = 0
    if duration = invalid then duration = 0
    if m.naturalEnd = true and duration > 0 then position = duration

    season = 0
    if params.season <> invalid then season = params.season
    episode = 0
    if params.episode <> invalid then episode = params.episode
    name = ""
    if params.name <> invalid then name = params.name
    poster = ""
    if params.poster <> invalid then poster = params.poster
    posterShape = ""
    if params.posterShape <> invalid then posterShape = params.posterShape

    m.stores.library.callFunc("LibrarySetPosition", params.videoId, params.metaId, params.metaType, season, episode, name, poster, Int(position), Int(duration), posterShape)
    mid = ""
    if params.metaId <> invalid then mid = params.metaId
    m.stores.library.callFunc("LibraryMarkWatchedIfFinished", mid, params.videoId, Int(position), Int(duration))
    m.saved = true
    PublishWatchState()
end sub

' Publish the current playback position through the watchStateUpdate field for
' MainScene to push back to Stremio (a stremio session only). Fired on pause
' and on leave (from SavePosition); MainScene coalesces, so the last state
' always wins and at most one push is in flight at a time. Publishing is purely
' local state — the player never touches the API — and harmless in a guest
' session, where MainScene drops it.
sub PublishWatchState()
    if not m.sourceAccepted then return
    if m.playParams <> invalid and m.playParams.diagnostic = true then return
    if m.playParams = invalid or m.playParams.videoId = invalid then return
    if m.stores = invalid then return
    if m.video = invalid then return
    if not m.hasPlayed then return

    ' Same live-channel policy as SavePosition: a paused channel must not
    ' publish a position for the account push either. WatchRecord never sees
    ' the packet, so the buffer and MainScene's push stay clean.
    params = m.playParams
    metaType = ""
    if params.metaType <> invalid then metaType = params.metaType
    if m.stores.library.callFunc("LibraryIsChannelType", metaType) then return

    position = m.video.position
    duration = m.video.duration
    if position = invalid then position = 0
    if duration = invalid then duration = 0
    if m.naturalEnd = true and duration > 0 then position = duration

    name = ""
    if params.name <> invalid then name = params.name
    poster = ""
    if params.poster <> invalid then poster = params.poster

    packet = {
        videoId: params.videoId
        metaId: params.metaId
        metaType: metaType
        name: name
        poster: poster
        position: Int(position)
        duration: Int(duration)
    }
    ' Record before publishing: MainScene's observer can fire synchronously on
    ' the field write, so the shared buffer must already hold this packet when
    ' it reads.
    m.stores.watch.callFunc("WatchRecord", packet)
    m.top.watchStateUpdate = packet
end sub
