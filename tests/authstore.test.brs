' AuthStore unit tests.
'
' Guest login is a purely local session: no transport, no network call, no
' authKey. Signing in as guest simply means the app runs without an account, so
' nothing syncs. The session string is the single source of truth for signed-in.

sub Test_Auth_GuestLogin()
    Harness_Suite("AuthStore.LoginGuest creates a local guest session")
    auth = AuthStore()
    result = auth.LoginGuest()

    Harness_Ok(result.ok, "guest login ok")
    Harness_Equal(auth.GetSession(), "guest", "session set to guest")
    Harness_Ok(auth.IsLoggedIn(), "isLoggedIn true")
end sub

sub Test_Auth_GuestIsLocalOnly()
    Harness_Suite("AuthStore guest login involves no transport")
    auth = AuthStore()
    auth.LoginGuest()
    auth.LoginGuest()

    Harness_Ok(auth.IsLoggedIn(), "still logged in after repeated calls")
    Harness_Equal(auth.GetSession(), "guest", "session unchanged")
end sub

sub Test_Auth_DefaultIsLoggedOut()
    Harness_Suite("AuthStore starts logged out")
    auth = AuthStore()

    Harness_Ok(not auth.IsLoggedIn(), "not logged in by default")
    Harness_Equal(auth.GetSession(), "", "session empty by default")
end sub

sub Test_Auth_InstancesIndependent()
    Harness_Suite("each AuthStore owns its own session")
    a = AuthStore()
    b = AuthStore()
    a.LoginGuest()

    Harness_Ok(a.IsLoggedIn(), "first instance logged in")
    Harness_Ok(not b.IsLoggedIn(), "second instance unaffected")
end sub

sub Test_Auth_Logout()
    Harness_Suite("AuthStore.Logout clears the session")
    auth = AuthStore()
    auth.LoginGuest()

    auth.Logout()
    Harness_Equal(auth.GetSession(), "", "session cleared")
    Harness_Ok(not auth.IsLoggedIn(), "no longer logged in")
end sub