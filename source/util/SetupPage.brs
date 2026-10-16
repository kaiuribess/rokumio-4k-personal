' Local setup page — the channel serves a one-field web form on the LAN so a
' phone can paste an add-on manifest URL instead of the user typing it on the
' remote with the on-screen keyboard.
'
' Everything here runs on the MAIN thread. The listener is registered on the
' same roMessagePort as the screen and source/main.brs dispatches
' roSocketEvent into SetupServerPoll inside its existing Wait loop, so the
' socket lifecycle must never block: reads are driven by notifyReadable, a
' partial write is parked on notifyWritable, and a finished response always
' closes the connection (Connection: close, no keep-alive bookkeeping).
'
' Two halves, deliberately split:
'
'   * pure helpers — SetupRequestState, SetupHeaderValue, SetupFormValue,
'     SetupValidateManifestUrl, SetupLanAddress, the HTML builders and
'     SetupHttpResponse. No sockets, no device objects, so
'     tests/setuppage.test.brs can drive all of it in the brs interpreter;
'   * SetupServerStart / SetupServerPoll / SetupServerClose — thin wrappers
'     around roStreamSocket that the tests never reach, kept to the shape of
'     the echo server in the roStreamSocket reference so the API surface is
'     the documented one.
'
' String indexing is the method form throughout (s.Mid(i, n), s.InStr(x),
' s.Left(n)), which is ZERO-based — the global Mid(s, i, n) is one-based and a
' single convention would silently split this file in two. Everything here is
' ASCII-only by design (the byte count in Content-Length stops matching Len()
' the moment a character outside ASCII shows up).
'
' The listener binds only the selected private IPv4 interface. Host/Origin
' checks reject browser cross-site submissions and DNS rebinding, and the
' Scene accepts imports only while the Add-ons screen is open.

' The one port the page binds. Named rather than inlined because the address
' printed on the TV and the address the listener binds are the same fact, and
' a typo in one of two literals would show an address that refuses to load.
function SetupServerPort() as integer
    return 8744
end function

function SetupListenBacklog() as integer
    return 4
end function

function SetupMaxConnections() as integer
    return 8
end function

function SetupReadChunk() as integer
    return 4096
end function

function SetupMaxRequestBytes() as integer
    return 65536
end function

' Both idle and absolute deadlines are monotonic. Drip-fed requests cannot
' occupy a slot forever just by sending one byte before the idle limit.
function SetupConnectionExpired(conn as dynamic, now as integer) as boolean
    if Type(conn) <> "roAssociativeArray" then return true
    if conn.startedAt = invalid or conn.lastActivity = invalid then return true
    return now - conn.lastActivity >= 10000 or now - conn.startedAt >= 30000
end function

sub SetupServerSweep(setup as dynamic)
    if setup = invalid or setup.clock = invalid then return
    expired = []
    now = setup.clock.TotalMilliseconds()
    for each key in setup.connections
        if SetupConnectionExpired(setup.connections[key],now) then expired.Push(key)
    end for
    for each key in expired
        SetupServerDrop(setup,key,setup.connections[key])
    end for
end sub

function CrLf() as string
    return Chr(13) + Chr(10)
end function

' Classify a buffered HTTP request.
'
'   "incomplete"  the headers, or a declared body, have not fully arrived
'   "ready"       the whole request is buffered and can be handled
'   "400"         the request line is unparseable (a method this page does not
'                 know, or a malformed line), or the declared body is larger
'                 than this page will ever accept
'   "405"         a method this page knows but does not serve (PUT, DELETE, ...)
'   "411"         a POST with no Content-Length, so its body cannot be framed
'
' Framing is by Content-Length alone. The only POST this page receives is a
' browser submitting an application/x-www-form-urlencoded form, which never
' uses chunked encoding; a chunked body would need a decoder that nothing here
' has, so it is answered with 411 rather than silently mis-framed.
'
' This runs on every socket event with whatever has arrived so far, so partial
' headers, a request line split across two reads and a body still in flight
' are all just "incomplete" — never a guess.
function SetupRequestState(raw as string) as string
    headEnd = raw.InStr(CrLf() + CrLf())
    if headEnd < 0 then return "incomplete"

    headerBlock = raw.Left(headEnd)
    lineEnd = headerBlock.InStr(CrLf())
    if lineEnd < 0
        ' A request with no other headers has nothing between the request line
        ' and the terminator — headerBlock IS the request line.
        requestLine = headerBlock
    else
        requestLine = headerBlock.Left(lineEnd)
    end if

    parts = requestLine.Split(" ")
    if parts.Count() < 2 then return "400"
    method = parts[0]
    if method = "GET" then return "ready"
    if method = "POST"
        length = SetupContentLength(headerBlock)
        if length < 0 then return "411"
        if length > SetupMaxRequestBytes() then return "400"
        if raw.Len() - (headEnd + 4) < length then return "incomplete"
        return "ready"
    end if
    if SetupIsServedElsewhere(method) then return "405"
    return "400"
end function

' Known HTTP methods this page deliberately does not serve. Anything else on
' the request line is not a method at all — a mis-typed line — which is a 400,
' not a 405.
function SetupIsServedElsewhere(method as string) as boolean
    return method = "PUT" or method = "DELETE" or method = "PATCH" or method = "HEAD" or method = "OPTIONS" or method = "TRACE"
end function

' The method token of a partial or whole request: everything up to the first
' space of the first line. Early reads arrive without the trailing CRLF and
' still carry a readable method, which keeps the socket path from branching on
' how the request happened to be sliced.
function SetupRequestMethod(raw as string) as string
    line = raw
    lineEnd = raw.InStr(CrLf())
    if lineEnd >= 0 then line = raw.Left(lineEnd)
    space = line.InStr(" ")
    if space < 0 then return ""
    return line.Left(space)
end function

function SetupRequestPath(raw as string) as string
    lineEnd = raw.InStr(CrLf())
    if lineEnd < 0 then return ""
    parts = raw.Left(lineEnd).Split(" ")
    if parts.Count() < 2 then return ""
    return parts[1].Split("?")[0]
end function

function SetupBody(raw as string) as string
    headEnd = raw.InStr(CrLf() + CrLf())
    if headEnd < 0 then return ""
    return raw.Mid(headEnd + 4)
end function

' Case-insensitive header lookup over a header block. The first line of the
' block is the request line, so the scan starts at index 1 — a request line
' can itself contain a colon (a path with a port, a query), and that must not
' read back as a header.
function SetupHeaderValue(headers as string, name as string) as string
    wanted = LCase(name.Trim())
    lines = headers.Split(CrLf())
    for i = 1 to lines.Count() - 1
        line = lines[i]
        colon = line.InStr(":")
        if colon > 0
            if LCase(line.Left(colon).Trim()) = wanted
                return line.Mid(colon + 1).Trim()
            end if
        end if
    end for
    return ""
end function

' -1 when the header is absent or holds anything but digits. A malformed
' Content-Length is not a short body — treating it as one would leave the
' connection waiting for bytes the sender believes it already sent.
function SetupContentLength(headers as string) as integer
    raw = SetupHeaderValue(headers, "content-length")
    if raw = "" then return -1
    value = 0
    for i = 0 to raw.Len() - 1
        ch = raw.Mid(i, 1)
        if ch < "0" or ch > "9" then return -1
        value = value * 10 + (Asc(ch) - 48)
    end for
    return value
end function

function SetupFormValue(body as string, key as string) as string
    if body = "" then return ""
    pairs = body.Split("&")
    for each pair in pairs
        equals = pair.InStr("=")
        if equals >= 0
            if pair.Left(equals) = key then return SetupFormDecode(pair.Mid(equals + 1))
        end if
    end for
    return ""
end function

' application/x-www-form-urlencoded: a plus is a space, everything else is a
' %XX escape. Unescape is RFC 3986 and leaves "+" alone, so the spaces have to
' be written before the escapes are read.
function SetupFormDecode(value as string) as string
    if value = "" then return ""
    spaces = SetupReplaceChar(value, "+", " ")

    ' Platform first: roString.Unescape knows UTF-8, which a byte walk does
    ' not. It answers "" for an invalid escape sequence (a literal % that never
    ' arrived encoded), and the interpreter raises on one, so both outcomes —
    ' a false empty and a caught error — fall through to the ASCII decoder
    ' below rather than reporting the field as blank.
    decoded = ""
    fromPlatform = false
    try
        decoded = spaces.Unescape()
        fromPlatform = true
    catch e
    end try
    if fromPlatform and decoded <> "" then return decoded

    if spaces.InStr("%") < 0 then return spaces
    return SetupPercentDecodeAscii(spaces)
end function

' ASCII half of SetupFormDecode: %XX for the range the manifest URL the page
' actually receives lives in. An escape this cannot render as a single ASCII
' byte — a UTF-8 lead byte, or a malformed pair — is kept verbatim instead of
' being guessed at, so what reaches AddonsStore is the pasted text rather than
' a mangled version of it. Non-ASCII URLs are percent-encoded by the browser
' and are rejected downstream as an address the store does not recognise.
function SetupPercentDecodeAscii(value as string) as string
    result = ""
    i = 0
    length = value.Len()
    while i < length
        ch = value.Mid(i, 1)
        if ch = "%"
            byte = SetupHexByte(value.Mid(i + 1, 2))
            if byte >= 0 and byte < 128
                result = result + Chr(byte)
                i = i + 3
            else
                result = result + ch
                i = i + 1
            end if
        else
            result = result + ch
            i = i + 1
        end if
    end while
    return result
end function

' -1 when the two characters are not a hex pair.
function SetupHexByte(hex as string) as integer
    if hex.Len() <> 2 then return -1
    value = 0
    for i = 0 to 1
        ch = UCase(hex.Mid(i, 1))
        digit = -1
        if ch >= "0" and ch <= "9" then digit = Asc(ch) - 48
        if ch >= "A" and ch <= "F" then digit = Asc(ch) - 55
        if digit < 0 then return -1
        value = value * 16 + digit
    end for
    return value
end function

' Replace every occurrence of one character with another. A hand walk rather
' than a string method: the page has to build the same text on every Roku the
' channel runs on, and this keeps that to functions the platform documents.
function SetupReplaceChar(value as string, target as string, replacement as string) as string
    if target = "" then return value
    result = ""
    i = 0
    length = value.Len()
    width = target.Len()
    while i < length
        if value.Mid(i, width) = target
            result = result + replacement
            i = i + width
        else
            result = result + value.Mid(i, 1)
            i = i + 1
        end if
    end while
    return result
end function

' Fast reject on the phone: a paste that is not even a manifest URL gets an
' answer here instead of a success message the TV then contradicts.
'
' The rules mirror AddonsStore.SanitizeUrl exactly — Install() refuses anything
' it does not return, so a URL the page blesses and the store refuses would
' install nothing and shame the page's "installs on the TV" copy. The only
' additions are pasted-text hygiene (a literal space means the paste picked up
' extra words) and the /manifest.json segment the store's BaseFromManifestUrl
' needs. tests/setuppage.test.brs runs both halves over the same corpus so this
' cannot drift into accepting what the store refuses.
function SetupValidateManifestUrl(url as dynamic) as string
    if url = invalid then return ""
    if Type(url) <> "roString" and Type(url) <> "String" then return ""
    ' Registry-less validation shares the installer's exact rules, including
    ' port URLs and configured paths; this never performs a network request.
    store = AddonsStore(invalid)
    return store.SanitizeUrl(url)
end function

' First address a phone on the same network can actually reach. GetIPAddrs is
' keyed by interface and includes whatever else the device holds — loopback,
' IPv6 link-local — and the page is useless on all of those.
function SetupLanAddress(addrs as dynamic) as string
    if addrs = invalid then return ""
    if Type(addrs) <> "roAssociativeArray" then return ""
    for each name in addrs
        if SetupIsLanIp(addrs[name]) then return addrs[name]
    end for
    return ""
end function

function SetupIsLanIp(ip as dynamic) as boolean
    if ip = invalid then return false
    if Type(ip) <> "roString" and Type(ip) <> "String" then return false
    parts = ip.Split(".")
    if parts.Count() <> 4 then return false
    values = []
    for each part in parts
        if part = "" or part.Len() > 3 then return false
        for i = 0 to part.Len() - 1
            ch = part.Mid(i, 1)
            if ch < "0" or ch > "9" then return false
        end for
        value = Val(part)
        if value > 255 then return false
        values.Push(value)
    end for
    return values[0] = 10 or (values[0] = 172 and values[1] >= 16 and values[1] <= 31) or (values[0] = 192 and values[1] = 168)
end function

' Browsers send Origin on form POSTs. Require it to match when present;
' requests without Origin remain usable by a direct local setup client. A
' foreign Host cannot read the form through a rebinding domain either.
function SetupSameOrigin(raw as string, address as string) as boolean
    if address.Left(7) <> "http://" then return false
    headEnd = raw.InStr(CrLf() + CrLf())
    if headEnd < 0 then return false
    headers = raw.Left(headEnd)
    if LCase(SetupHeaderValue(headers, "Host")) <> LCase(address.Mid(7)) then return false
    origin = SetupHeaderValue(headers, "Origin")
    if origin <> "" and LCase(origin) <> LCase(address) then return false
    if LCase(SetupHeaderValue(headers, "Sec-Fetch-Site")) = "cross-site" then return false
    return true
end function

' Plain http on purpose: this is a form on a private address, and a
' self-signed certificate on a phone is a worse experience than no TLS at all.
function SetupAddressText(ip as dynamic) as string
    if ip = invalid then return ""
    if ip = "" then return ""
    return "http://" + ip + ":" + SetupServerPort().ToStr()
end function

' The document shell. Single-quoted HTML attributes throughout: BrightScript
' has only double-quoted strings, so every attribute value would otherwise
' need Chr(34) concatenated into the markup.
function SetupHtml(title as string, inner as string) as string
    html = "<!DOCTYPE html><html><head><meta charset='utf-8'>"
    html = html + "<meta name='viewport' content='width=device-width, initial-scale=1'>"
    html = html + "<title>Crimson Cinema setup</title><style>"
    html = html + "body{margin:0;background:#0d0e12;color:#f5f2f4;"
    html = html + "font:16px/1.5 -apple-system,Segoe UI,sans-serif;display:flex;"
    html = html + "min-height:100vh;align-items:center;justify-content:center}"
    html = html + "main{width:100%;max-width:34rem;padding:1.5rem}"
    html = html + "h1{color:#e6384f;font-size:1.5rem;margin:0 0 .75rem}"
    html = html + "p{color:#adb0bc;margin:0 0 1.25rem}"
    html = html + "input{width:100%;box-sizing:border-box;padding:.9rem;font-size:1rem;"
    html = html + "border:1px solid #2f4038;border-radius:.5rem;background:#101712;"
    html = html + "color:#f5f2f4}"
    html = html + "button{margin-top:1rem;padding:.9rem 1.5rem;font-size:1rem;border:0;"
    html = html + "border-radius:.5rem;background:#e6384f;color:#0d0e12;font-weight:600}"
    html = html + "a{color:#e6384f}"
    html = html + "</style></head><body><main>"
    html = html + "<h1>" + title + "</h1>"
    html = html + inner
    html = html + "</main></body></html>"
    return html
end function

function SetupHtmlPage() as string
    inner = "<p>Keep the Add-ons screen open on your Roku, then paste the configured HTTPS manifest URL here.</p>"
    inner = inner + "<form method='POST' action='/'>"
    inner = inner + "<input name='manifest' type='url' required autofocus "
    inner = inner + "placeholder='https://example.com/manifest.json'>"
    inner = inner + "<button type='submit'>Install</button>"
    inner = inner + "</form>"
    return SetupHtml("Add an add-on", inner)
end function

function SetupHtmlSent() as string
    inner = "<p>Sent to the Roku. Confirm Allow import on the TV within 60 seconds, then watch the installation summary.</p>"
    inner = inner + "<p><a href='/'>Install another</a></p>"
    return SetupHtml("Sent", inner)
end function

function SetupHtmlBusy() as string
    inner = "<p>Keep the Add-ons screen open on the Roku. If an import is already running, wait for its summary on the TV, then submit again.</p>"
    inner = inner + "<p><a href='/'>Back</a></p>"
    return SetupHtml("The TV is busy", inner)
end function

function SetupHtmlStatus(code as string) as string
    if code = "403"
        return SetupHtml("Local setup only", "<p>Open the exact local address shown on the Roku Add-ons screen.</p>")
    end if
    if code = "405"
        return SetupHtml("Method not allowed", "<p>This page answers GET and POST only.</p><p><a href='/'>Back</a></p>")
    end if
    if code = "411"
        return SetupHtml("Length required", "<p>The request arrived without a body to read.</p><p><a href='/'>Back</a></p>")
    end if
    return SetupHtml("Bad request", "<p>The request could not be read.</p><p><a href='/'>Back</a></p>")
end function

function SetupStatusText(code as string) as string
    if code = "403" then return "403 Forbidden"
    if code = "400" then return "400 Bad Request"
    if code = "405" then return "405 Method Not Allowed"
    if code = "409" then return "409 Conflict"
    if code = "411" then return "411 Length Required"
    return "200 OK"
end function

' The whole response, headers included. Content-Length is the body's byte
' count, which is why every page above is built from ASCII only — a count of
' characters and a count of bytes stop agreeing the moment anything outside
' ASCII gets in.
function SetupHttpResponse(status as string, body as string) as string
    response = "HTTP/1.1 " + status + CrLf()
    response = response + "Content-Type: text/html; charset=utf-8" + CrLf()
    response = response + "Content-Length: " + Len(body).ToStr() + CrLf()
    response = response + "Connection: close" + CrLf()
    response = response + "Cache-Control: no-store" + CrLf()
    response = response + "X-Content-Type-Options: nosniff" + CrLf()
    response = response + "Referrer-Policy: no-referrer" + CrLf()
    response = response + "Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'" + CrLf()
    response = response + CrLf()
    return response + body
end function

' First LAN address the device reports, or "" when it has none worth showing.
' The listener is only started when there is an address to print: an empty one
' means nothing a phone could dial, so a bound socket would be pure noise.
function SetupServerStart(port as dynamic, scene as dynamic) as dynamic
    device = CreateObject("roDeviceInfo")
    ip = SetupLanAddress(device.GetIPAddrs())
    address = SetupAddressText(ip)
    if address = "" then return invalid

    listener = CreateObject("roStreamSocket")
    listener.SetMessagePort(port)
    bindTo = CreateObject("roSocketAddress")
    if not bindTo.SetAddress(ip + ":" + SetupServerPort().ToStr())
        listener.Close()
        return invalid
    end if
    if not listener.SetAddress(bindTo)
        listener.Close()
        return invalid
    end if
    listener.NotifyReadable(true)
    listener.Listen(SetupListenBacklog())
    if not listener.EOK()
        listener.Close()
        return invalid
    end if

    clock = CreateObject("roTimespan")
    clock.Mark()
    return {
        listen: listener
        port: port
        scene: scene
        address: address
        connections: {}
        clock: clock
    }
end function

sub SetupServerPoll(setup as dynamic, event as dynamic)
    if setup = invalid then return
    if setup.listen = invalid then return

    changed = event.GetSocketID()
    if changed = setup.listen.GetID()
        SetupServerAccept(setup)
        return
    end if

    key = StrI(changed)
    if not setup.connections.DoesExist(key) then return
    conn = setup.connections[key]
    if conn = invalid then return
    if not conn.socket.EOK()
        SetupServerDrop(setup, key, conn)
        return
    end if

    ' A parked response outranks an inbound read: the client is waiting on it,
    ' and there is nothing further to read once it has been answered.
    if conn.outbox <> ""
        SetupServerFlush(setup, key, conn)
        return
    end if
    SetupServerRead(setup, key, conn)
end sub

sub SetupServerAccept(setup as dynamic)
    if not setup.listen.IsReadable() then return

    sock = setup.listen.Accept()
    if sock = invalid then return
    if setup.connections.Count() >= SetupMaxConnections()
        sock.Close()
        return
    end if

    sock.SetMessagePort(setup.port)
    sock.NotifyReadable(true)
    conn = {
        socket: sock
        inbound: ""
        outbox: ""
        sent: 0
        startedAt: setup.clock.TotalMilliseconds()
        lastActivity: setup.clock.TotalMilliseconds()
    }
    setup.connections[StrI(sock.GetID())] = conn
end sub

sub SetupServerRead(setup as dynamic, key as string, conn as dynamic)
    if not conn.socket.IsReadable() then return

    ' A fresh, zero-filled array each time: Receive writes n bytes and
    ' ToAsciiString stops at the first zero, so a reused buffer would hand back
    ' whatever the previous, longer read left behind past byte n. HTTP is text
    ' and carries no zero bytes, so the truncation is exactly the frame.
    chunk = CreateObject("roByteArray")
    chunk[SetupReadChunk() - 1] = 0
    got = conn.socket.Receive(chunk, 0, SetupReadChunk())
    if got <= 0
        SetupServerDrop(setup, key, conn)
        return
    end if

    conn.inbound = conn.inbound + chunk.ToAsciiString()
    conn.lastActivity = setup.clock.TotalMilliseconds()
    if conn.inbound.Len() > SetupMaxRequestBytes()
        SetupServerRespond(setup, key, conn, "400", SetupHtmlStatus("400"))
        return
    end if

    state = SetupRequestState(conn.inbound)
    if state = "incomplete" then return
    SetupServerHandle(setup, key, conn, state)
end sub

sub SetupServerHandle(setup as dynamic, key as string, conn as dynamic, state as string)
    if state <> "ready"
        SetupServerRespond(setup, key, conn, state, SetupHtmlStatus(state))
        return
    end if

    if not SetupSameOrigin(conn.inbound, setup.address)
        SetupServerRespond(setup, key, conn, "403", SetupHtmlStatus("403"))
        return
    end if

    path = SetupRequestPath(conn.inbound)
    ' Fixed public Apple test manifest, with one 4K video and AAC stereo only.
    ' Served by Roku itself; this diagnostic does not need a PC media server.
    if path = "/4k-control.m3u8" and SetupRequestMethod(conn.inbound) = "GET"
        body = ReadAsciiFile("pkg:/images/4k-control.m3u8")
        conn.outbox = SetupHttpResponse("200 OK",body).Replace("text/html", "application/vnd.apple.mpegurl")
        conn.sent = 0
        SetupServerFlush(setup,key,conn)
        return
    end if
    if path = "/playback-status" and SetupRequestMethod(conn.inbound) = "GET"
        data = setup.scene.callFunc("ReadPlaybackDiagnostic")
        conn.outbox = SetupHttpResponse("200 OK", FormatJson(data)).Replace("text/html", "application/json")
        conn.sent = 0
        SetupServerFlush(setup, key, conn)
        return
    end if
    if path = "/playback-test" and SetupRequestMethod(conn.inbound) = "POST"
        ' Public packages expose setup, not LAN-triggered playback controls.
        SetupServerRespond(setup, key, conn, "403", SetupHtmlStatus("403"))
        return
    end if

    if SetupRequestMethod(conn.inbound) = "GET"
        SetupServerRespond(setup, key, conn, "200", SetupHtmlPage())
        return
    end if

    manifest = SetupFormValue(SetupBody(conn.inbound), "manifest")
    url = SetupValidateManifestUrl(manifest)
    if url = ""
        inner = "<p>Give it a URL that ends in manifest.json, for example "
        inner = inner + "https://example.com/manifest.json.</p><p><a href='/'>Back</a></p>"
        SetupServerRespond(setup, key, conn, "400", SetupHtml("Not a manifest URL", inner))
        return
    end if

    ' The Scene owns the single import slot (see ImportFromSetup): it answers
    ' false while another import is running, which is a 409 to the phone and a
    ' readable summary on the TV.
    accepted = false
    if setup.scene <> invalid
        accepted = setup.scene.callFunc("RequestSetupImport", url)
    end if
    if accepted = true
        SetupServerRespond(setup, key, conn, "200", SetupHtmlSent())
    else
        SetupServerRespond(setup, key, conn, "409", SetupHtmlBusy())
    end if
end sub

sub SetupServerRespond(setup as dynamic, key as string, conn as dynamic, code as string, body as string)
    conn.outbox = SetupHttpResponse(SetupStatusText(code), body)
    conn.sent = 0
    SetupServerFlush(setup, key, conn)
end sub

' Write whatever is still queued. Send is allowed to take the response in more
' than one piece — a full send buffer returns short — so the offset is kept and
' the remainder is armed on notifyWritable instead of being dropped.
sub SetupServerFlush(setup as dynamic, key as string, conn as dynamic)
    if conn.outbox = "" then return

    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(conn.outbox)
    total = bytes.Count()

    if conn.sent < total
        wrote = conn.socket.Send(bytes, conn.sent, total - conn.sent)
        if wrote > 0
            conn.sent = conn.sent + wrote
            conn.lastActivity = setup.clock.TotalMilliseconds()
        end if
    end if

    if conn.sent >= total
        SetupServerDrop(setup, key, conn)
        return
    end if

    if not conn.socket.EOK()
        SetupServerDrop(setup, key, conn)
        return
    end if
    conn.socket.NotifyWritable(true)
end sub

sub SetupServerDrop(setup as dynamic, key as string, conn as dynamic)
    if setup.connections.DoesExist(key) then setup.connections.Delete(key)
    if conn = invalid then return
    if conn.socket = invalid then return
    conn.socket.Close()
end sub

' Every exit path in main() — the exitApp poll, the screen-closed event and
' the exitApp node event — runs this before returning. Leaving the listener
' behind would keep the port bound for the rest of the session with nothing
' draining it.
sub SetupServerClose(setup as dynamic)
    if setup = invalid then return

    keys = []
    for each key in setup.connections
        keys.Push(key)
    end for
    for each key in keys
        conn = setup.connections[key]
        if conn <> invalid
            if conn.socket <> invalid then conn.socket.Close()
        end if
    end for
    setup.connections = {}

    if setup.listen <> invalid
        setup.listen.Close()
        setup.listen = invalid
    end if
    setup.address = ""
end sub
