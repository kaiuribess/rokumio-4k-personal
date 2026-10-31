' Older installs and partial native boundaries retain existing defaults.
' Only real booleans can override them; provider configuration is not read.
function PlaybackPreferences(stores as dynamic, params = invalid as dynamic) as object
    result = {fourKOnly:false,autoNextEpisode:true,autoSourceRetry:true,waitForProviders:false,onlineSubtitles:false}
    saved = invalid
    if stores <> invalid and stores.settings <> invalid
        try
            saved = stores.settings.callFunc("SettingsGetPlaybackOptions")
        catch e
        end try
    end if
    for each source in [saved,params]
        if Type(source) <> "roAssociativeArray" then continue for
        for each key in ["fourKOnly","autoNextEpisode","autoSourceRetry","waitForProviders","onlineSubtitles"]
            kind = Type(source[key])
            if kind = "Boolean" or kind = "roBoolean" then result[key] = source[key]
        end for
    end for
    if Type(params) = "roAssociativeArray" and params.livePlayback = true
        result.fourKOnly = false:result.autoNextEpisode = false:result.onlineSubtitles = false
    end if
    return result
end function
