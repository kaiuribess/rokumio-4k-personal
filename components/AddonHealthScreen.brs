sub init()
    m.list = m.top.FindNode("healthList")
    m.status = m.top.FindNode("healthStatus")
    m.name = m.top.FindNode("healthName")
    m.detail = m.top.FindNode("healthDetail")
    m.limit = m.top.FindNode("healthLimit")
    m.list.ObserveField("rowItemFocused","onHealthFocus")
    m.limit.ObserveField("fire","onHealthTimeout")
    t = Theme()
    m.top.FindNode("healthTitle").color = t.textPrimary
    m.top.FindNode("healthSubtitle").color = t.textSecondary
    m.top.FindNode("healthHelp").color = t.textSecondary
    m.top.FindNode("healthPlate").color = t.tileFace
    m.name.color = t.accentFocus
    m.detail.color = t.textPrimary
    m.status.color = t.textSecondary
    m.task = invalid
    m.sequence = 0
    m.checkClock = invalid
    m.rows = []
end sub

function OnEnter(params as object) as void
    StartHealthCheck()
    m.list.callFunc("SetListFocus")
end function

sub StartHealthCheck()
    CancelHealthCheck()
    m.rows = []
    addons = []
    if m.stores <> invalid then addons = m.stores.addons.callFunc("AddonsGetAll")
    if Type(addons) <> "roArray" then addons = []
    for index = 0 to addons.Count() - 1
        m.rows.Push({name:AddonDiagnostics_Name(addons[index],index),state:"pending",label:"Waiting",detail:"Waiting to check this add-on's manifest. Back cancels."})
    end for
    RenderHealthRows()
    if addons.Count() = 0
        m.status.text = "No add-ons installed. Return to Add-ons to connect one."
        return
    end if
    m.status.text = "Checking manifests… 0/" + addons.Count().ToStr()
    m.sequence = m.sequence + 1
    m.checkClock = CreateObject("roTimespan")
    m.checkClock.Mark()
    m.task = AsyncTask_Launch(m.top,"AddonHealthTask","onHealthResult",{addons:addons},"addonHealth" + m.sequence.ToStr())
    m.limit.control = "start"
end sub

sub onHealthResult(event as object)
    if m.task = invalid then return
    task = event.GetRoSGNode()
    if task = invalid or task.id <> m.task.id then return
    packet = event.GetData()
    if Type(packet) <> "roAssociativeArray" or Type(packet.results) <> "roArray" then return
    if m.top.screenActive <> true then return
    failed = 0
    for each item in packet.results
        if Type(item) <> "roAssociativeArray" or item.index = invalid then continue for
        if item.index < 0 or item.index >= m.rows.Count() then continue for
        m.rows[item.index] = item
    end for
    for each row in m.rows
        if row.state = "failed" then failed = failed + 1
    end for
    RenderHealthRows()
    m.status.text = "Checked " + packet.results.Count().ToStr() + "/" + m.rows.Count().ToStr() + " · " + failed.ToStr() + " need attention"
    if packet.done = true
        m.task = invalid
        m.limit.control = "stop"
        AsyncTask_Reap(task,m.top,false)
        m.status.text = m.status.text + " · Manifest checks only"
    end if
end sub

sub RenderHealthRows()
    focus = m.list.rowItemFocused
    index = 0
    if Type(focus) = "roArray" and focus.Count() > 0 then index = focus[0]
    content = CreateObject("roSGNode","ContentNode")
    for each row in m.rows
        parent = content.CreateChild("ContentNode")
        item = parent.CreateChild("ContentNode")
        item.title = row.name
        item.description = row.label
    end for
    m.list.content = content
    if index < 0 or index >= m.rows.Count() then index = 0
    if m.rows.Count() > 0 then m.list.callFunc("FocusRow",index)
    ShowHealthDetail(index)
end sub

sub onHealthFocus()
    focus = m.list.rowItemFocused
    if Type(focus) <> "roArray" or focus.Count() = 0 then return
    ShowHealthDetail(focus[0])
end sub

sub ShowHealthDetail(index as integer)
    if index < 0 or index >= m.rows.Count()
        m.name.text = "No add-ons"
        m.detail.text = "Add a configured source in Add-ons."
        return
    end if
    m.name.text = m.rows[index].name
    m.detail.text = m.rows[index].label + Chr(10) + Chr(10) + m.rows[index].detail
end sub

sub onHealthTimeout()
    if m.task = invalid then return
    ' A queued fire from a previous run cannot cancel a newly started check.
    if m.checkClock <> invalid and m.checkClock.TotalMilliseconds() < 120000 then return
    CancelHealthCheck()
    for each row in m.rows
        if row.state = "pending"
            row.state = "incomplete"
            row.label = "Not finished"
            row.detail = "The overall check deadline ended before this add-on was checked. Press Play/Pause to retry. This is not proof that it is broken."
        end if
    end for
    RenderHealthRows()
    m.status.text = "Check deadline reached · Play/Pause retries; Back returns"
end sub

sub CancelHealthCheck()
    if m.limit <> invalid then m.limit.control = "stop"
    m.checkClock = invalid
    if m.task <> invalid
        task = m.task
        m.task = invalid
        task.cancelRequested = true
        AsyncTask_Reap(task,m.top,true)
    end if
end sub

function OnExit() as void
    CancelHealthCheck()
end function

function OnBackPressed() as boolean
    CancelHealthCheck()
    return false
end function

function OnKeyEvent(key as string, press as boolean) as boolean
    if press and key = "play"
        StartHealthCheck()
        return true
    end if
    return false
end function
