' DeepLinkStore unit tests.
'
' The store is pure parsing over the args AA Roku hands to Main() on an ECP
' launch (see reference/ecp-integration.md). It must accept OS-decoded or still
' percent-encoded rkio values, enforce the schema-1 contract, and never throw
' on hostile shape input. Payload strings are built with FormatJson — the brs
' interpreter has no escape mechanism for double quotes inside a string.

sub Test_DeepLink_NotOurMarker()
    Harness_Suite("DeepLinkStore ignores non-rokumio launches")
    store = DeepLinkStore()
    args = { contentid: "tt123456", rkio: "{}" }

    result = store.Parse(args)
    Harness_Equal(result.kind, "none", "plain launch is kind none")
    Harness_Ok(not result.ok, "not ok")
    Harness_Equal(result.verb, "", "no verb parsed")
end sub

sub Test_DeepLink_NoArgs()
    Harness_Suite("DeepLinkStore handles an empty or missing args map")
    store = DeepLinkStore()

    result = store.Parse(invalid)
    Harness_Equal(result.kind, "none", "invalid args yields kind none")

    result = store.Parse({})
    Harness_Equal(result.kind, "none", "empty args yields kind none")
end sub

sub Test_DeepLink_MarkerCaseInsensitive()
    Harness_Suite("DeepLinkStore matches the contentId marker case-insensitively")
    store = DeepLinkStore()
    args = { CONTENTID: "ROKUMIO-IMPORT", RKIO: FormatJson({ schema: 1 }) }

    result = store.Parse(args)
    Harness_Equal(result.kind, "import", "uppercase marker still recognized")
    Harness_Ok(result.ok, "schema-1-only payload is valid")
end sub

sub Test_DeepLink_ValidPayload()
    Harness_Suite("DeepLinkStore parses a full schema-1 payload")
    store = DeepLinkStore()
    payload = FormatJson({
        schema: 1
        addons: ["https://addon.example.com/manifest.json?token=abc", "https://other.example/manifest.json"]
        settings: { serverAddress: "http://192.168.1.40:11470" }
    })
    args = { contentid: "rokumio-import", rkio: payload }

    result = store.Parse(args)
    Harness_Equal(result.kind, "import", "import marker recognized")
    Harness_Ok(result.ok, "payload valid")
    Harness_Equal(result.schema, 1, "schema surfaced")
    Harness_Equal(result.addons.Count(), 2, "two add-on URLs")
    Harness_Equal(result.addons[0], "https://addon.example.com/manifest.json?token=abc", "first add-on URL with query kept")
    Harness_Equal(result.addons[1], "https://other.example/manifest.json", "second add-on URL kept")
    Harness_Equal(result.settings.serverAddress, "http://192.168.1.40:11470", "server address surfaced")
end sub

sub Test_DeepLink_EncodedPayload()
    Harness_Suite("DeepLinkStore percent-decodes a raw rkio value before parsing")
    store = DeepLinkStore()
    ' The client ships { "schema":1, "addons":["https://addon.example.com/manifest.json"] } through
    ' encodeURIComponent once; this is exactly what arrives if the OS does not decode it.
    encoded = "%7B%22schema%22%3A1%2C%22addons%22%3A%5B%22https%3A%2F%2Faddon.example.com%2Fmanifest.json%22%5D%7D"
    args = { contentid: "rokumio-import", rkio: encoded }

    result = store.Parse(args)
    Harness_Equal(result.kind, "import", "import marker recognized")
    Harness_Ok(result.ok, "encoded payload decodes and parses")
    Harness_Equal(result.addons.Count(), 1, "one add-on URL")
    Harness_Equal(result.addons[0], "https://addon.example.com/manifest.json", "decoded URL intact")
end sub

sub Test_DeepLink_DialLaunchArgs()
    Harness_Suite("DeepLinkStore parses the args a DIAL cold start delivers")
    store = DeepLinkStore()
    ' The companion launches over DIAL with body
    '   contentId=rokumio-import&rkio=<urlencoded>
    ' Roku passes those pairs to Main(args) keeping the sent key case; a
    ' source=dial key marks the launch transport. The store must not care.
    payload = FormatJson({
        schema: 1
        addons: ["https://addon.example.com/manifest.json"]
        settings: { serverAddress: "http://192.168.1.40:11470" }
    })
    args = {
        source: "dial"
        contentId: "rokumio-import"
        rkio: payload
    }

    result = store.Parse(args)
    Harness_Equal(result.kind, "import", "DIAL launch with our marker recognized")
    Harness_Ok(result.ok, "payload valid")
    Harness_Equal(result.addons.Count(), 1, "one add-on URL")
    Harness_Equal(result.settings.serverAddress, "http://192.168.1.40:11470", "server address surfaced")
end sub

sub Test_DeepLink_SettingsOnly()
    Harness_Suite("DeepLinkStore accepts a settings-only payload")
    store = DeepLinkStore()
    payload = FormatJson({ schema: 1, settings: { serverAddress: "http://192.168.1.50:8080/prefix" } })
    args = { contentid: "rokumio-import", rkio: payload }

    result = store.Parse(args)
    Harness_Ok(result.ok, "settings-only payload valid")
    Harness_Equal(result.addons.Count(), 0, "no add-ons requested")
    Harness_Equal(result.settings.serverAddress, "http://192.168.1.50:8080/prefix", "server address surfaced")
end sub

sub Test_DeepLink_AddonsOnly()
    Harness_Suite("DeepLinkStore accepts an add-ons-only payload")
    store = DeepLinkStore()
    payload = FormatJson({ schema: 1, addons: ["https://addon.example.com/manifest.json"] })
    args = { contentid: "rokumio-import", rkio: payload }

    result = store.Parse(args)
    Harness_Ok(result.ok, "add-ons-only payload valid")
    Harness_Equal(result.addons.Count(), 1, "one add-on URL")
    Harness_Equal(result.settings, invalid, "no settings requested")
end sub

sub Test_DeepLink_MissingRkio()
    Harness_Suite("DeepLinkStore rejects an import with no rkio payload")
    store = DeepLinkStore()
    args = { contentid: "rokumio-import" }

    result = store.Parse(args)
    Harness_Equal(result.kind, "import", "still recognized as import")
    Harness_Ok(not result.ok, "rejected")
    Harness_Equal(result.error, "missing rkio payload", "error names the gap")
end sub

sub Test_DeepLink_InvalidJson()
    Harness_Suite("DeepLinkStore rejects an unparseable rkio payload")
    store = DeepLinkStore()
    cases = [
        { raw: "{not json", error: "invalid rkio payload" }
        { raw: "", error: "missing rkio payload" }
        { raw: "   ", error: "missing rkio payload" }
        { raw: "12345", error: "invalid rkio payload" }
    ]
    for each entry in cases
        result = store.Parse({ contentid: "rokumio-import", rkio: entry.raw })
        Harness_Ok(not result.ok, "rejected: [" + entry.raw + "]")
        Harness_Equal(result.error, entry.error, "error flags the payload")
    end for
end sub

sub Test_DeepLink_SchemaRequired()
    Harness_Suite("DeepLinkStore requires the payload schema")
    store = DeepLinkStore()
    result = store.Parse({ contentid: "rokumio-import", rkio: FormatJson({ addons: [] }) })

    Harness_Ok(not result.ok, "schema-less payload rejected")
    Harness_Equal(result.error, "missing payload schema", "error names the missing field")
end sub

sub Test_DeepLink_SchemaRejected()
    Harness_Suite("DeepLinkStore rejects an unknown schema")
    store = DeepLinkStore()
    cases = [
        FormatJson({ schema: 2 })
        FormatJson({ schema: 0 })
        FormatJson({ schema: 99 })
    ]
    for each payload in cases
        result = store.Parse({ contentid: "rokumio-import", rkio: payload })
        Harness_Ok(not result.ok, "rejected: " + payload)
        Harness_Ok(result.error.InStr("unsupported payload schema") >= 0, "error names the schema mismatch")
    end for
end sub

sub Test_DeepLink_AddonsShape()
    Harness_Suite("DeepLinkStore enforces the addons array shape")
    store = DeepLinkStore()
    cases = [
        FormatJson({ schema: 1, addons: {} })
        FormatJson({ schema: 1, addons: "https://addon.example.com/manifest.json" })
        FormatJson({ schema: 1, addons: [123] })
        FormatJson({ schema: 1, addons: [""] })
        FormatJson({ schema: 1, addons: [["nested"]] })
    ]
    for each payload in cases
        result = store.Parse({ contentid: "rokumio-import", rkio: payload })
        Harness_Ok(not result.ok, "rejected: " + payload)
        Harness_Equal(result.error, "addons must be an array of URLs", "error names the shape")
    end for
end sub

sub Test_DeepLink_SettingsShape()
    Harness_Suite("DeepLinkStore enforces the settings object shape")
    store = DeepLinkStore()
    cases = [
        FormatJson({ schema: 1, settings: [] })
        FormatJson({ schema: 1, settings: "http://example.com" })
    ]
    for each payload in cases
        result = store.Parse({ contentid: "rokumio-import", rkio: payload })
        Harness_Ok(not result.ok, "rejected: " + payload)
        Harness_Equal(result.error, "settings must be an object", "error names the shape")
    end for
end sub

sub Test_DeepLink_UnknownVerb()
    Harness_Suite("DeepLinkStore flags unknown rokumio verbs")
    store = DeepLinkStore()
    result = store.Parse({ contentid: "rokumio-backup", rkio: FormatJson({ schema: 1 }) })

    Harness_Equal(result.kind, "unknown", "unregistered verb marked unknown")
    Harness_Ok(not result.ok, "never ok for an unknown verb")
    Harness_Equal(result.error, "unknown rokumio verb 'backup'", "error names the verb")
end sub

sub Test_DeepLink_DecodePercent()
    Harness_Suite("DeepLinkStore.DecodePercent converts %XX escapes")
    store = DeepLinkStore()
    Harness_Equal(store.DecodePercent("%7B%22schema%22%3A1%7D"), FormatJson({ schema: 1 }), "braces-quotes-colon decoded")
    Harness_Equal(store.DecodePercent("https%3A%2F%2Faddon.example.com%2Fmanifest.json"), "https://addon.example.com/manifest.json", "URL escapes decoded")
    Harness_Equal(store.DecodePercent("plain%20text"), "plain text", "space escape decoded")
    Harness_Equal(store.DecodePercent("100%25complete"), "100%complete", "%25 round-trips to a literal percent")
    Harness_Equal(store.DecodePercent("no escapes"), "no escapes", "unencoded text passes through")
    Harness_Equal(store.DecodePercent("bad%ZZ"), "bad%ZZ", "non-hex escapes pass through")
end sub