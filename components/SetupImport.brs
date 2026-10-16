
' Browser imports need an explicit, short-lived confirmation on this TV.
' The configured URL stays private; the dialog displays no provider token.
function RequestSetupImport(url as dynamic) as boolean
    if m.stack = invalid or m.import <> invalid or m.pendingSetupImport <> invalid then return false
    active = m.stack.top()
    if active = invalid or active.id <> "addonsScreen" then return false
    if m.top.dialog <> invalid then return false
    if GetInterface(url,"ifString") = invalid or url = "" or Len(url) > 8192 then return false
    clock = CreateObject("roTimespan"):clock.Mark()
    m.pendingSetupImport = {url:url,clock:clock,accountGeneration:AccountGeneration()}
    dialog = CreateObject("roSGNode","StandardMessageDialog")
    dialog.id = "setupImportConfirm"
    dialog.title = "Allow browser add-on import?"
    dialog.message = ["A device on your Wi-Fi sent an add-on link. Allow only if you just submitted it. This request expires after 60 seconds."]
    dialog.buttons = ["Cancel","Allow import"]
    dialog.ObserveField("buttonSelected","onSetupImportChoice")
    dialog.ObserveField("wasClosed","onSetupImportClosed")
    m.top.dialog = dialog
    return true
end function
sub onSetupImportChoice()
    dialog = m.top.dialog
    if dialog = invalid or dialog.id <> "setupImportConfirm" then return
    request = m.pendingSetupImport
    m.pendingSetupImport = invalid
    allowed = dialog.buttonSelected = 1
    dialog.close = true
    if not allowed or Type(request) <> "roAssociativeArray" then return
    if request.accountGeneration <> AccountGeneration() or request.clock.TotalMilliseconds() >= 60000 then return
    ImportFromSetup(request.url)
end sub
sub onSetupImportClosed()
    m.pendingSetupImport = invalid
    if m.top.dialog <> invalid and m.top.dialog.id = "setupImportConfirm" then m.top.dialog = invalid
    RestoreActiveScreenFocus()
end sub

sub ExpireSetupImport()
    request = m.pendingSetupImport
    if Type(request) <> "roAssociativeArray" then return
    expired = request.clock.TotalMilliseconds() >= 60000 or request.accountGeneration <> AccountGeneration()
    active = m.stack.top()
    if active = invalid or active.id <> "addonsScreen" then expired = true
    if not expired then return
    m.pendingSetupImport = invalid
    if m.top.dialog <> invalid and m.top.dialog.id = "setupImportConfirm" then m.top.dialog.close = true
end sub
