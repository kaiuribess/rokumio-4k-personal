' Classification affects browsing only. Native type, ID and configured address
' remain opaque routing data. No provider-specific URLs or credentials here.
function Sports_Groups() as object
    return [
        {key:"basketball",label:"Basketball",detail:"NBA, WNBA, college and international games"},
        {key:"football",label:"American football",detail:"NFL and college football"},
        {key:"soccer",label:"Soccer",detail:"Domestic leagues and international competitions"},
        {key:"baseball",label:"Baseball",detail:"MLB and other baseball competitions"},
        {key:"hockey",label:"Ice hockey",detail:"NHL and other hockey competitions"},
        {key:"mma",label:"MMA / UFC",detail:"Mixed martial arts events"},
        {key:"boxing",label:"Boxing",detail:"Fight cards and boxing events"},
        {key:"motorsport",label:"Motorsport",detail:"Formula 1, NASCAR, MotoGP and more"},
        {key:"tennis",label:"Tennis",detail:"Tours and tournaments"},
        {key:"golf",label:"Golf",detail:"Tours and tournaments"},
        {key:"cricket",label:"Cricket",detail:"International and league cricket"},
        {key:"rugby",label:"Rugby",detail:"League and union"},
        {key:"wrestling",label:"Wrestling",detail:"Wrestling events"},
        {key:"volleyball",label:"Volleyball",detail:"Indoor and beach volleyball"},
        {key:"cycling",label:"Cycling",detail:"Races and tours"},
        {key:"darts",label:"Darts",detail:"Darts competitions"},
        {key:"snooker",label:"Snooker / pool",detail:"Cue sports"},
        {key:"esports",label:"Esports",detail:"Competitive gaming"},
        {key:"channels",label:"Sports channels",detail:"Linear channels; not necessarily live games"},
        {key:"other",label:"All / other sports",detail:"Mixed-event catalogs and uncategorized sports"}
    ]
end function

function Sports_Category(value as dynamic) as string
    text = LCase(Sports_Text(value,1024))
    if m.sportsCategoryMatchers = invalid
        rules = [
            ["basketball","basketball|nba|wnba|ncaab"], ["football","american.?football|nfl|ncaaf|college.?football"],
            ["soccer","soccer|football|premier.?league|champions.?league|la.?liga|bundesliga|mls"],
            ["baseball","baseball|mlb"], ["hockey","ice.?hockey|hockey|nhl"],
            ["mma","mma|ufc|mixed.?martial"], ["boxing","boxing"],
            ["motorsport","motor.?sports?|formula.?1|f1|nascar|motogp|racing"],
            ["tennis","tennis|atp|wta"], ["golf","golf|pga"], ["cricket","cricket"],
            ["rugby","rugby"], ["wrestling","wrestling|wwe|aew"], ["volleyball","volleyball"],
            ["cycling","cycling"], ["darts","darts"], ["snooker","snooker|billiards|pool"],
            ["esports","esports|e.sports"], ["channels","channels?|live.?tv"]
        ]
        m.sportsCategoryMatchers = []
        for each rule in rules
            m.sportsCategoryMatchers.Push({key:rule[0],pattern:CreateObject("roRegex","(^|[^a-z0-9])(" + rule[1] + ")([^a-z0-9]|$)","i")})
        end for
    end if
    for each rule in m.sportsCategoryMatchers
        if rule.pattern.IsMatch(text) then return rule.key
    end for
    return "other"
end function

function Sports_CleanEventName(value as dynamic) as string
    name = Sports_Text(value,160)
    name = CreateObject("roRegex","^[^a-z0-9]*(live|upcoming|replay|highlights)\s*:\s*","i").Replace(name,"")
    return CreateObject("roRegex","\s+","").ReplaceAll(name," ").Trim()
end function

function Sports_EventPhase(meta as object) as string
    status = LCase(Sports_Text(meta.status,40))
    if status = "live" or status = "in" then return "Live"
    if status = "upcoming" or status = "pre" or status = "scheduled" then return "Upcoming"
    if status = "postponed" or status = "cancelled" or status = "canceled" then return "Postponed / cancelled"
    if status = "replay" or status = "completed" or status = "post" then return "Replay / completed"
    name = Sports_Text(meta.name,160)
    if CreateObject("roRegex","^[^a-z0-9]*live\s*:","i").IsMatch(name) then return "Live"
    if CreateObject("roRegex","^[^a-z0-9]*upcoming\s*:","i").IsMatch(name) then return "Upcoming"
    if CreateObject("roRegex","^[^a-z0-9]*(replay|highlights)\s*:","i").IsMatch(name) then return "Replay / completed"
    return "Status unverified"
end function

' Matching is deliberately strict: a name alone (or a day without a start
' time) never folds two providers together. Unknowns stay individually usable.
function Sports_EventMatchKey(meta as object, name as string, phase as string) as string
    if phase <> "Live" and phase <> "Upcoming" and phase <> "Replay / completed" then return ""
    ' Display truncation must never manufacture matching evidence.
    if Len(Sports_Text(meta.name,2048)) > 160 then return ""
    if Len(Sports_Text(meta.competition,2048)) > 100 or Len(Sports_Text(meta.league,2048)) > 100 then return ""
    if Len(Sports_Text(meta.startTime,2048)) > 40 or Len(Sports_Text(meta.start_time,2048)) > 40 then return ""
    start = Sports_Text(meta.startTime,40)
    if start = "" then start = Sports_Text(meta.start_time,40)
    if not CreateObject("roRegex","^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z$","").IsMatch(start) then return ""
    if Len(start) = 17 then start = Left(start,16) + ":00Z"
    competition = Sports_Text(meta.competition,100)
    if competition = "" then competition = Sports_Text(meta.league,100)
    if competition = "" then return ""
    normalized = LCase(name).Replace(" vs. "," vs ").Replace(" v "," vs ").Replace(" - "," vs ")
    if normalized.InStr(" vs ") < 1 then return ""
    return FormatJson([normalized,LCase(competition),start,phase])
end function

function Sports_NormalizeCatalogItem(meta as dynamic, entry as object) as dynamic
    if Type(meta) <> "roAssociativeArray" then return invalid
    id = meta.id
    if Type(id) <> "String" and Type(id) <> "roString" then return invalid
    ' Reject rather than truncate opaque routing values.
    if Len(id) = 0 or Len(id) > 2048 then return invalid
    name = Sports_CleanEventName(meta.name)
    if name = "" then return invalid
    kind = Sports_Text(meta.type,64)
    if kind = "" then kind = entry.params.metaType
    if kind <> entry.params.metaType then return invalid
    tags = Sports_Text(meta.sport,100) + " " + Sports_Text(meta.league,100) + " " + Sports_Text(meta.competition,100)
    if Type(meta.genres) = "roArray"
        for i = 0 to meta.genres.Count() - 1
            if i >= 8 then exit for
            tags = tags + " " + Sports_Text(meta.genres[i],60)
        end for
    end if
    category = Sports_Category(tags)
    if category = "other" then category = Sports_Category(name)
    if category = "other" then category = entry.groupKey
    phase = Sports_EventPhase(meta)
    route = {addonAddress:entry.params.addonAddress,metaType:kind,metaId:id,videoId:id,name:name,provider:entry.provider,poster:Sports_Text(meta.poster,1024)}
    return {name:name,phase:phase,category:category,start:Sports_Text(meta.startTime,40),competition:Sports_Text(meta.competition,100),matchKey:Sports_EventMatchKey(meta,name,phase),routes:[route]}
end function

' Bound the transfer from Task to render thread, including malformed fields.
' Non-paginated providers are re-fetched and sliced locally on More events.
function Sports_CatalogPage(answer as dynamic, entry as object, offset as integer) as object
    result = {ok:false,events:[],nextOffset:offset,hasMore:false,skipped:0,firstId:""}
    if Type(answer) <> "roAssociativeArray" or answer.ok <> true or Type(answer.metas) <> "roArray" then return result
    result.ok = true
    if answer.rawCount <> invalid then result.skipped = answer.rawCount - answer.metas.Count()
    start = 0
    if entry.skipSupported <> true
        start = offset
        if Type(answer.rawPositions) = "roArray"
            start = 0
            while start < answer.rawPositions.Count()
                if answer.rawPositions[start] >= offset then exit while
                start++
            end while
        end if
    end if
    last = start + 48
    if last > answer.metas.Count() then last = answer.metas.Count()
    if answer.metas.Count() > 0 then result.firstId = Sports_Text(answer.metas[0].id,2048)
    for i = start to last - 1
        item = Sports_NormalizeCatalogItem(answer.metas[i],entry)
        if item = invalid then result.skipped++ else result.events.Push(item)
    end for
    consumed = last - start
    if consumed < 0 then consumed = 0
    nextOffset = offset + consumed
    if Type(answer.rawPositions) = "roArray"
        rawEnd = 0
        if last = answer.metas.Count()
            rawEnd = answer.rawCount
        else if last > 0
            rawEnd = answer.rawPositions[last-1] + 1
        end if
        if entry.skipSupported = true then nextOffset = offset + rawEnd else nextOffset = rawEnd
    end if
    result.nextOffset = nextOffset
    result.hasMore = last < answer.metas.Count()
    if entry.skipSupported = true and answer.hasMore = true and consumed > 0 then result.hasMore = true
    return result
end function

function Sports_RouteIdentity(route as object) as string
    return FormatJson([route.addonAddress,route.metaType,route.videoId])
end function

function Sports_WatchRequest(route as object, autoPlay as boolean, live as boolean, unknownAudio as boolean) as object
    return {addonAddress:route.addonAddress,metaType:route.metaType,metaId:route.metaId,videoId:route.videoId,name:route.name,poster:route.poster,position:0,autoPlay:autoPlay,fourKOnly:false,autoNextEpisode:false,onlineSubtitles:false,livePlayback:live,allowUnknownLiveAudio:unknownAudio}
end function
