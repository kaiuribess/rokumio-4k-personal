sub Main(args as object)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)

    ' ECP "input" (POST /input?<query params>) marshals its arguments straight
    ' to the running app as an roInputEvent (see reference/ecp-integration.md).
    ' Unlike /launch it does NOT relaunch the channel, so a deep link can land
    ' on the live instance. The port is shared with the screen; the loop below
    ' type-dispatches the events. The reference is deliberately held for the
    ' whole Main lifetime.
    input = CreateObject("roInput")
    input.SetMessagePort(port)
    ' Transport events carry Roku voice playback commands. Text dictation is
    ' handled separately by SearchScreen's native voice keyboard.
    input.EnableTransportEvents()

    scene = screen.CreateScene("MainScene")
    scene.ObserveField("exitApp", port)
    screen.Show()
    scene.callFunc("Start")
    ' An ECP deep link (rokumio-<verb>, see reference/ecp-integration.md) rides
    ' the launch args. Handle it after Start so the stack is up and Home is the
    ' base; the flow reports through a dialog and never replaces Home.
    scene.callFunc("HandleDeepLink", args)

    ' The local setup page (source/util/SetupPage.brs): a phone on the same
    ' network opens the address the scene prints on the Add-ons screen and
    ' pastes a manifest URL, which is far less work than typing one on the
    ' remote. The listener shares the screen's message port, so the loop below
    ' dispatches roSocketEvent alongside ECP and the exit poll. Closed on every
    ' exit path below.
    setup = SetupServerStart(port, scene)
    if setup <> invalid then scene.callFunc("ShowSetupAddress", setup.address)

    scene.SignalBeacon("AppLaunchComplete")

    while true
        message = Wait(300, port)
        if message = invalid
            ' Poll fallback: field polling does not depend on port delivery, so
            ' the exit dialog always closes the channel even if the event path
            ' dies.
            if scene.exitApp = true
                SetupServerClose(setup)
                return
            end if
        else
            if Type(message) = "roInputEvent"
                info = message.GetInfo()
                if info <> invalid and info.type = "transport"
                    response = scene.callFunc("HandleVoiceTransport", info)
                    if response = invalid then response = { status: "unhandled" }
                    response.id = info.id
                    ' Respond immediately; Roku requires a response within
                    ' five seconds and supplies defaults for unhandled keys.
                    input.EventResponse(response)
                else
                    scene.callFunc("HandleDeepLink", info)
                end if
            else if Type(message) = "roSocketEvent"
                SetupServerPoll(setup, message)
            else if Type(message) = "roSGScreenEvent" and message.IsScreenClosed()
                SetupServerClose(setup)
                return
            else if Type(message) = "roSGNodeEvent" and message.GetField() = "exitApp" and scene.exitApp = true
                SetupServerClose(setup)
                return
            end if
        end if
    end while
end sub
