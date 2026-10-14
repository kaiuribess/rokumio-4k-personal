// Node test for the mock addon server. Boots the server on an ephemeral port
// and asserts every endpoint the stores speak to. Wired into `npm test` after
// the brs suite; same PASS/FAIL convention as the BrightScript harness.
"use strict";

const { createAddonServer } = require("./server");

const server = createAddonServer();
let passed = 0;
let failed = 0;

function request(port, method, path, body) {
    return new Promise((resolve, reject) => {
        const options = {
            host: "127.0.0.1",
            port,
            method,
            path,
            headers: body ? { "Content-Type": "application/json" } : {},
        };
        const req = httpRequest(options, resolve, reject);
        if (body) req.write(JSON.stringify(body));
        req.end();
    });
}

function httpRequest(options, resolve, reject) {
    const http = require("http");
    const req = http.request(options, (res) => {
        let raw = "";
        res.on("data", (chunk) => {
            raw += chunk;
        });
        res.on("end", () => {
            let json = null;
            try {
                json = JSON.parse(raw || "null");
            } catch (err) {
                json = { error: "unparseable body" };
            }
            resolve({ status: res.statusCode, json, raw });
        });
    });
    req.on("error", reject);
    return req;
}

function check(name, condition) {
    if (condition) {
        passed++;
        console.log(`    ok   ${name}`);
    } else {
        failed++;
        console.log(`    FAIL ${name}`);
    }
}

server.listen(0, "127.0.0.1", async () => {
    const port = server.address().port;
    try {
        const health = await request(port, "GET", "/health");
        check("health returns 200 {ok:true}", health.status === 200 && health.json.ok === true);

        const manifest = await request(port, "GET", "/");
        check(
            "manifest returns the addon id",
            manifest.status === 200 && manifest.json.id === "stremio.rokumio.mock"
        );

        const manifestJson = await request(port, "GET", "/manifest.json");
        check(
            "manifest.json alias returns the same manifest",
            manifestJson.status === 200 && manifestJson.json.id === "stremio.rokumio.mock"
        );
        check(
            "manifest advertises the stream resource",
            Array.isArray(manifestJson.json.resources) && manifestJson.json.resources.includes("stream")
        );
        check(
            "manifest advertises the subtitles resource",
            Array.isArray(manifestJson.json.resources) && manifestJson.json.resources.includes("subtitles")
        );

        const catalog = await request(port, "GET", "/catalog/movie/top/skip=0.json");
        check(
            "catalog returns two metas",
            catalog.status === 200 && Array.isArray(catalog.json.metas) && catalog.json.metas.length === 2
        );

        const metaMovie = await request(port, "GET", "/meta/movie/tt0133093.json");
        check(
            "movie meta returns a movie with runtime",
            metaMovie.status === 200 &&
                metaMovie.json.meta.type === "movie" &&
                metaMovie.json.meta.name.includes("tt0133093") &&
                metaMovie.json.meta.runtime === 121 &&
                typeof metaMovie.json.meta.description === "string" &&
                typeof metaMovie.json.meta.imdbRating === "string" &&
                typeof metaMovie.json.meta.releaseInfo === "string" &&
                typeof metaMovie.json.meta.background === "string"
        );

        const metaSeries = await request(port, "GET", "/meta/series/tt1234567.json");
        check(
            "series meta returns episodes with seasons and runtimes",
            metaSeries.status === 200 &&
                Array.isArray(metaSeries.json.meta.videos) &&
                metaSeries.json.meta.videos.length === 3 &&
                metaSeries.json.meta.videos[0].season === 1 &&
                metaSeries.json.meta.videos[0].runtime === 49
        );

        const streams = await request(port, "GET", "/stream/movie/tt0133093.json");
        check(
            "stream returns a torrent + a direct url",
            streams.status === 200 &&
                Array.isArray(streams.json.streams) &&
                streams.json.streams.length === 2 &&
                typeof streams.json.streams[0].infoHash === "string" &&
                streams.json.streams[1].url === "http://127.0.0.1:11470/mock/file.mp4"
        );
        check(
            "torrent stream embeds peers, size and indexer in the title",
            streams.status === 200 &&
                streams.json.streams[0].name === "Mock\n4K" &&
                streams.json.streams[0].title.includes("👤 412") &&
                streams.json.streams[0].title.includes("💾 54.2 GB") &&
                streams.json.streams[0].title.includes("🔗 RARBG")
        );

        const seriesStreams = await request(port, "GET", "/stream/series/tt1234567.json");
        check(
            "series stream is a season pack with file, facts and flags on their own lines",
            seriesStreams.status === 200 &&
                seriesStreams.json.streams.some(
                    (s) =>
                        (s.title || "").split("\n").length === 4 &&
                        s.title.includes("Pilot.mkv") &&
                        s.title.includes("👤 113") &&
                        s.title.includes("🇬🇧 / 🇷🇺 / 🇺🇦")
                )
        );

        const subtitles = await request(port, "GET", "/subtitles/movie/tt0133093.json");
        check(
            "subtitles returns a caption list for the video",
            subtitles.status === 200 &&
                Array.isArray(subtitles.json.subtitles) &&
                subtitles.json.subtitles.length >= 3 &&
                typeof subtitles.json.subtitles[0].url === "string" &&
                typeof subtitles.json.subtitles[0].lang === "string" &&
                typeof subtitles.json.subtitles[0].langName === "string"
        );
        check(
            "caption urls point at reachable srt bodies on the request host",
            Array.isArray(subtitles.json.subtitles) &&
                subtitles.json.subtitles.every(
                    (s) => s.url === `http://127.0.0.1:${port}/subtitles/files/${s.lang}.srt`
                )
        );

        const enSrt = await request(port, "GET", "/subtitles/files/en.srt");
        check(
            "srt endpoint serves a subrip body starting with a cue number",
            enSrt.status === 200 && /^1\r?\n\d{2}:\d{2}:\d{2},\d{3} --> /.test(enSrt.raw || "")
        );
        const deSrt = await request(port, "GET", "/subtitles/files/de.srt");
        check(
            "each advertised language has a distinct srt body",
            deSrt.status === 200 && enSrt.raw !== deSrt.raw && deSrt.raw.includes("Untertitel")
        );
        const unknownSrt = await request(port, "GET", "/subtitles/files/xx.srt");
        check("unknown caption language is 404", unknownSrt.status === 404);

        const missing = await request(port, "GET", "/nope");
        check("unknown path is 404", missing.status === 404);
    } catch (err) {
        console.error(err);
        failed++;
    } finally {
        server.close();
        console.log("");
        console.log(`Assertions passed: ${passed}  failed: ${failed}`);
        if (failed > 0) {
            console.log("RESULT: FAIL");
            process.exit(1);
        }
        console.log("RESULT: PASS");
    }
});