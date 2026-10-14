' AuthStore persistence + stremio-session tests.
'
' AuthStore is registry-backed like the other stores: guest and stremio sessions
' survive relaunches through the "session" key, and books are kept on device.
' Guest login stays purely local (no transport anywhere) — signing in still
' makes zero network calls.

sub Test_Auth_GuestPersistsAcrossReload()
    Harness_Suite("AuthStore persists a guest session across reloads")
    registry = MockRegistry()
    first = AuthStore(registry)
    first.LoginGuest()

    second = AuthStore(registry)
    Harness_Ok(second.IsLoggedIn(), "session restored")
    Harness_Equal(second.GetSession(), "guest", "guest session restored")
end sub

sub Test_Auth_LoginStremio()
    Harness_Suite("AuthStore.LoginStremio records the account session")
    auth = AuthStore()
    user = { _id: "u123", email: "x@example.com" }
    result = auth.LoginStremio("authKey123", user)

    Harness_Ok(result.ok, "login ok")
    Harness_Equal(auth.GetSession(), "stremio", "stremio session set")
    Harness_Equal(auth.GetAuthKey(), "authKey123", "auth key stored")
    Harness_Equal(auth.GetUser().email, "x@example.com", "user profile stored")
end sub

sub Test_Auth_StremioPersistsAcrossReload()
    Harness_Suite("AuthStore persists the stremio session across reloads")
    registry = MockRegistry()
    first = AuthStore(registry)
    first.LoginStremio("authKey123", { _id: "u123", email: "x@example.com" })

    second = AuthStore(registry)
    Harness_Equal(second.GetSession(), "stremio", "stremio session restored")
    Harness_Equal(second.GetAuthKey(), "authKey123", "auth key restored")
    Harness_Equal(second.GetUser().email, "x@example.com", "user profile restored")
end sub

sub Test_Auth_LogoutClearsPersisted()
    Harness_Suite("AuthStore.Logout clears the persisted session")
    registry = MockRegistry()
    first = AuthStore(registry)
    first.LoginStremio("authKey123", { _id: "u123" })

    first.Logout()
    Harness_Ok(not first.IsLoggedIn(), "logged out in memory")
    Harness_Equal(first.GetAuthKey(), "", "auth key cleared")

    second = AuthStore(registry)
    Harness_Ok(not second.IsLoggedIn(), "reload still sees logged out")
    Harness_Equal(second.GetSession(), "", "no session leaks after logout")
end sub

sub Test_Auth_LoginGuestClearsStremioData()
    Harness_Suite("AuthStore.LoginGuest drops any previous account data")
    auth = AuthStore()
    auth.LoginStremio("authKey123", { _id: "u123" })
    auth.LoginGuest()

    Harness_Equal(auth.GetSession(), "guest", "guest session set")
    Harness_Equal(auth.GetAuthKey(), "", "auth key cleared")
    Harness_Ok(auth.GetUser() = invalid, "user profile cleared")
end sub