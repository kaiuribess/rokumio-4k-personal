' LinkStremioTask — Stremio link-code pairing on a worker thread.
'
' The full login flow: GET create -> poll GET read every 3s -> POST getUser.
' The code and link are written to observable fields as soon as the create
' endpoint returns so the UI can display them. The final result arrives
' through the result field once pairing succeeds or times out.
'
' Wire format (verified against the live API): the endpoints live under
' /api/v2 and carry a type tag, and every response is envelope-wrapped —
' {"result": {...}} on success, {"error": {code, message}} while the code is
' still pending. The read poll returns error-wrapped responses until the user
' pairs the code on their phone; only a {"result": {"authKey": ...}} body means
' pairing succeeded. HTTP status is not meaningful here — check body fields.

sub init()
    m.top.functionName = "startAuth"
end sub

sub startAuth()
    http = Transport()
    try
        createRes = http.Get("https://link.stremio.com/api/v2/create?type=Create")
        result = invalid
        if createRes.ok and createRes.json <> invalid then result = createRes.json.result
        if result = invalid or result.code = invalid or result.code = ""
            m.top.result = { ok: false, authKey: "", user: invalid, error: "Could not connect to Stremio" }
            return
        end if
        m.top.code = result.code
        link = result.link
        if link = invalid or link = "" then link = "https://link.stremio.com/" + result.code
        m.top.link = link
        qr = result.qrcode
        if qr = invalid then qr = ""
        m.top.qrcode = qr

        authKey = ""
        deadline = CreateObject("roTimespan")
        deadline.Mark()
        while deadline.TotalMilliseconds() < 300000
            ' Stop-aware poll loop: MainScene sets control = "STOP" to cancel an
            ' old worker when a new code is requested (or the flow is cancelled).
            ' Removing a Task node does not kill its running thread, so the loop
            ' must check the stop signal itself.
            if m.top.control = "STOP" then exit while
            Sleep(3000)
            if deadline.TotalMilliseconds() >= 300000 then exit while
            if m.top.control = "STOP" then exit while
            readRes = http.Get("https://link.stremio.com/api/v2/read?type=Read&code=" + result.code)
            readResult = invalid
            if readRes.ok and readRes.json <> invalid then readResult = readRes.json.result
            if readResult <> invalid and readResult.authKey <> invalid and readResult.authKey <> ""
                authKey = readResult.authKey
                exit while
            end if
        end while

        ' Cancelled: stop quietly on the detached node — no stray "Login timed
        ' out" write racing the fresh task the screen rebinds to.
        if m.top.control = "STOP" then return

        if authKey = ""
            m.top.result = { ok: false, authKey: "", user: invalid, error: "Login timed out" }
            return
        end if

        userRes = http.Post("https://api.strem.io/api/getUser", { type: "GetUser", authKey: authKey })
        user = invalid
        if userRes.ok and userRes.json <> invalid and userRes.json.result <> invalid
            user = userRes.json.result
        end if

        identity = ""
        if Type(user) = "roAssociativeArray"
            if GetInterface(user._id,"ifString") <> invalid then identity = user._id
            if identity = "" and GetInterface(user.id,"ifString") <> invalid then identity = user.id
        end if
        if identity.Trim() = "" or Len(identity) > 256
            m.top.result = {ok:false,authKey:"",user:invalid,error:"Paired, but Stremio could not verify the account. Retry login."}
            return
        end if
        m.top.result = { ok: true, authKey: authKey, user: user, error: "" }
    catch e
        m.top.result = { ok: false, authKey: "", user: invalid, error: "Login failed" }
    end try
end sub
