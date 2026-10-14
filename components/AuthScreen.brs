' AuthScreen — the first-run and post-logout decision screen.
'
' Two PrefRow options: continue as a local guest, or log in with Stremio via
' link-code pairing. OK on a row publishes one pushRequest; MainScene routes it.
' Back is swallowed so a not-logged-in launch cannot slip past the gate into the
' guest home beneath.

sub init()
    m.list = m.top.FindNode("authList")

    t = Theme()
    m.top.FindNode("authTitle").color = t.accent
    m.top.FindNode("authSub").color = t.textSecondary
    m.top.FindNode("authHint").color = t.textSecondary
    m.list.focusBitmapBlendColor = t.accentFocus

    m.list.ObserveField("rowItemSelected", "onRowSelected")
    m.rows = []
end sub

function OnEnter(params as object) as void
    BuildRows()
    m.list.SetFocus(true)
end function

function OnExit() as void
end function

' Swallow Back: the only exits from this gate are the two rows or Home.
function OnBackPressed() as boolean
    return true
end function

sub BlurFocus()
end sub

sub BuildRows()
    m.rows = []
    m.rows.Push({
        action: "continueGuest"
        title: "Browse movies & shows"
        value: "Local profile"
    })
    m.rows.Push({
        action: "loginStremio"
        title: "Connect Stremio"
        value: "Sync your library"
    })

    content = CreateObject("roSGNode", "ContentNode")
    for each row in m.rows
        entry = content.CreateChild("ContentNode")
        item = entry.CreateChild("ContentNode")
        item.title = row.title
        item.description = row.value
    end for
    m.list.content = content
    m.list.jumpToRowItem = [0, 0]
end sub

sub onRowSelected()
    data = m.list.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[0]
    if index < 0 or index >= m.rows.Count() then return
    action = m.rows[index].action
    if action = "continueGuest"
        m.top.pushRequest = { action: "continueGuest" }
    else if action = "loginStremio"
        m.top.pushRequest = { action: "startLogin" }
    end if
end sub
