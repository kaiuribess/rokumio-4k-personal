
' Account sync exposes only safe counts and fixed messages, never provider URLs.
function ReadAddonSyncStatus() as object
    if Type(m.addonSyncStatus) = "roAssociativeArray" then return m.addonSyncStatus
    return {state:"idle",text:"",complete:false}
end function
sub RefreshAddonStatus()
    if m.addonsScreen <> invalid then m.addonsScreen.callFunc("RefreshInstalledRows")
end sub
sub NotifyAddonChanges()
    if m.homeScreen <> invalid then m.homeScreen.callFunc("EnsureCurrentRows")
    if m.searchScreen <> invalid then m.searchScreen.callFunc("EnsureCurrentSources")
    if m.discoverScreen <> invalid then m.discoverScreen.callFunc("EnsureCurrentSources")
    if m.playerScreen <> invalid then m.playerScreen.callFunc("EnsureSubtitleProviders")
    RefreshAddonStatus()
end sub
function RetryAddonSync() as boolean
    if m.storeHost = invalid then return false
    if m.storeHost.callFunc("AuthGetSession") <> "stremio" then return false
    StartAddonSync()
    return true
end function
