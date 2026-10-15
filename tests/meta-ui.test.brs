function MetaTest_Event(task as dynamic) as object
    return {
        task: task
        GetRoSGNode: function() as dynamic
            return m.task
        end function
    }
end function
sub MetaTest_Reset()
    m.reaped = []
    m.rendered = []
    m.built = []
    m.meta = { id: "ttcurrent", type: "series", name: "Current show" }
    m.metaRefreshed = false:m.episodeSnapshotSequence=0
    m.seriesMeta = invalid
    m.epHeaderLine = { text: "Loading" }
    m.epDesc = { text: "Loading episodes" }
    m.epHelp = { text: "" }
    m.seasons = []
    m.resume = invalid
    m.reloads = 0
    m.top = {}
    m.stores = {
        episodes: {
            calls: 0
            callFunc: function(name as string, current as dynamic, fetched as dynamic, episode = invalid as dynamic, meta = invalid as dynamic) as dynamic
                m.calls = m.calls + 1
                if name = "EpisodesResolveVideoId"
                    if meta <> invalid and Type(meta.videos) = "roArray"
                        for each video in meta.videos
                            if video.season = fetched and video.episode = episode then return video.id
                        end for
                    end if
                    return "fabricated-fallback"
                end if
                return { id: current.id, type: current.type, name: current.name, description: fetched.description }
            end function
        }
    }
end sub
sub AsyncTask_Reap(task as object, parent as object, doStop as boolean)
    m.reaped.Push(task.id)
end sub
sub RenderHero(meta as object)
    m.rendered.Push(meta)
end sub
sub BuildList(meta as object)
    m.built.Push(meta)
end sub
sub LoadSeries()
    m.reloads = m.reloads + 1
end sub
function ShowWatchDialog() as boolean
    return false
end function

Harness_Suite("Details completion belongs to its current worker")
MetaTest_Reset()
current = { id: "detailsMetaLoader2", result: { ok: true, meta: { id: "ttcurrent", description: "Current description" } } }
m.loadTask = current
onMetaLoaded(MetaTest_Event({ id: "detailsMetaLoader2", result: invalid }))
Harness_Equal(m.loadTask.id, "detailsMetaLoader2", "blank notification leaves Details worker alive")
Harness_Equal(m.reaped.Count(), 0, "blank Details notification not reaped")
onMetaLoaded(MetaTest_Event({ id: "detailsMetaLoader1", result: { ok: true, meta: { id: "ttold" } } }))
Harness_Equal(m.loadTask.id, "detailsMetaLoader2", "stale Details notification preserves replacement")
Harness_Equal(m.rendered.Count(), 0, "stale Details result not rendered")
onMetaLoaded(MetaTest_Event(current))
Harness_Equal(m.loadTask, invalid, "current Details completion clears slot")
Harness_Equal(m.reaped[0], "detailsMetaLoader2", "current Details worker reaped")
Harness_Equal(m.meta.description, "Current description", "current metadata merged")
Harness_Ok(m.metaRefreshed, "current Details marked refreshed")
Harness_Equal(m.rendered.Count(), 1, "current Details rendered once")
onMetaLoaded(MetaTest_Event(current))
Harness_Equal(m.rendered.Count(), 1, "duplicate Details event ignored")
MetaTest_Reset()
failed = { id: "detailsMetaLoader3", result: { ok: false, meta: invalid } }
m.loadTask = failed
onMetaLoaded(MetaTest_Event(failed))
Harness_Equal(m.meta.name, "Current show", "failed metadata retains catalog hero")
Harness_Equal(m.rendered.Count(), 0, "failed metadata not rendered")
wrong = { id: "detailsMetaLoader4", result: { ok: true, meta: { id: "ttwrong" } } }
m.loadTask = wrong
onMetaLoaded(MetaTest_Event(wrong))
Harness_Equal(m.stores.episodes.calls, 0, "wrong title cannot be merged")
bad = { id: "detailsMetaLoader5", result: { ok: true, meta: 42 } }
m.loadTask = bad
onMetaLoaded(MetaTest_Event(bad))
Harness_Equal(m.rendered.Count(), 0, "malformed metadata safely rejected")

Harness_Suite("Episodes completion belongs to the current show")
MetaTest_Reset()
current = { id: "episodesLoader2", result: { ok: true, meta: { id: "ttcurrent", videos: [{ id: "provider:opaque/episode?1", season: 1, episode: 1, name: "Pilot" }] } } }
m.loadTask = current
onSeriesLoaded(MetaTest_Event({ id: "episodesLoader2", result: invalid }))
Harness_Equal(m.loadTask.id, "episodesLoader2", "blank Episodes notification retains worker")
onSeriesLoaded(MetaTest_Event({ id: "episodesLoader1", result: { ok: true, meta: { id: "ttold" } } }))
Harness_Equal(m.loadTask.id, "episodesLoader2", "stale Episodes notification preserves replacement")
Harness_Equal(m.built.Count(), 0, "stale seasons not built")
onSeriesLoaded(MetaTest_Event(current))
Harness_Equal(m.loadTask, invalid, "current Episodes completion clears slot")
Harness_Equal(m.seriesMeta.id, "ttcurrent", "current show metadata adopted")
Harness_Equal(m.built.Count(), 1, "current season list built once")
Harness_Equal(m.meta.videos[0].id, "provider:opaque/episode?1", "fetched opaque ids retained on selection metadata")
PushEpisode(1, current.result.meta.videos[0])
Harness_Equal(m.top.pushRequest.params.videoId, "provider:opaque/episode?1", "episode selection uses exact provider id after skinny catalog entry")
onSeriesLoaded(MetaTest_Event(current))
Harness_Equal(m.built.Count(), 1, "duplicate Episodes notification ignored")
MetaTest_Reset()
failed = { id: "episodesLoader3", result: { ok: false, meta: invalid } }
m.loadTask = failed
onSeriesLoaded(MetaTest_Event(failed))
Harness_Equal(m.epDesc.text, "Series information could not be loaded.", "terminal failure displays useful status")
Harness_Equal(m.epHelp.text, "OK  Try again     Back  Return", "failed episode load exposes a direct retry")
Harness_Ok(onKeyEvent("OK", true), "OK retries empty episode browser")
Harness_Equal(m.reloads, 1, "one retry begins one load")
Harness_Equal(onKeyEvent("OK", false), false, "key release cannot repeat retry")
m.loadTask = { id: "stillLoading" }
Harness_Equal(onKeyEvent("OK", true), false, "OK cannot duplicate pending load")
Harness_Equal(m.reloads, 1, "pending load survives repeated OK")
Harness_Equal(m.built.Count(), 0, "failed metadata not used for season list")
bad = { id: "episodesLoader4", result: { ok: true, meta: "bad" } }
m.loadTask = bad
onSeriesLoaded(MetaTest_Event(bad))
Harness_Equal(m.built.Count(), 0, "malformed episode metadata rejected")
wrong = { id: "episodesLoader5", result: { ok: true, meta: { id: "ttwrong" } } }
m.loadTask = wrong
onSeriesLoaded(MetaTest_Event(wrong))
Harness_Equal(m.built.Count(), 0, "wrong series cannot replace current seasons")
Harness_Equal(EpisodesVisibleRows(0), 0, "empty series has no visible rows")
Harness_Equal(EpisodesVisibleRows(1), 1, "one season uses one visible slot")
Harness_Equal(EpisodesVisibleRows(20), 2, "many seasons scroll through two visible rows")
Harness_Finish()
if m.failed > 0
    bad = invalid
    x = bad.poison
end if
