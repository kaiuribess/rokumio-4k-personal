' addonsync tests — the store-side adoption and the wire format of the
' addonCollectionGet call the AddonSyncTask makes. The Task itself runs on a
' worker thread with its own Transport (like LinkStremioTask), so its HTTP
' call cannot be injected here; these tests pin the store adoption rules and
' the request/response shape the task depends on.
'
' Wire format (verified live + stremio-core): POST /api/addonCollectionGet
' with body carrying the type tag — {"type":"AddonCollectionGet","authKey":...,
' "update":true} — and every response envelope-wrapped:
' {"result":{"addons":[...],"lastModified":...}}.

function DescriptorFixture(id as string, name as string, transportUrl = "https://addon.example.com/manifest.json" as string) as object
    return {
        transportUrl: transportUrl
        manifest: {
            id: id
            name: name
            version: "2.1.0"
            types: ["movie", "series"]
            catalogs: [ { type: "movie", id: "top", name: "Top" } ]
            resources: [ "catalog", { name: "meta", types: ["movie"], idPrefixes: ["tt"] }, "stream" ]
        }
    }
end function

sub Test_AddonSync_InstallsDescriptorIntoRecord()
    Harness_Suite("InstallFromDescriptor builds and registers a record")
    addons = AddonsStore(ScriptedTransport([]), invalid, "stremio")
    desc = DescriptorFixture("com.test.addon", "Test Addon")
    outcome = addons.InstallFromDescriptor(desc.transportUrl, desc.manifest)
    Harness_Ok(outcome.ok, "install succeeds")
    Harness_Equal(outcome.id, "com.test.addon", "id set")
    addon = addons.Get("com.test.addon")
    Harness_Ok(addon <> invalid, "addon resolves after install")
    Harness_Equal(addon.name, "Test Addon", "name correct")
    Harness_Equal(addon.version, "2.1.0", "version correct")
    Harness_Equal(addon.address, "https://addon.example.com", "address stripped of /manifest.json")
    Harness_Equal(addon.builtin, false, "not marked builtin")
    Harness_Equal(addon.resources.Count(), 3, "resources normalized to three descriptors")
    Harness_Equal(addon.resources[0].name, "catalog", "short string resource keeps its name")
    Harness_Equal(addon.resources[0].short, true, "short string resource flagged as short")
    Harness_Equal(addon.resources[1].name, "meta", "object resource keeps its name")
    Harness_Equal(addon.resources[1].short, false, "object resource flagged as full")
    Harness_Equal(addon.resources[1].types[0], "movie", "object resource types preserved")
    Harness_Equal(addon.resources[1].idPrefixes[0], "tt", "object resource idPrefixes preserved")
    Harness_Equal(addon.resources[2].name, "stream", "third resource")
    Harness_Equal(addon.types.Count(), 2, "types preserved")
    Harness_Equal(addon.catalogs.Count(), 1, "catalogs preserved")
end sub

sub Test_AddonSync_PreservesQueryArgsInAddress()
    Harness_Suite("InstallFromDescriptor keeps query args in address")
    addons = AddonsStore(ScriptedTransport([]), invalid, "stremio")
    desc = DescriptorFixture("com.test.qa", "QA Addon", "https://addon.example.com/manifest.json?token=abc123")
    outcome = addons.InstallFromDescriptor(desc.transportUrl, desc.manifest)
    Harness_Ok(outcome.ok, "install succeeds")
    addon = addons.Get("com.test.qa")
    Harness_Ok(addon <> invalid, "addon resolves")
    Harness_Equal(addon.address, "https://addon.example.com?token=abc123", "query args preserved in address")
end sub

sub Test_AddonSync_DuplicateSkipped()
    Harness_Suite("InstallFromDescriptor skips a duplicate id")
    addons = AddonsStore(ScriptedTransport([]), invalid, "stremio")
    desc = DescriptorFixture("com.test.dup", "Dup Addon")
    first = addons.InstallFromDescriptor(desc.transportUrl, desc.manifest)
    Harness_Ok(first.ok, "first install succeeds")
    second = addons.InstallFromDescriptor(desc.transportUrl, desc.manifest)
    Harness_Ok(not second.ok, "second install fails")
    Harness_Equal(second.error, "addon already installed", "duplicate error message")
    Harness_Equal(addons.GetAll().Count(), 1, "only one addon registered")
end sub

sub Test_AddonSync_MissingManifestIdentity()
    Harness_Suite("InstallFromDescriptor rejects manifest missing id or name")
    addons = AddonsStore(ScriptedTransport([]), invalid, "stremio")

    missingId = addons.InstallFromDescriptor("https://addon.example.com/manifest.json", { name: "No Id", version: "1", types: [], catalogs: [], resources: [] })
    Harness_Ok(not missingId.ok, "missing id rejected")
    Harness_Equal(missingId.error, "manifest missing id or name", "correct error for missing id")

    missingName = addons.InstallFromDescriptor("https://addon.example.com/manifest.json", { id: "com.test.noname", version: "1", types: [], catalogs: [], resources: [] })
    Harness_Ok(not missingName.ok, "missing name rejected")
    Harness_Equal(missingName.error, "manifest missing id or name", "correct error for missing name")
end sub

sub Test_AddonSync_RejectsNonHttpTransport()
    Harness_Suite("InstallFromDescriptor rejects non-http(s) transports")
    addons = AddonsStore(ScriptedTransport([]), invalid, "stremio")
    outcome = addons.InstallFromDescriptor("stremio://some-host/addon/manifest.json", { id: "com.stremio.test", name: "Stremio Test", version: "1", types: [], catalogs: [], resources: [] })
    Harness_Ok(not outcome.ok, "stremio:// transport rejected")
    Harness_Equal(outcome.error, "unsupported addon transport", "error names the unsupported transport")
end sub

sub Test_AddonSync_NamelessCatalogGetsFallbackName()
    Harness_Suite("InstallFromDescriptor fills a missing catalog name")
    desc = DescriptorFixture("com.test.nameless", "Nameless Addon")
    desc.manifest.catalogs = [
        { type: "movie", id: "top" }
        { type: "series", id: "videos" }
    ]
    addons = AddonsStore(ScriptedTransport([]), invalid, "stremio")
    outcome = addons.InstallFromDescriptor(desc.transportUrl, desc.manifest)
    Harness_Ok(outcome.ok, "install succeeds")
    addon = addons.Get("com.test.nameless")
    Harness_Ok(addon <> invalid, "addon resolves")
    Harness_Equal(addon.catalogs[0].name, "Nameless Addon", "first catalog named from addon name")
    Harness_Equal(addon.catalogs[1].name, "Nameless Addon", "second catalog named from addon name")
    Harness_Equal(addon.catalogs[0].id, "top", "catalog id preserved")
    Harness_Equal(addon.catalogs[0].type, "movie", "catalog type preserved")
end sub

sub Test_AddonSync_CatalogNameFallsBackToId()
    Harness_Suite("NormalizeCatalogNames falls back to the catalog id when the addon name is blank")
    addons = AddonsStore(ScriptedTransport([]), invalid, "stremio")
    catalogs = addons.NormalizeCatalogNames([ { type: "movie", id: "publicdomainmovies" } ], "")
    Harness_Equal(catalogs[0].name, "publicdomainmovies", "catalog named from its id")
end sub

sub Test_AddonSync_NamedCatalogUnchanged()
    Harness_Suite("InstallFromDescriptor leaves present catalog names untouched")
    desc = DescriptorFixture("com.test.named", "Named Addon")
    addons = AddonsStore(ScriptedTransport([]), invalid, "stremio")
    outcome = addons.InstallFromDescriptor(desc.transportUrl, desc.manifest)
    Harness_Ok(outcome.ok, "install succeeds")
    addon = addons.Get("com.test.named")
    Harness_Ok(addon <> invalid, "addon resolves")
    Harness_Equal(addon.catalogs[0].name, "Top", "catalog keeps its own name")
    Harness_Equal(addon.catalogs[0].id, "top", "catalog id kept")
end sub

sub Test_AddonSync_ApiRequestCarriesTypeTag()
    Harness_Suite("addonCollectionGet POST carries the type tag and authKey")
    script = [
        {
            method: "POST"
            url: "https://api.strem.io/api/addonCollectionGet"
            ok: true
            status: 200
            json: { result: { addons: [], lastModified: 1750000000000 } }
        }
    ]
    http = ScriptedTransport(script)
    res = http.Post("https://api.strem.io/api/addonCollectionGet", { type: "AddonCollectionGet", authKey: "sk_test_key", update: true })
    Harness_Ok(res.ok, "request succeeds")
    Harness_Equal(http.log.Count(), 1, "one request logged")
    Harness_Equal(http.log[0].body.type, "AddonCollectionGet", "request carries the type tag")
    Harness_Equal(http.log[0].body.authKey, "sk_test_key", "request carries the authKey")
    Harness_Equal(http.log[0].body.update, true, "request sends update:true")
end sub

sub Test_AddonSync_DescriptorsParsedFromEnvelope()
    Harness_Suite("addonCollectionGet response descriptors are parsed correctly")
    script = [
        {
            method: "POST"
            url: "https://api.strem.io/api/addonCollectionGet"
            ok: true
            status: 200
            json: {
                result: {
                    addons: [
                        { transportUrl: "https://cinemeta.strem.io/manifest.json", manifest: { id: "com.linvo.cinemeta", name: "Cinemeta", version: "3.0.0", types: ["movie", "series"], catalogs: [ { type: "movie", id: "top", name: "Top" } ], resources: [ "catalog", "meta" ] } },
                        { transportUrl: "https://opensubtitles.strem.io/manifest.json", manifest: { id: "org.stremio.opensubtitles", name: "OpenSubtitles", version: "1.0.0", types: ["movie", "series"], catalogs: [], resources: [ "subtitles" ] } }
                    ]
                    lastModified: 1750000000000
                }
            }
        }
    ]
    http = ScriptedTransport(script)
    res = http.Post("https://api.strem.io/api/addonCollectionGet", { type: "AddonCollectionGet", authKey: "sk_abc", update: true })
    Harness_Ok(res.ok, "request succeeds")
    result = res.json.result
    Harness_Ok(result <> invalid, "result envelope present")
    Harness_Equal(result.addons.Count(), 2, "two addons in the collection")
    addons = AddonsStore(ScriptedTransport([]), invalid, "stremio")
    for each entry in result.addons
        addons.InstallFromDescriptor(entry.transportUrl, entry.manifest)
    end for
    Harness_Ok(addons.Get("com.linvo.cinemeta") <> invalid, "cinemeta registered from collection")
    Harness_Equal(addons.Get("com.linvo.cinemeta").address, "https://cinemeta.strem.io", "cinemeta address correct")
    Harness_Equal(addons.Get("com.linvo.cinemeta").version, "3.0.0", "cinemeta version from manifest")
    Harness_Ok(addons.Get("org.stremio.opensubtitles") <> invalid, "opensubtitles registered from collection")
    Harness_Equal(addons.Get("org.stremio.opensubtitles").resources.Count(), 1, "opensubtitles resources normalized")
    Harness_Equal(addons.GetAll().Count(), 2, "both addons in GetAll")
end sub

sub Test_AddonSync_ApiErrorEnvelope()
    Harness_Suite("addonCollectionGet error envelope yields empty descriptors")
    script = [
        {
            method: "POST"
            url: "https://api.strem.io/api/addonCollectionGet"
            ok: true
            status: 200
            json: { error: { code: 1, message: "Session does not exist" } }
        }
    ]
    http = ScriptedTransport(script)
    res = http.Post("https://api.strem.io/api/addonCollectionGet", { type: "AddonCollectionGet", authKey: "bad-key", update: true })
    Harness_Ok(res.ok, "HTTP request succeeds (error envelope)")
    Harness_Equal(res.json.result, invalid, "no result in error envelope")
    Harness_Equal(res.json.error.message, "Session does not exist", "error message surfaced")
end sub

sub Test_AddonSync_StremioSessionPersistsToRegistryKey()
    Harness_Suite("InstallFromDescriptor in stremio session writes to stremio_addons key")
    registry = MockRegistry()
    addons = AddonsStore(ScriptedTransport([]), registry, "stremio")
    desc = DescriptorFixture("com.test.persists", "Persist Addon")
    outcome = addons.InstallFromDescriptor(desc.transportUrl, desc.manifest)
    Harness_Ok(outcome.ok, "install succeeds")
    Harness_Equal(addons.GetAll().Count(), 1, "one addon present")
    rawStremio = registry.Read("stremio_addons")
    Harness_Ok(rawStremio <> "", "stremio_addons key written")
    parsed = ParseJson(rawStremio)
    Harness_Ok(parsed <> invalid and parsed["com.test.persists"] <> invalid, "record stored under stremio key")
    rawGuest = registry.Read("addons")
    Harness_Equal(rawGuest, "", "guest addons key untouched")
end sub