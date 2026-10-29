' Public schedules and playable streams are deliberately separate contracts.
function Sports_Leagues() as object
    return [
        {raw:"football/nfl",label:"NFL"},{raw:"basketball/nba",label:"NBA"},
        {raw:"baseball/mlb",label:"MLB"},{raw:"hockey/nhl",label:"NHL"},
        {raw:"mma/ufc",label:"UFC"},{raw:"football/college-football",label:"College football"},
        {raw:"basketball/mens-college-basketball",label:"College basketball"},
        {raw:"basketball/womens-college-basketball",label:"Women's college hoops"},
        {raw:"basketball/wnba",label:"WNBA"},{raw:"soccer/eng.1",label:"Premier League"},
        {raw:"soccer/usa.1",label:"MLS"},{raw:"soccer/esp.1",label:"La Liga"},
        {raw:"soccer/uefa.champions",label:"Champions League"}
    ]
end function

function Sports_Text(value as dynamic, limit = 160 as integer) as string
    if Type(value) <> "String" and Type(value) <> "roString" then return ""
    return value.Replace(Chr(10)," ").Replace(Chr(13)," ").Trim().Left(limit)
end function

function Sports_Url(league as string, day as string) as string
    allowed = false
    for each item in Sports_Leagues()
        if item.raw = league then allowed = true
    end for
    if not allowed or not CreateObject("roRegex","^[0-9]{8}$","").IsMatch(day) then return ""
    return "https://site.api.espn.com/apis/site/v2/sports/" + league + "/scoreboard?dates=" + day + "&limit=100"
end function

function Sports_Normalize(body as dynamic, league as string) as object
    result = {ok:false,events:[],error:"Schedule service returned an unsupported response.",skipped:0,truncated:false}
    if Type(body) <> "roAssociativeArray" then return result
    if Type(body.events) <> "roArray" then return result
    seen = {}
    count = body.events.Count()
    if count > 100 then count = 100:result.truncated = true
    digits = CreateObject("roRegex","^[0-9]{1,24}$","")
    for index = 0 to count - 1
        event = body.events[index]
        if Type(event) <> "roAssociativeArray" then result.skipped++:continue for
        id = Sports_Text(event.id,25)
        name = Sports_Text(event.name)
        if not digits.IsMatch(id) or name = "" or seen.DoesExist(id) then result.skipped++:continue for
        seen[id] = true
        status = event.status
        competition = invalid
        if Type(event.competitions) = "roArray" and event.competitions.Count() > 0 then competition = event.competitions[0]
        if Type(status) <> "roAssociativeArray" and Type(competition) = "roAssociativeArray" then status = competition.status
        state = "unknown":detail = "Status unavailable"
        if Type(status) = "roAssociativeArray" and Type(status.type) = "roAssociativeArray"
            state = Sports_Text(status.type.state,12)
            detail = Sports_Text(status.type.shortDetail)
            if detail = "" then detail = Sports_Text(status.type.description)
        end if
        phase = "Status unknown"
        if state = "pre" then phase = "Upcoming"
        if state = "in" then phase = "Live"
        if state = "post" then phase = "Completed"
        date = Sports_Text(event.date,32)
        score = ""
        if Type(competition) = "roAssociativeArray" and Type(competition.competitors) = "roArray"
            teams = []
            for each team in competition.competitors
                if teams.Count() >= 2 then exit for
                if Type(team) <> "roAssociativeArray" then continue for
                label = ""
                if Type(team.team) = "roAssociativeArray" then label = Sports_Text(team.team.abbreviation,12)
                if label <> "" and state <> "pre" then teams.Push(label + " " + Sports_Text(team.score,8))
            end for
            score = teams.Join("   ")
        end if
        result.events.Push({id:"espn_" + league.Replace("/","_") + "_" + id,name:name,state:state,phase:phase,detail:detail,date:date,score:score})
    end for
    result.ok = true:result.error = ""
    return result
end function

function Sports_StreamRequest(event as object) as object
    return {metaType:"tv",metaId:event.id,videoId:event.id,name:event.name,description:event.phase + " · " + event.detail,position:0,autoPlay:true,autoNextEpisode:false,fourKOnly:false}
end function
