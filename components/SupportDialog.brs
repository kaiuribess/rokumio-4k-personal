' Help for the personal 4K build, shown as a native dialog.
'
' A StandardDialog presented through the Scene's dialog field. Close or Back
' dismisses it and restores the active screen's focus.

sub init()
    m.top.width = 1380
    m.top.observeFieldScoped("buttonSelected", "onButtonSelected")
end sub

' Preserve the upstream Scene's Configure contract.
sub Configure(platform as string)
    ' Kept for the existing Scene dialog contract; no payment action here.
end sub

' Single Close button; Back/Home are handled by the system.
sub onButtonSelected()
    m.top.close = true
end sub
