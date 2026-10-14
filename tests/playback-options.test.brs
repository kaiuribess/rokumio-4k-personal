function OptionsDialog() as object
    return {buttonSelected:-1,ObserveFieldScoped:sub(field as string,callback as string)
    end sub}
end function
function OptionsEvent(node as object) as object
    return {node:node,GetRoSGNode:function() as object
        return m.node
    end function}
end function
function NextSettingsWorkerId(prefix as string) as string
    m.sequence=m.sequence+1
    return prefix+m.sequence.ToStr()
end function
sub ReportSaveFault()
end sub
sub BuildRows(preserve=false as boolean)
    m.rebuilds=m.rebuilds+1
    m.preserved=preserve
end sub
function AudioSetupValue() as string
    return "TV / projector"
end function
sub OptionsSetup()
    m.registry=MockRegistry()
    store=SettingsStore(m.registry)
    host={data:store,callFunc:function(name as string,key="" as string,value=invalid as dynamic) as dynamic
        if name="SettingsGetPlaybackOptions" then return m.data.GetPlaybackOptions()
        if name="SettingsSetPlaybackOption" then return m.data.SetPlaybackOption(key,value)
        if name="SettingsSaveFailed" then return m.data.SaveFailed()
        if name="SettingsGetAudioMode" then return m.data.GetAudioMode()
        if name="SettingsGetServerAddress" then return m.data.GetServerAddress()
        return invalid
    end function}
    m.stores={settings:host}
    m.top={scene:{dialog:invalid},getScene:function() as object
        return m.scene
    end function}
    m.list={SetFocus:sub(value as boolean)
        m.focused=value
    end sub}
    m.status={text:""}:m.sequence=0:m.rebuilds=0:m.settingsAudioDialog=invalid
end sub

Harness_Suite("Public options require explicit choices and retain saved values")
OptionsSetup()
ShowPlaybackOption("quality")
dialog=m.settingsAudioDialog
Harness_Equal(dialog.buttons.Count(),3,"quality offers both choices and Cancel")
onSettingsAudioChoice(OptionsEvent(dialog))
Harness_Ok(not m.stores.settings.data.GetPlaybackOptions().fourKOnly,"initial negative selection does not save")
dialog.buttonSelected=2:onSettingsAudioChoice(OptionsEvent(dialog))
Harness_Ok(not m.stores.settings.data.GetPlaybackOptions().fourKOnly,"Cancel does not change quality")
m.top.scene.dialog=invalid:ShowPlaybackOption("quality"):dialog=m.settingsAudioDialog
onSettingsAudioChoice(OptionsEvent({id:"old",buttonSelected:1}))
Harness_Equal(m.rebuilds,0,"stale modal cannot change preference")
dialog.buttonSelected=1:onSettingsAudioChoice(OptionsEvent(dialog))
Harness_Ok(m.stores.settings.data.GetPlaybackOptions().fourKOnly,"explicit choice enables 4K only")
Harness_Ok(SettingsStore(m.registry).GetPlaybackOptions().fourKOnly,"quality persists across store restart")
Harness_Ok(m.preserved and m.list.focused,"choice preserves row and returns remote focus")
m.top.scene.dialog=invalid:ShowPlaybackOption("autoplay"):dialog=m.settingsAudioDialog
dialog.buttonSelected=1:onSettingsAudioChoice(OptionsEvent(dialog))
Harness_Ok(not SettingsStore(m.registry).GetPlaybackOptions().autoNextEpisode,"autoplay can be disabled persistently")
m.top.scene.dialog=invalid:ShowPlaybackOption("recovery"):dialog=m.settingsAudioDialog
dialog.buttonSelected=1:onSettingsAudioChoice(OptionsEvent(dialog))
Harness_Ok(not SettingsStore(m.registry).GetPlaybackOptions().autoSourceRetry,"recovery can be disabled persistently")
m.top.scene.dialog=invalid:ShowPlaybackOption("autoStart"):dialog=m.settingsAudioDialog
dialog.buttonSelected=1:onSettingsAudioChoice(OptionsEvent(dialog))
Harness_Ok(SettingsStore(m.registry).GetPlaybackOptions().waitForProviders,"full provider comparison can be saved")
ApplyPlaybackOption("autoStart",0)
Harness_Ok(not SettingsStore(m.registry).GetPlaybackOptions().waitForProviders,"early automatic selection can be restored")
before=m.rebuilds:ApplyPlaybackOption("invalid",0):ApplyPlaybackOption("quality",2)
Harness_Equal(m.rebuilds,before,"unknown/cancel choices cannot write")
m.registry.failWrites=true:ApplyPlaybackOption("quality",0)
Harness_Ok(m.status.text.InStr("not saved")>=0,"failed persistence is visible")

Harness_Suite("Saved preferences reach actual playback requests; only booleans override")
OptionsSetup()
m.stores.settings.data.SetPlaybackOption("fourKOnly",true)
m.stores.settings.data.SetPlaybackOption("autoNextEpisode",false)
m.stores.settings.data.SetPlaybackOption("autoSourceRetry",false)
m.stores.settings.data.SetPlaybackOption("waitForProviders",true)
prefs=PlaybackPreferences(m.stores)
Harness_Ok(prefs.fourKOnly and not prefs.autoNextEpisode and not prefs.autoSourceRetry,"saved options read through native-style host boundary")
prefs=PlaybackPreferences(m.stores,{fourKOnly:"false",autoNextEpisode:1,autoSourceRetry:invalid})
Harness_Ok(prefs.fourKOnly and not prefs.autoNextEpisode and not prefs.autoSourceRetry,"wrong-type overrides cannot silently enable behavior")
prefs=PlaybackPreferences(m.stores,{fourKOnly:false,autoNextEpisode:true,autoSourceRetry:true})
Harness_Ok(not prefs.fourKOnly and prefs.autoNextEpisode and prefs.autoSourceRetry,"explicit current-title values override saved defaults")
m.params={metaType:"movie",metaId:"fixture",videoId:"fixture",position:0}
m.headTitle={text:"Fixture movie"}:m.fourKOnly=true
PushAutomaticPlayer({url:"https://example.invalid/fixture"},[])
request=m.top.pushRequest.params
Harness_Ok(request.fourKOnly,"quality reaches the player")
Harness_Ok(not request.autoNextEpisode,"disabled next episode reaches the player")
Harness_Ok(not request.autoSourceRetry,"disabled recovery reaches the player")
Harness_Ok(request.waitForProviders,"saved comparison mode reaches the episode playback handoff")
m.params.autoSourceRetry=true
PushAutomaticPlayer({url:"https://example.invalid/fixture"},[])
Harness_Ok(m.top.pushRequest.params.autoSourceRetry,"episode-scoped recovery override reaches player")
prefs=PlaybackPreferences(invalid)
Harness_Ok(not prefs.fourKOnly and prefs.autoNextEpisode and prefs.autoSourceRetry,"absent settings preserve existing defaults")
Harness_Ok(not prefs.waitForProviders,"absent settings choose early automatic selection")
Harness_Ok(not PlaybackPreferences(invalid,{waitForProviders:"true"}).waitForProviders,"wrong-type comparison override is ignored")
Harness_Ok(PlaybackPreferences(invalid,{waitForProviders:true}).waitForProviders,"explicit boolean can request full comparison")
Harness_Finish()
