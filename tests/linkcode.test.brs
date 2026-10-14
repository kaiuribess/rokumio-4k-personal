' linkcode tests — verifies the Transport layer and API wire format that the
' LinkStremioTask relies on. The Task itself creates its own Transport and runs
' on a worker thread, so its HTTP flow cannot be injected in the brs
' interpreter; these tests validate that the endpoints resolve correctly
' through ScriptedTransport and that the full login flow logic holds.
'
' Wire format (verified against the live API, see
' reference/stremio-integration-plan.md): link endpoints live under
' /api/v2 and take a type tag; every response is envelope-wrapped —
' {"result": {...}} on success, {"error": {code, message}} while pending.
' getUser lives at /api/getUser and its body carries a type tag too.

sub Test_LinkCode_CreateReturnsCodeAndLink()
    Harness_Suite("Link-code create returns code and link")
    script = [
        { method: "GET", url: "https://link.stremio.com/api/v2/create?type=Create", ok: true, status: 200, json: { result: { code: "ABC123", link: "https://link.stremio.com/ABC123", qrcode: "https://link.stremio.com/qr?data=abc" } } }
    ]
    http = ScriptedTransport(script)
    res = http.Get("https://link.stremio.com/api/v2/create?type=Create")
    Harness_Ok(res.ok, "create request succeeds")
    Harness_Equal(res.json.result.code, "ABC123", "code returned")
    Harness_Equal(res.json.result.link, "https://link.stremio.com/ABC123", "link returned")
end sub

sub Test_LinkCode_ReadReturnsAuthKeyOnSuccess()
    Harness_Suite("Link-code read returns authKey when pairing completes")
    script = [
        { method: "GET", url: "https://link.stremio.com/api/v2/read?type=Read&code=ABC123", ok: true, status: 200, json: { result: { authKey: "sk_auth_999" } } }
    ]
    http = ScriptedTransport(script)
    res = http.Get("https://link.stremio.com/api/v2/read?type=Read&code=ABC123")
    Harness_Ok(res.ok, "read request succeeds")
    Harness_Equal(res.json.result.authKey, "sk_auth_999", "authKey returned")
end sub

sub Test_LinkCode_ReadReturnsErrorWhilePending()
    Harness_Suite("Link-code read returns error before user completes pairing")
    script = [
        { method: "GET", url: "https://link.stremio.com/api/v2/read?type=Read&code=PENDING1", ok: true, status: 200, json: { error: { code: 101, message: "Invalid or expired token" } } }
    ]
    http = ScriptedTransport(script)
    res = http.Get("https://link.stremio.com/api/v2/read?type=Read&code=PENDING1")
    Harness_Ok(res.ok, "HTTP request succeeds")
    Harness_Ok(res.json.error <> invalid, "error envelope returned while pending")
    Harness_Equal(res.json.result, invalid, "no result wrapper yet")
end sub

sub Test_LinkCode_GetUserReturnsProfile()
    Harness_Suite("getUser returns user profile for a valid authKey")
    script = [
        { method: "POST", url: "https://api.strem.io/api/getUser", ok: true, status: 200, json: { result: { _id: "u42", email: "test@strem.io", avatar: "https://img.strem.io/avatar/u42.png" } } }
    ]
    http = ScriptedTransport(script)
    res = http.Post("https://api.strem.io/api/getUser", { type: "GetUser", authKey: "sk_auth_999" })
    Harness_Ok(res.ok, "getUser succeeds")
    Harness_Equal(res.json.result._id, "u42", "user id returned")
    Harness_Equal(res.json.result.email, "test@strem.io", "user email returned")
    Harness_Equal(http.log.Count(), 1, "one request logged")
    Harness_Equal(http.log[0].body.type, "GetUser", "request carries the type tag")
    Harness_Equal(http.log[0].body.authKey, "sk_auth_999", "request carries the authKey")
end sub

sub Test_LinkCode_GetUserFailure()
    Harness_Suite("getUser returns error for invalid authKey")
    script = [
        { method: "POST", url: "https://api.strem.io/api/getUser", ok: true, status: 200, json: { error: { code: 1, message: "Session does not exist" } } }
    ]
    http = ScriptedTransport(script)
    res = http.Post("https://api.strem.io/api/getUser", { type: "GetUser", authKey: "invalid" })
    Harness_Ok(res.ok, "HTTP request succeeds (error envelope)")
    Harness_Equal(res.json.result, invalid, "no profile when the session is unknown")
    Harness_Equal(res.json.error.message, "Session does not exist", "error message surfaced")
end sub

sub Test_LinkCode_CreateNetworkFailure()
    Harness_Suite("Link-code create handles network failure")
    script = [
        { method: "GET", url: "https://link.stremio.com/api/v2/create?type=Create", ok: false, status: 0, json: invalid, error: "connection refused" }
    ]
    http = ScriptedTransport(script)
    res = http.Get("https://link.stremio.com/api/v2/create?type=Create")
    Harness_Ok(not res.ok, "create request fails")
    Harness_Equal(res.error, "connection refused", "error surfaced")
end sub

sub Test_LinkCode_FullFlowSimulation()
    Harness_Suite("Full link-code flow: create -> read -> getUser")
    authKey = ""
    user = invalid
    http = ScriptedTransport([
        { url: "https://link.stremio.com/api/v2/create?type=Create", ok: true, status: 200, json: { result: { code: "TEST01", link: "https://link.stremio.com/TEST01" } } },
        { url: "https://link.stremio.com/api/v2/read?type=Read&code=TEST01", ok: true, status: 200, json: { result: { authKey: "sk_abc" } } },
        { url: "https://api.strem.io/api/getUser", ok: true, status: 200, json: { result: { _id: "u7", email: "flow@test.com" } } }
    ])

    createRes = http.Get("https://link.stremio.com/api/v2/create?type=Create")
    Harness_Ok(createRes.ok, "create succeeds")
    Harness_Equal(createRes.json.result.code, "TEST01", "code extracted from result envelope")

    readRes = http.Get("https://link.stremio.com/api/v2/read?type=Read&code=" + createRes.json.result.code)
    Harness_Ok(readRes.ok, "read succeeds after create")
    authKey = readRes.json.result.authKey
    Harness_Equal(authKey, "sk_abc", "authKey extracted from result envelope")

    userRes = http.Post("https://api.strem.io/api/getUser", { type: "GetUser", authKey: authKey })
    Harness_Ok(userRes.ok, "getUser succeeds")
    user = userRes.json.result
    Harness_Equal(user._id, "u7", "user id correct")

    auth = AuthStore()
    result = auth.LoginStremio(authKey, user)
    Harness_Ok(result.ok, "auth store accepts login")
    Harness_Equal(auth.GetSession(), "stremio", "session set to stremio")
    Harness_Equal(auth.GetAuthKey(), "sk_abc", "authKey persisted in store")
    Harness_Equal(auth.GetUser().email, "flow@test.com", "user profile persisted")
end sub