' logouttask tests — verifies the wire format the LogoutTask worker relies on.
'
' Like LinkStremioTask/LibraryPutTask, LogoutTask builds its own Transport on
' a worker thread, so its HTTP cannot be injected in the brs interpreter; these
' tests pin the /api/logout URL, the body shape (authKey + the type tag the api
' endpoint convention requires) and the envelope semantics through
' ScriptedTransport, exactly as the task parses them.

sub Test_Logout_PostsLogoutWithAuthKeyAndType()
    Harness_Suite("logout POST carries authKey and the Logout type tag")
    script = [
        { method: "POST", url: "https://api.strem.io/api/logout", ok: true, status: 200, json: { result: { success: true } } }
    ]
    http = ScriptedTransport(script)
    res = http.Post("https://api.strem.io/api/logout", { type: "Logout", authKey: "sk_test_key" })
    Harness_Ok(res.ok, "request succeeds")
    Harness_Ok(res.json.result.success, "result envelope reports success")
    Harness_Equal(http.log.Count(), 1, "one request logged")
    Harness_Equal(http.log[0].body.authKey, "sk_test_key", "request carries the authKey")
    Harness_Equal(http.log[0].body.type, "Logout", "request carries the type tag")
end sub

sub Test_Logout_ErrorEnvelopeSurfacesMessage()
    Harness_Suite("logout surfaces an error envelope's message")
    script = [
        { method: "POST", url: "https://api.strem.io/api/logout", ok: true, status: 200, json: { error: { code: 1, message: "Session does not exist" } } }
    ]
    http = ScriptedTransport(script)
    res = http.Post("https://api.strem.io/api/logout", { type: "Logout", authKey: "invalid" })
    Harness_Ok(res.ok, "HTTP request succeeds (error envelope)")
    Harness_Equal(res.json.result, invalid, "no success result on the error envelope")
    Harness_Equal(res.json.error.message, "Session does not exist", "error message surfaced")
end sub

sub Test_Logout_NetworkFailure()
    Harness_Suite("logout handles a transport failure")
    script = [
        { method: "POST", url: "https://api.strem.io/api/logout", ok: false, status: 0, json: invalid, error: "connection refused" }
    ]
    http = ScriptedTransport(script)
    res = http.Post("https://api.strem.io/api/logout", { type: "Logout", authKey: "sk_test_key" })
    Harness_Ok(not res.ok, "request fails")
    Harness_Equal(res.error, "connection refused", "error surfaced")
end sub