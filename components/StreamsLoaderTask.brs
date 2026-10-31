' StreamsLoaderTask — back one provider's stream-list fetch off the UI thread.
' The coordinator queues matching providers within its shared worker budget;
' each publishes its { streams, error } as
' soon as that one address answers. Running in a Task means a hung add-on costs
' the worker thread, not a frozen channel. The store is built fresh in the task
' scope — no object created on the render thread is shared across the thread
' boundary. providerIndex/providerName identify which provider this result
' belongs to, so the screen can route it to the right slot on completion order
' instead of task creation order.
sub init()
    m.top.functionName = "load"
end sub
sub load()
    try
        http = Transport()
        playback = PlaybackStore(http)

        streams = []
        error = ""
        answer = playback.Streams(m.top.addonAddress, m.top.metaType, m.top.videoId)
        if answer.ok and answer.streams <> invalid
            for each stream in CinemaBudgetStreams(answer.streams,m.top.candidateLimit,m.top.candidateByteLimit)
                if Type(stream) <> "roAssociativeArray" then continue for
                ' A public provider identity, never its configured secret path.
                host = LCase(m.top.addonAddress).Split("://")
                providerHost = ""
                if host.Count() > 1 then providerHost = host[1].Split("/")[0].Split("?")[0].Split("#")[0]
                stream.sourceMemoryProvider = m.top.providerId + "|" + providerHost
                streams.Push(stream)
            end for
        else if answer.error <> invalid and answer.error <> ""
            error = answer.error
        end if

        ready = CinemaChooseStreams(streams, false, m.top.audioMode, false)
        m.top.result = {
            streams: streams
            readyStreams: ready
            uhdCount: CinemaFilterReadyStreams(ready,true).Count()
            sourceDiagnostics: CinemaSkippedSources(streams)
            error: error
            providerIndex: m.top.providerIndex
            providerName: m.top.providerName
        }
    catch e
        m.top.result = {
            streams: []
            readyStreams: []
            uhdCount: 0
            error: "Source response could not be processed"
            providerIndex: m.top.providerIndex
            providerName: m.top.providerName
        }
    end try
end sub
