sub init()
    m.border=m.top.FindNode("quickBorder"):m.face=m.top.FindNode("quickFace")
    m.title=m.top.FindNode("quickTitle"):m.detail=m.top.FindNode("quickDetail")
    m.top.ObserveField("itemContent","onQuickContent")
    m.top.ObserveField("itemHasFocus","onQuickLook")
    m.top.ObserveField("rowHasFocus","onQuickLook")
    onQuickLook()
end sub
sub onQuickContent()
    if m.top.itemContent=invalid then return
    m.title.text=m.top.itemContent.title
    m.detail.text=m.top.itemContent.description
    onQuickLook()
end sub
sub onQuickLook()
    t=Theme()
    m.border.color=t.tileFace:m.face.color=t.tileFace
    if m.top.itemHasFocus then m.border.color=t.accentFocus:m.face.color=t.itemFace
    m.title.color=t.textPrimary:m.detail.color=t.textSecondary
end sub
