' Minimal self-contained test harness for the brs interpreter.
'
' Pure BrightScript only — no classes, no BrighterScript-only syntax — so the
' brs CLI can run it unmodified. npm test transpiles the BSL sources first, then
' hands them to brs along with this harness, the suites and tests/_run.brs.
'
'   brs <transpiled sources...> tests/harness.brs tests/<suite>.brs tests/_run.brs

' File-scope tally. tests/run.js concatenates this file, the suites and the
' runner into ONE script, so every function here shares this `m`.
m.passed = 0
m.failed = 0

' A safe stringizer for the interpreter — the Roku built-in toJson() is not
' implemented in @rokucommunity/brs, so Harness_Equal would abort the suite on
' the first failing assertion. This handles every type our tests compare.
function ToJson(value as dynamic) as string
    if value = invalid then return "invalid"
    vtype = Type(value)
    if vtype = "String" or vtype = "roString" then return value
    if vtype = "Integer" or vtype = "roInteger" or vtype = "Float" then return value.ToStr()
    if vtype = "Boolean" or vtype = "roBoolean"
        if value then return "true"
        return "false"
    end if
    return vtype
end function

function Harness_Suite(name as string) as void
    print ""
    print "SUITE: " + name
end function

function Harness_Ok(condition as boolean, what as string) as void
    if condition
        m.passed++
        print "    ok   " + what
    else
        m.failed++
        print "    FAIL " + what
    end if
end function

function Harness_Equal(actual as dynamic, expected as dynamic, what as string) as void
    if actual = expected
        m.passed++
        print "    ok   " + what
    else
        m.failed++
        print "    FAIL " + what + "  expected [" + toJson(expected) + "] got [" + toJson(actual) + "]"
    end if
end function

function Harness_Finish() as void
    print ""
    print "Assertions passed: " + m.passed.ToStr() + "  failed: " + m.failed.ToStr()
    if m.failed = 0
        print "RESULT: PASS"
    else
        print "RESULT: FAIL"
    end if
end function