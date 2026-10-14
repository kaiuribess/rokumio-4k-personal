' Build a fresh episode request from provider metadata, never from the previous
' media URL. Missing metadata/current episode is a safe stop, not a guessed id.
function NextEpisode_Params(params as dynamic, meta as dynamic, nowIso = "" as string) as dynamic
    if Type(params) <> "roAssociativeArray" or Type(meta) <> "roAssociativeArray" then return invalid
    if params.metaType <> "series" or params.diagnostic = true or params.autoNextEpisode = false then return invalid
    if Type(meta.videos) <> "roArray" then return invalid
    seriesId = NextEpisode_Text(params.metaId)
    if NextEpisode_Text(params.videoId) = "" then return invalid
    if seriesId = "" or (NextEpisode_Text(meta.id) <> "" and NextEpisode_Text(meta.id) <> seriesId) then return invalid
    season = NextEpisode_Ordinal(params.season)
    episode = NextEpisode_Ordinal(params.episode)
    if season = invalid or episode = invalid then return invalid
    currentFound = false
    candidate = invalid
    for each video in meta.videos
        if Type(video) <> "roAssociativeArray" then continue for
        s = NextEpisode_Ordinal(video.season)
        e = NextEpisode_Ordinal(video.episode)
        if s = invalid or e = invalid then continue for
        if s = season and e = episode
            id = NextEpisode_Text(video.id)
            if id = "" or id = NextEpisode_Text(params.videoId) then currentFound = true
        end if
        ' Regular seasons never roll into specials; specials stay in season 0.
        if season = 0 and s <> 0 then continue for
        if season > 0 and s = 0 then continue for
        if s < season or (s = season and e <= episode) then continue for
        if candidate = invalid
            candidate = {video:video,season:s,episode:e}
        else if s < candidate.season or (s = candidate.season and e < candidate.episode)
            candidate = {video:video,season:s,episode:e}
        end if
    end for
    if not currentFound or candidate = invalid then return invalid
    released = NextEpisode_Text(candidate.video.released)
    if released = "" then released = NextEpisode_Text(candidate.video.firstAired)
    datePattern = CreateObject("roRegex", "^\d{4}-\d{2}-\d{2}", "")
    if datePattern.IsMatch(released) and datePattern.IsMatch(nowIso)
        if released.Left(10) > nowIso.Left(10) then return invalid
    end if
    id = NextEpisode_Text(candidate.video.id)
    if id = "" then id = seriesId + ":" + candidate.season.ToStr() + ":" + candidate.episode.ToStr()
    nextParams = {autoPlay:true,metaType:"series",metaId:seriesId,videoId:id,season:candidate.season,episode:candidate.episode,position:0,seriesMeta:meta}
    for each key in ["addonAddress", "name", "poster", "posterShape", "logo", "background", "audioMode", "fourKOnly"]
        if params[key] <> invalid then nextParams[key] = params[key]
    end for
    nextParams.episodeName = NextEpisode_Text(candidate.video.name)
    if nextParams.episodeName = "" then nextParams.episodeName = NextEpisode_Text(candidate.video.title)
    nextParams.episodeOverview = NextEpisode_Text(candidate.video.overview)
    if nextParams.episodeOverview = "" then nextParams.episodeOverview = NextEpisode_Text(candidate.video.description)
    return nextParams
end function

function NextEpisode_Text(value as dynamic) as string
    if Type(value) = "String" or Type(value) = "roString" then return value.Trim()
    return ""
end function

function NextEpisode_Ordinal(value as dynamic) as dynamic
    kind = Type(value)
    if kind = "String" or kind = "roString"
        text = value.Trim()
        if text = "" then return invalid
        ordinal = 0
        for index = 0 to text.Len() - 1
            digit = Asc(text.Mid(index, 1)) - 48
            if digit < 0 or digit > 9 then return invalid
            if ordinal > 214748364 or (ordinal = 214748364 and digit > 7) then return invalid
            ordinal = ordinal * 10 + digit
        end for
        return ordinal
    end if
    if kind <> "Integer" and kind <> "roInt" and kind <> "roInteger" and kind <> "Float" and kind <> "roFloat" and kind <> "Double" and kind <> "roDouble" and kind <> "LongInteger" and kind <> "roLongInteger" then return invalid
    try
        if value < 0 or value > 2147483647 then return invalid
        ordinal = Int(value)
        if ordinal <> value then return invalid
        return ordinal
    catch e
        return invalid
    end try
end function
