' ScreenStack unit tests.
'
' ScreenStack talks to the scene only through FindNode, node.visible,
' node.screenActive, node.callFunc and node.SetFocus, so the harness fakes the
' scene with the same tiny surface. Every assertion printed by the harness is a
' lock on a stack behavior: push shows + enters, pop hides + blurs + exits +
' refocuses, back delegates, popTo walks the stack, the bottom screen is never
' popped away, and screenActive tracks the interactive top.

function MockNode(id as string, log as object, parent = invalid as dynamic) as object
    node = {
        id: id
        visible: false
        parent: parent
        onBackResult: false
        _log: log
    }

    node.callFunc = function(cmd as string, params = invalid as dynamic) as dynamic
        m._log.Push({ screen: m.id, call: cmd, withParams: params })
        if cmd = "OnBackPressed" then return m.onBackResult
        return invalid
    end function

    node.SetFocus = function(state as boolean)
        m._log.Push({ screen: m.id, call: "SetFocus", value: state })
        return invalid
    end function

    node.getParent = function() as dynamic
        return m.parent
    end function

    return node
end function

' A fake parent for the node-destruction path: ScreenStack reads getParent() and
' calls RemoveChild on whatever the node reports, so the parent just logs it.
function MockParent(log as object) as object
    parent = { _log: log }
    parent.RemoveChild = function(node as object)
        m._log.Push({ screen: node.id, call: "RemoveChild" })
    end function
    return parent
end function

function MockScene(screens as object, log as object) as object
    scene = {
        screens: screens
        _log: log
    }

    scene.FindNode = function(id as string) as object
        return m.screens[id]
    end function

    return scene
end function

function Test_FindCall(log as object, screen as string, callName as string) as object
    for each entry in log
        if entry.screen = screen and entry.call = callName then return entry
    end for
    return invalid
end function

sub Test_Stack_Introspection()
    Harness_Suite("ScreenStack count / top / has")
    log = []
    scene = MockScene({ home: MockNode("home", log), detail: MockNode("detail", log) }, log)
    stack = ScreenStack(scene)

    Harness_Equal(stack.count(), 0, "count is 0 when empty")
    Harness_Ok(stack.top() = invalid, "top is invalid when empty")

    stack.push("home", invalid)
    Harness_Equal(stack.count(), 1, "count is 1 after push")
    Harness_Equal(stack.top().id, "home", "top().id is home")
    Harness_Ok(stack.has("home"), "has(home) is true")
    Harness_Ok(not stack.has("detail"), "has(detail) is false before it is pushed")
end sub

sub Test_Push_ShowsAndEnters()
    Harness_Suite("ScreenStack.push shows target, enters with params, blurs outgoing")
    log = []
    screens = { home: MockNode("home", log), detail: MockNode("detail", log) }
    scene = MockScene(screens, log)
    stack = ScreenStack(scene)

    stack.push("home", invalid)
    Harness_Ok(screens.home.visible, "home visible after first push")
    Harness_Equal(stack.count(), 1, "count is 1")

    stack.push("detail", { pick: 3 })
    Harness_Ok(screens.detail.visible, "detail visible after push")
    Harness_Ok(not screens.home.visible, "outgoing home hidden after push")
    Harness_Equal(stack.count(), 2, "count is 2")

    call = Test_FindCall(log, "detail", "OnEnter")
    Harness_Ok(call <> invalid, "detail received OnEnter")
    if call <> invalid
        Harness_Equal(call.withParams.pick, 3, "OnEnter received params")
    end if

    Harness_Ok(Test_FindCall(log, "home", "BlurFocus") <> invalid, "outgoing home blurred on push")

    Harness_Ok(not screens.home.screenActive, "outgoing home no longer active after push")
    Harness_Ok(screens.detail.screenActive, "pushed detail is the active top")

    call = Test_FindCall(log, "detail", "SetFocus")
    Harness_Ok(call <> invalid and call.value = true, "pushed detail focused")
end sub

sub Test_Modal_Push_KeepsPreviousVisible()
    Harness_Suite("ScreenStack.modal push keeps the previous screen visible but blurred")
    log = []
    screens = { home: MockNode("home", log), dialog: MockNode("dialog", log) }
    scene = MockScene(screens, log)
    stack = ScreenStack(scene)

    stack.push("home", invalid)
    stack.push("dialog", invalid, true)

    Harness_Ok(screens.dialog.visible, "modal dialog visible")
    Harness_Ok(screens.home.visible, "home stays visible behind modal")
    Harness_Ok(Test_FindCall(log, "home", "BlurFocus") <> invalid, "home still blurred behind modal")
    Harness_Ok(not screens.home.screenActive, "home inactive behind modal")
    Harness_Ok(screens.dialog.screenActive, "modal dialog is the active top")
    call = Test_FindCall(log, "dialog", "SetFocus")
    Harness_Ok(call <> invalid and call.value = true, "modal dialog focused")

    Harness_Ok(stack.pop(), "pop returns true")
    Harness_Ok(screens.dialog.visible = false, "dialog hidden after pop")
    Harness_Ok(screens.home.visible, "home still visible after pop")
    Harness_Ok(screens.home.screenActive, "home active again after modal pop")
    call = Test_FindCall(log, "home", "SetFocus")
    Harness_Ok(call <> invalid and call.value = true, "home refocused after pop")
end sub

sub Test_Push_UnknownScreen()
    Harness_Suite("ScreenStack.push unknown screen is a no-op")
    log = []
    scene = MockScene({}, log)
    stack = ScreenStack(scene)
    stack.push("ghost", invalid)
    Harness_Equal(stack.count(), 0, "nothing pushed on empty stack")
end sub

sub Test_Push_UnknownScreenLeavesCurrentAlone()
    Harness_Suite("ScreenStack.push unknown screen leaves the current screen untouched")
    log = []
    screens = { home: MockNode("home", log) }
    scene = MockScene(screens, log)
    stack = ScreenStack(scene)

    stack.push("home", invalid)
    stack.push("ghost", { pick: 3 })

    Harness_Equal(stack.count(), 1, "unknown push leaves the stack untouched")
    Harness_Ok(screens.home.visible, "current screen stays visible")
    Harness_Ok(Test_FindCall(log, "home", "BlurFocus") = invalid, "current screen not blurred")
    Harness_Ok(Test_FindCall(log, "ghost", "OnEnter") = invalid, "ghost never entered")
end sub

sub Test_Pop_RefusesOnSingle()
    Harness_Suite("ScreenStack.pop refuses below the bottom screen")
    log = []
    screens = { home: MockNode("home", log) }
    scene = MockScene(screens, log)
    stack = ScreenStack(scene)

    stack.push("home", invalid)
    ret = stack.pop()
    Harness_Ok(ret = false, "pop returns false when count <= 1")
    Harness_Equal(stack.count(), 1, "stack unchanged")
    Harness_Ok(screens.home.visible, "home still visible")
end sub

sub Test_Pop_RestoresPrevious()
    Harness_Suite("ScreenStack.pop pops, hides, blurs, exits, refocuses previous")
    log = []
    screens = { home: MockNode("home", log), detail: MockNode("detail", log) }
    scene = MockScene(screens, log)
    stack = ScreenStack(scene)

    stack.push("home", invalid)
    stack.push("detail", invalid)

    ret = stack.pop()
    Harness_Ok(ret = true, "pop returns true")
    Harness_Equal(stack.count(), 1, "count back to 1")
    Harness_Ok(screens.home.visible, "home visible again")
    Harness_Ok(screens.detail.visible = false, "popped detail hidden")
    Harness_Ok(not screens.detail.screenActive, "popped detail no longer active")
    Harness_Ok(screens.home.screenActive, "restored home is active again")

    Harness_Ok(Test_FindCall(log, "detail", "BlurFocus") <> invalid, "popped detail blurred")
    Harness_Ok(Test_FindCall(log, "detail", "OnExit") <> invalid, "popped detail exited")

    entered = Test_FindCall(log, "home", "OnEnter")
    Harness_Ok(entered <> invalid and entered.withParams = invalid, "home re-entered with no params")

    call = Test_FindCall(log, "home", "SetFocus")
    Harness_Ok(call <> invalid and call.value = true, "home refocused")
end sub

sub Test_PushNode_LikePush()
    Harness_Suite("ScreenStack.pushNode pushes a caller-built node like push")
    log = []
    home = MockNode("home", log)
    player = MockNode("player", log, MockParent(log))
    scene = MockScene({ home: home }, log)
    stack = ScreenStack(scene)

    stack.push("home", invalid)
    stack.pushNode(player, { url: "http://example/lib.m3u8" })

    Harness_Equal(stack.count(), 2, "count is 2 after pushNode")
    Harness_Ok(player.visible, "player visible after pushNode")
    Harness_Ok(not home.visible, "outgoing home hidden after pushNode")
    Harness_Ok(not home.screenActive, "outgoing home inactive after pushNode")
    Harness_Ok(player.screenActive, "player node is the active top")

    call = Test_FindCall(log, "player", "OnEnter")
    Harness_Ok(call <> invalid and call.withParams.url = "http://example/lib.m3u8", "pushNode OnEnter received params")
end sub

sub Test_PushNode_DestroysOnPop()
    Harness_Suite("ScreenStack.pop removes a pushNode'd screen from the tree")
    log = []
    home = MockNode("home", log)
    parent = MockParent(log)
    player = MockNode("player", log, parent)
    scene = MockScene({ home: home }, log)
    stack = ScreenStack(scene)

    stack.push("home", invalid)
    stack.pushNode(player, invalid)

    ret = stack.pop()
    Harness_Ok(ret = true, "pop returns true")
    Harness_Equal(stack.count(), 1, "count back to 1")
    Harness_Ok(Test_FindCall(log, "player", "OnExit") <> invalid, "player exited before teardown")
    Harness_Ok(Test_FindCall(log, "player", "RemoveChild") <> invalid, "player removed from its parent on pop")
end sub

sub Test_Static_Push_NotDestroyedOnPop()
    Harness_Suite("ScreenStack.pop never removes a statically-resolved screen")
    log = []
    detail = MockNode("detail", log, MockParent(log))
    scene = MockScene({ home: MockNode("home", log), detail: detail }, log)
    stack = ScreenStack(scene)

    stack.push("home", invalid)
    stack.push("detail", invalid)
    stack.pop()

    Harness_Ok(Test_FindCall(log, "detail", "RemoveChild") = invalid, "static screen stays in the tree")
end sub

sub Test_Back_Delegates()
    Harness_Suite("ScreenStack.onBackPressed delegates to the top screen")
    log = []
    home = MockNode("home", log)
    scene = MockScene({ home: home }, log)
    stack = ScreenStack(scene)
    stack.push("home", invalid)

    home.onBackResult = false
    Harness_Ok(stack.onBackPressed() = false, "false when top declines")
    home.onBackResult = true
    Harness_Ok(stack.onBackPressed() = true, "true when top swallows")
    Harness_Ok(Test_FindCall(log, "home", "OnBackPressed") <> invalid, "top's OnBackPressed called")
end sub

sub Test_Back_EmptyStack()
    Harness_Suite("ScreenStack.onBackPressed on empty stack")
    log = []
    scene = MockScene({}, log)
    stack = ScreenStack(scene)
    Harness_Ok(stack.onBackPressed() = false, "false on empty stack")
end sub

sub Test_PopTo()
    Harness_Suite("ScreenStack.popTo walks down to a named screen")
    log = []
    screens = {
        home: MockNode("home", log)
        detail: MockNode("detail", log)
        player: MockNode("player", log)
    }
    scene = MockScene(screens, log)
    stack = ScreenStack(scene)

    stack.push("home", invalid)
    stack.push("detail", invalid)
    stack.push("player", invalid)

    Harness_Ok(stack.popTo("home"), "popTo(home) succeeds")
    Harness_Equal(stack.count(), 1, "only home remains")
    Harness_Ok(screens.player.visible = false, "player hidden after popTo")
    Harness_Ok(screens.detail.visible = false, "detail hidden after popTo")
    Harness_Ok(screens.home.visible, "home visible after popTo")

    Harness_Ok(stack.popTo("missing") = false, "popTo unknown returns false")
end sub