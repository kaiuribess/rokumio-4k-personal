' LogoutTask — best-effort server-side logout of the Stremio session.
'
' A single /api/logout through StremioApiStore and nothing else. The local
' logout always proceeds regardless of this worker's outcome (server-side
' cleanup is hygiene, not gating), so it fires lazily: MainScene spawns it, logs
' the result and moves on. A blank authKey short-circuits to success — there is
' nothing to revoke.

sub init()
    m.top.functionName = "logout"
end sub

sub logout()
    if m.top.authKey = invalid or m.top.authKey = ""
        m.top.result = { ok: true, error: "" }
        return
    end if
    try
        store = StremioApiStore(Transport(), m.top.authKey)
        result = store.Logout()
        m.top.result = result
    catch e
        m.top.result = { ok: false, error: e.message }
    end try
end sub