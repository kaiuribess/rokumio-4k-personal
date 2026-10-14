sub init()
    t = Theme()
    m.top.FindNode("aboutTitle").color = t.textPrimary
    m.top.FindNode("aboutVersion").color = t.accentFocus
    m.top.FindNode("aboutBody").color = t.textPrimary
    m.top.FindNode("aboutCredit").color = t.textSecondary
    m.top.FindNode("aboutHelp").color = t.textSecondary
end sub

function OnEnter(params as object) as void
    m.top.SetFocus(true)
end function

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function
