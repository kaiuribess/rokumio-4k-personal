' CatalogStore unit tests.
'
' CatalogStore is pure transport: catalog/manifest/search are endpoint calls to
' an add-on server and nothing is stored locally. The scripted transport owns
' the exact URLs so the URL-building contract is pinned by these tests.

sub Test_Catalog_Manifest()
    Harness_Suite("CatalogStore.Manifest normalizes a manifest")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/manifest.json"
            ok: true
            status: 200
            json: {
                id: "com.linvo.cinemeta"
                name: "Cinemeta"
                version: "3.0.14"
                types: ["movie", "series"]
                catalogs: [
                    { type: "movie", id: "top", name: "Top" }
                    { type: "series", id: "top", name: "Top Series" }
                ]
                resources: ["catalog", "meta"]
            }
            error: ""
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Manifest(address)

    Harness_Ok(result.ok, "manifest ok")
    Harness_Equal(result.manifest.id, "com.linvo.cinemeta", "id parsed")
    Harness_Equal(result.manifest.name, "Cinemeta", "name parsed")
    Harness_Equal(result.manifest.catalogs.Count(), 2, "catalogs parsed")
end sub

sub Test_Catalog_ManifestRejectsMissingId()
    Harness_Suite("CatalogStore.Manifest rejects a manifest without id")
    script = [
        { method: "GET", ok: true, status: 200, json: { name: "No id" }, error: "" }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Manifest("https://addon.example.com")

    Harness_Ok(not result.ok, "manifest rejected")
    Harness_Equal(result.error, "manifest missing id or name", "error names the missing field")
end sub

sub Test_Catalog_FetchPreservesQuery()
    Harness_Suite("CatalogStore.Catalog keeps user query args in the URL")
    script = [
        {
            method: "GET"
            url: "https://addon.example.com/catalog/movie/top/skip=0.json?provider=yts"
            ok: true
            status: 200
            json: { metas: [ { id: "tt0000001", type: "movie", name: "One" } ] }
            error: ""
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Catalog("https://addon.example.com?provider=yts", "movie", "top")

    Harness_Ok(result.ok, "catalog ok")
    Harness_Equal(result.metas.Count(), 1, "one meta returned")
end sub

sub Test_Catalog_Fetch()
    Harness_Suite("CatalogStore.Catalog fetches a catalog row")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/catalog/movie/top/skip=0.json"
            ok: true
            status: 200
            json: {
                metas: [
                    { id: "tt0000001", type: "movie", name: "One" }
                    { id: "tt0000002", type: "movie", name: "Two" }
                ]
            }
            error: ""
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Catalog(address, "movie", "top")

    Harness_Ok(result.ok, "catalog ok")
    Harness_Equal(result.metas.Count(), 2, "two metas returned")
    Harness_Equal(result.metas[0].name, "One", "meta fields intact")
end sub

sub Test_Catalog_DiscoverTop()
    Harness_Suite("CatalogStore builds the Discover Popular catalog URL")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/catalog/movie/top/skip=0.json"
            ok: true
            status: 200
            json: { metas: [ { id: "tt0000001", type: "movie", name: "One" } ] }
            error: ""
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Catalog(address, "movie", "top", "skip=0")

    Harness_Ok(result.ok, "popular catalog ok")
    Harness_Equal(store.transport.log[0].url, address + "/catalog/movie/top/skip=0.json", "Defaults to the Popular + All + skip=0 shape")
end sub

sub Test_Catalog_DiscoverGenre()
    Harness_Suite("CatalogStore builds a Discover genre catalog URL")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/catalog/series/top/genre=Action&skip=0.json"
            ok: true
            status: 200
            json: { metas: [ { id: "tt0000002", type: "series", name: "Two" } ] }
            error: ""
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Catalog(address, "series", "top", "genre=Action&skip=0")

    Harness_Ok(result.ok, "genre catalog ok")
    Harness_Equal(store.transport.log[0].url, address + "/catalog/series/top/genre=Action&skip=0.json", "Genre joins the skip param in the extra segment")
end sub

sub Test_Catalog_DiscoverYear()
    Harness_Suite("CatalogStore builds a Discover New/this-year catalog URL")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/catalog/movie/year/genre=2026&skip=0.json"
            ok: true
            status: 200
            json: { metas: [ { id: "tt0000003", type: "movie", name: "Three" } ] }
            error: ""
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Catalog(address, "movie", "year", "genre=2026&skip=0")

    Harness_Ok(result.ok, "year catalog ok")
    Harness_Equal(store.transport.log[0].url, address + "/catalog/movie/year/genre=2026&skip=0.json", "New chart pins the current year")
end sub

sub Test_Catalog_DiscoverFeatured()
    Harness_Suite("CatalogStore builds a Discover Featured catalog URL")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/catalog/series/imdbRating/skip=0.json"
            ok: true
            status: 200
            json: { metas: [ { id: "tt0000004", type: "series", name: "Four" } ] }
            error: ""
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Catalog(address, "series", "imdbRating", "skip=0")

    Harness_Ok(result.ok, "featured catalog ok")
    Harness_Equal(store.transport.log[0].url, address + "/catalog/series/imdbRating/skip=0.json", "Featured uses imdbRating")
end sub

sub Test_Catalog_DiscoverNextPage()
    Harness_Suite("CatalogStore advances a Discover page via its own skip")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/catalog/movie/top/genre=Sci-Fi&skip=50.json"
            ok: true
            status: 200
            json: {
                metas: [
                    { id: "tt0000005", type: "movie", name: "Five" }
                    { id: "tt0000006", type: "movie", name: "Six" }
                ]
                hasMore: true
            }
            error: ""
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Catalog(address, "movie", "top", "genre=Sci-Fi&skip=50")

    Harness_Ok(result.ok, "next page ok")
    Harness_Equal(store.transport.log[0].url, address + "/catalog/movie/top/genre=Sci-Fi&skip=50.json", "skip advances past the metas already shown")
    Harness_Ok(result.hasMore, "hasMore rides along when the server says so")
end sub

sub Test_Catalog_HasMoreFlag()
    Harness_Suite("CatalogStore reports hasMore=false when the server omits it")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/catalog/movie/top/skip=100.json"
            ok: true
            status: 200
            json: { metas: [ { id: "tt0000007", type: "movie", name: "Seven" } ] }
            error: ""
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Catalog(address, "movie", "top", "skip=100")

    Harness_Ok(result.ok, "final page ok")
    Harness_Equal(result.hasMore, false, "a response without hasMore stops pagination")
end sub

sub Test_Catalog_Search()
    Harness_Suite("CatalogStore.Search hits the add-on search catalog")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/catalog/movie/top/search=matrix.json"
            ok: true
            status: 200
            json: { metas: [ { id: "tt0133093", type: "movie", name: "The Matrix" } ] }
            error: ""
        }
        {
            method: "GET"
            url: address + "/catalog/series/top/search=percy%20jackson.json"
            ok: true
            status: 200
            json: { metas: [ { id: "tt1489428", type: "series", name: "Percy Jackson" } ] }
            error: ""
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Search(address, "movie", "matrix")

    Harness_Ok(result.ok, "movie search ok")
    Harness_Equal(result.metas.Count(), 1, "one movie meta returned")
    Harness_Equal(store.transport.log[0].url, address + "/catalog/movie/top/search=matrix.json", "movie query hits /top/search=")

    result = store.Search(address, "series", "percy jackson")
    Harness_Ok(result.ok, "series search ok")
    Harness_Equal(result.metas.Count(), 1, "one series meta returned")
    Harness_Equal(store.transport.log[1].url, address + "/catalog/series/top/search=percy%20jackson.json", "query percent-encoded in the URL")
end sub

sub Test_Catalog_SearchExplicitCatalogId()
    Harness_Suite("CatalogStore.Search routes an explicit catalog id")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/catalog/movie/year/search=matrix.json"
            ok: true
            status: 200
            json: { metas: [ { id: "tt0133093", type: "movie", name: "The Matrix" } ] }
            error: ""
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Search(address, "movie", "matrix", "year")

    Harness_Ok(result.ok, "search with explicit catalog id ok")
    Harness_Equal(result.metas.Count(), 1, "one meta returned")
    Harness_Equal(store.transport.log[0].url, address + "/catalog/movie/year/search=matrix.json", "non-default catalog id reaches the URL")
end sub

sub Test_Catalog_RejectsMissingMetas()
    Harness_Suite("CatalogStore.Catalog rejects a payload without metas")
    script = [
        { method: "GET", ok: true, status: 200, json: { something: "else" }, error: "" }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Catalog("https://addon.example.com", "movie", "top")

    Harness_Ok(not result.ok, "catalog rejected")
    Harness_Equal(result.error, "catalog response missing metas", "error names the missing field")
end sub

sub Test_Catalog_NoAddress()
    Harness_Suite("CatalogStore refuses calls without an address")
    store = CatalogStore(ScriptedTransport([]))
    result = store.Catalog("", "movie", "top")

    Harness_Ok(not result.ok, "catalog rejected")
    Harness_Equal(result.error, "no addon address", "error names the missing address")
end sub

sub Test_Catalog_AcceptsGatewayWrappedJson()
    Harness_Suite("CatalogStore accepts a gateway-status response carrying JSON metas")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/catalog/movie/top/search=matrix.json"
            ok: false
            status: 504
            json: { metas: [ { id: "tt0133093", type: "movie", name: "The Matrix" } ] }
            error: "HTTP 504"
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Search(address, "movie", "matrix")

    Harness_Ok(result.ok, "504-wrapped metas accepted")
    Harness_Equal(result.metas.Count(), 1, "gateway meta returned")
end sub

sub Test_Catalog_RejectsGatewayHtml()
    Harness_Suite("CatalogStore rejects a gateway response with an unparseable body")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/catalog/movie/top/search=matrix.json"
            ok: false
            status: 504
            body: "<!DOCTYPE html><html><body>error code: 504</body></html>"
            error: "HTTP 504"
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Search(address, "movie", "matrix")

    Harness_Ok(not result.ok, "gateway HTML rejected")
end sub

sub Test_Catalog_RejectsNonGatewayWithMetas()
    Harness_Suite("CatalogStore rejects a non-gateway error even with JSON metas")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/catalog/movie/top/search=matrix.json"
            ok: false
            status: 404
            json: { metas: [ { id: "tt0133093", type: "movie", name: "The Matrix" } ] }
            error: "HTTP 404"
        }
    ]
    store = CatalogStore(ScriptedTransport(script))
    result = store.Search(address, "movie", "matrix")

    Harness_Ok(not result.ok, "404 with metas still rejected")
end sub