' Shared test doubles for the store suites.
'
' MockRegistry mirrors the roRegistrySection surface (Read/Write/Flush) so
' persistence is testable in the interpreter. ScriptedTransport serves both
' Get and Post from a script of pre-parsed transport results, matching on HTTP
' method + URL (a blank method or url in an entry matches anything), and logs
' every request made. Suites assert against the log and inject via the script.

function MockRegistry() as object
    registry = { values: {}, durable:{}, failWrites: false, failFlushes:false }
    registry.Read = function(key as string) as string
        if m.values[key] <> invalid then return m.values[key]
        return ""
    end function
    ' Returns a boolean and can be told to refuse, because roRegistrySection.Write
    ' answers with one. A void stand-in would read as a failure to every caller
    ' that checks, and a stand-in that always succeeded could not exercise the
    ' path where the registry says no.
    registry.Write = function(key as string, value as string) as boolean
        if m.failWrites then return false
        m.values[key] = value
        return true
    end function
    registry.Flush = function() as boolean
        if m.failFlushes then return false
        m.durable = {}
        for each key in m.values
            m.durable[key] = m.values[key]
        end for
        return true
    end function
    registry.Exists = function(key as string) as boolean
        return m.values.DoesExist(key)
    end function
    registry.Delete = function(key as string) as boolean
        return m.values.Delete(key)
    end function
    registry.GetKeyList = function() as object
        return m.values.Keys()
    end function
    return registry
end function

function ScriptedTransport(script as object) as object
    transport = { _script: script, log: [] }
    transport._respond = function(method as string, url as string, body as dynamic, headers = invalid as dynamic, timeoutMs = invalid as dynamic) as object
        for each entry in m._script
            if (entry.method = invalid or entry.method = method) and (entry.url = invalid or entry.url = url)
                m.log.Push({ method: method, url: url, body: body, headers: headers, timeoutMs: timeoutMs })
                return { ok: entry.ok, status: entry.status, json: entry.json, error: entry.error }
            end if
        end for
        m.log.Push({ method: method, url: url, body: body, headers: headers, timeoutMs: timeoutMs })
        return { ok: false, status: 0, json: invalid, error: "no scripted response" }
    end function
    transport.Get = function(url as string, headers = invalid as dynamic, timeoutMs = invalid as dynamic) as object
        return m._respond("GET", url, invalid, headers, timeoutMs)
    end function
    ' The raw twin of _respond: the body comes back as text rather than as parsed
    ' json, which is the shape Transport.GetRaw speaks. An entry that scripts no
    ' `body` yields an empty one rather than a fabricated body.
    transport._respondRaw = function(method as string, url as string, headers = invalid as dynamic, timeoutMs = invalid as dynamic) as object
        for each entry in m._script
            if (entry.method = invalid or entry.method = method) and (entry.url = invalid or entry.url = url)
                m.log.Push({ method: method, url: url, headers: headers, timeoutMs: timeoutMs, body: entry.body })
                return { ok: entry.ok, status: entry.status, body: entry.body, error: entry.error }
            end if
        end for
        m.log.Push({ method: method, url: url, headers: headers, timeoutMs: timeoutMs, body: invalid })
        return { ok: false, status: 0, body: invalid, error: "no scripted response" }
    end function
    ' timeoutMs is accepted and logged, not just ignored, matching Transport's real
    ' signatures. A mock that swallows it cannot show that two requests were given
    ' two different budgets — which is the whole claim the warm-up's split constants
    ' rest on, and the thing that let a 40ms request and the request meant to block
    ' share one number. A mock that declared fewer parameters than the real client
    ' is also how a seam starts lying about what it accepts.
    transport.GetRaw = function(url as string, timeoutMs = invalid as dynamic, headers = invalid as dynamic) as object
        return m._respondRaw("GET", url, headers, timeoutMs)
    end function
    ' The HEAD twin: raw-shaped, because a HEAD carries no body to parse and
    ' Transport.Head returns the client's raw result for the same reason
    ' GetRaw does.
    transport.Head = function(url as string, timeoutMs = invalid as dynamic) as object
        return m._respondRaw("HEAD", url, invalid, timeoutMs)
    end function
    transport.Post = function(url as string, body = invalid as dynamic, headers = invalid as dynamic) as object
        return m._respond("POST", url, body)
    end function
    transport.PostLong = function(url as string, body = invalid as dynamic, headers = invalid as dynamic) as object
        return m._respond("POST", url, body)
    end function
    transport.EndpointUrl = function(storedAddress as string, endpointPath as string) as string
        at = storedAddress.InStr("?")
        if at < 0 then return storedAddress + endpointPath
        return storedAddress.Left(at) + endpointPath + storedAddress.Mid(at)
    end function
    ' Forwards to the real implementation in Transport.bs rather than repeating
    ' it. A copy here would let the suite assert an encoding the device never
    ' produces, which is precisely the failure this file exists to prevent.
    transport.EncodeQueryValue = function(value as string) as string
        return PercentEncode(value)
    end function
    return transport
end function
