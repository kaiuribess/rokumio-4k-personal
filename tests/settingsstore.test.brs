' SettingsStore unit tests.
'
' MockRegistry is shared with the other store suites (tests/mocks.brs):
' persistence is testable in the interpreter, and constructing a second store
' over the same registry must restore the saved state — that is Load().

sub Test_Settings_Defaults()
    Harness_Suite("SettingsStore defaults")
    settings = SettingsStore(invalid)

    Harness_Equal(settings.ServerAddressSet(), false, "no server address by default")
    Harness_Equal(settings.GetLanguage(), "en", "language defaults to en")
    Harness_Equal(settings.GetAudioMode(), "projector", "existing and new installs default to projector speakers")
end sub

sub Test_Settings_PlaybackOptions()
    Harness_Suite("Public playback options migrate safely and persist independently")
    registry = MockRegistry()
    registry.Write("audioMode","surround")
    settings = SettingsStore(registry)
    prefs = settings.GetPlaybackOptions()
    Harness_Ok(not prefs.fourKOnly,"existing installs retain HD alternatives by default")
    Harness_Ok(prefs.autoNextEpisode and prefs.autoSourceRetry,"existing automatic behavior is retained")
    Harness_Equal(settings.GetAudioMode(),"surround","adding options preserves speaker preference")
    Harness_Ok(settings.SetPlaybackOption("fourKOnly",true),"quality choice accepted")
    Harness_Ok(settings.SetPlaybackOption("autoNextEpisode",false),"autoplay choice accepted")
    Harness_Ok(settings.SetPlaybackOption("autoSourceRetry",false),"recovery choice accepted")
    reopened = SettingsStore(registry)
    prefs = reopened.GetPlaybackOptions()
    Harness_Ok(prefs.fourKOnly,"4K-only choice survives restart")
    Harness_Ok(not prefs.autoNextEpisode and not prefs.autoSourceRetry,"disabled choices survive restart")
    prefs.fourKOnly=false
    Harness_Ok(reopened.GetPlaybackOptions().fourKOnly,"returned plain options cannot mutate saved store")
    Harness_Ok(not reopened.SetPlaybackOption("audioMode",false),"unknown option cannot overwrite speaker setup")
    Harness_Equal(reopened.GetAudioMode(),"surround","invalid option leaves existing setting intact")
    registry.Write("fourKOnly","garbage")
    registry.Write("autoNextEpisode","0")
    registry.Write("autoSourceRetry","disabled")
    prefs=SettingsStore(registry).GetPlaybackOptions()
    Harness_Ok(not prefs.fourKOnly and prefs.autoNextEpisode and prefs.autoSourceRetry,"malformed stored values use documented defaults")
    registry.failWrites=true
    Harness_Ok(settings.SetPlaybackOption("fourKOnly",false),"refused write retains usable in-session choice")
    Harness_Ok(settings.SaveFailed(),"refused preference write is reported")
end sub

sub Test_Settings_SetServerAddress()
    Harness_Suite("SettingsStore.SetServerAddress validates and normalizes")
    settings = SettingsStore(invalid)

    Harness_Ok(settings.SetServerAddress("http://10.0.0.2:4141/"), "accepts http host + port")
    Harness_Equal(settings.GetServerAddress(), "http://10.0.0.2:4141", "strips a trailing slash")
    Harness_Ok(settings.SetServerAddress("https://addon.example.com"), "accepts https host")
    Harness_Ok(settings.SetServerAddress("http://host/base/path"), "accepts a path prefix")

    Harness_Ok(not settings.SetServerAddress(""), "rejects empty")
    Harness_Ok(not settings.SetServerAddress("host:4141"), "rejects a missing scheme")
    Harness_Ok(not settings.SetServerAddress("ftp://host"), "rejects a non-http(s) scheme")
    Harness_Ok(not settings.SetServerAddress("http://host:41xx"), "rejects a non-digit port")
    Harness_Equal(settings.GetServerAddress(), "http://host/base/path", "failed attempts leave the address unchanged")
end sub

sub Test_Settings_ClearServerAddress()
    Harness_Suite("SettingsStore.ClearServerAddress blanks and persists")
    registry = MockRegistry()
    settings = SettingsStore(registry)
    settings.SetServerAddress("http://10.0.0.2:4141")
    settings.ClearServerAddress()

    Harness_Equal(settings.GetServerAddress(), "", "address blanked")
    Harness_Equal(settings.ServerAddressSet(), false, "no longer set")

    reopened = SettingsStore(registry)
    Harness_Equal(reopened.GetServerAddress(), "", "blank persisted")
end sub

' The setters persist themselves, so no Save() call appears anywhere below. That
' is the point of the suite: the ECP import path set the server address and
' omitted the save, which no existing test could see, because the one test that
' checked persistence made the Save() call itself.
sub Test_Settings_SettersPersistWithoutAnExplicitSave()
    Harness_Suite("SettingsStore setters persist on their own")
    registry = MockRegistry()
    settings = SettingsStore(registry)

    Harness_Ok(settings.SetServerAddress("http://192.168.1.5:4141"), "address accepted")
    Harness_Ok(settings.SetLanguage("es"), "language accepted")
    Harness_Ok(settings.SetAudioMode("surround"), "surround audio preset accepted")

    reopened = SettingsStore(registry)
    Harness_Equal(reopened.GetServerAddress(), "http://192.168.1.5:4141", "address reloaded with no Save() call")
    Harness_Equal(reopened.GetLanguage(), "es", "language reloaded with no Save() call")
    Harness_Equal(reopened.GetAudioMode(), "surround", "audio preset reloaded without explicit Save")
    Harness_Ok(not reopened.SetAudioMode("invalid"), "unsupported audio preset rejected")
    Harness_Equal(reopened.GetAudioMode(), "surround", "invalid preset cannot overwrite saved choice")
    Harness_Ok(reopened.SetAudioMode("projector"), "projector preset accepted")
    Harness_Equal(SettingsStore(registry).GetAudioMode(), "projector", "switching back also persists")
    registry.Write("audioMode", "obsolete")
    Harness_Equal(SettingsStore(registry).GetAudioMode(), "projector", "unknown registry values safely fall back to projector")
end sub

' roRegistrySection.Write answers with a boolean, and the answer used to be
' discarded — so a refused write flushed nothing and reverted on the next
' launch with nothing recording that it had been refused.
sub Test_Settings_ReportsARefusedWrite()
    Harness_Suite("SettingsStore reports a write the registry refuses")
    registry = MockRegistry()
    registry.failWrites = true
    settings = SettingsStore(registry)

    Harness_Ok(settings.SetServerAddress("http://192.168.1.5:4141"), "the value is still set in memory")
    Harness_Ok(settings.SaveFailed(), "the refused write is reported")
    Harness_Equal(SettingsStore(registry).GetServerAddress(), "", "and nothing reached the registry")

    registry.failWrites = false
    Harness_Ok(settings.SetServerAddress("http://192.168.1.5:4141"), "a retry still sets the value")
    Harness_Ok(not settings.SaveFailed(), "and the failure clears itself once a write lands")
    Harness_Equal(SettingsStore(registry).GetServerAddress(), "http://192.168.1.5:4141", "the retry persisted")
end sub

' A missing registry is the in-memory-only mode, not a write that failed.
sub Test_Settings_NoRegistryIsNotAFailedWrite()
    Harness_Suite("SettingsStore without a registry does not report a failure")
    settings = SettingsStore(invalid)
    settings.SetServerAddress("http://192.168.1.5:4141")
    Harness_Ok(not settings.SaveFailed(), "nowhere to write is not the same as a refused write")
end sub

sub Test_Settings_PersistsViaRegistry()
    Harness_Suite("SettingsStore round-trips through the registry")
    registry = MockRegistry()
    settings = SettingsStore(registry)
    settings.SetServerAddress("http://192.168.1.5:4141")
    settings.SetLanguage("es")
    settings.Save()

    reopened = SettingsStore(registry)
    Harness_Equal(reopened.GetServerAddress(), "http://192.168.1.5:4141", "address reloaded")
    Harness_Equal(reopened.GetLanguage(), "es", "language reloaded")
end sub

sub Test_Settings_InMemoryOnlyWithoutRegistry()
    Harness_Suite("SettingsStore without a registry is in-memory only")
    settings = SettingsStore(invalid)
    settings.SetServerAddress("http://192.168.1.5:4141")
    settings.Save()

    Harness_Equal(SettingsStore(invalid).GetServerAddress(), "", "nothing persisted without a registry")
end sub
