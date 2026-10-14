sub Main()
    m.cinemaAssertions = 0
    m.cinemaRankCalls = 0
    direct4k = { name: "2160p HEVC DDP 5.1 HDR10", url: "https://example.com/movie.mkv?token=sample" }
    unsupported = { name: "2160p HEVC", infoHash: "sample" }
    hd = { name: "1080p H264", url: "https://example.com/hd.mp4" }
    unknown = { name: "Direct stream", url: "https://example.com/stream" }
    dv = { name: "4K DV TrueHD", url: "https://example.com/dv.mkv" }
    plain = { name: "4K HEVC", url: "http://example.com/movie.mkv" }
    list = [unsupported, hd, dv, unknown, direct4k, plain]
    selected = CinemaChooseStreams(list, true)
    Assert(selected.Count() = 2, "4K filter selects only declared 4K direct HTTPS")
    Assert(selected[0].name = direct4k.name, "HEVC DD+ HDR10 preferred to DV TrueHD")
    Assert(selected[1].name = dv.name, "Alternative labelled source stays available with warning")
    allStreams = CinemaChooseStreams(list, false)
    Assert(allStreams.Count() = 4, "All-qualities mode includes unknown and HD but no raw torrent")
    Assert(allStreams[0].name = direct4k.name, "4K remains first in all-qualities mode")
    Assert(list[0].infoHash = "sample", "Selection does not modify provider array")
    Assert(not CinemaIs4KLabel({ name: "Movie 4kids 2160abc" }), "Quality detection uses token boundaries")
    Assert(CinemaIs4KLabel({ behaviorHints: { filename: "Movie.2160p.x265.mkv" } }), "Filename-only resolution hints work")
    Assert(not CinemaIsHttpsStream({ url: "https:///broken" }), "Missing HTTPS host rejected")
    Assert(not CinemaIsHttpsStream({ url: "https://user:password@example.com/file" }), "URL userinfo rejected")
    Assert(not CinemaIsHttpsStream({ url: "https://example.com/file extra" }), "Unescaped whitespace rejected")
    Assert(not CinemaIsHttpsStream({ externalUrl: "https://example.com/" }), "External web pages are not native streams")
    Assert(CinemaSourceNotice(dv).InStr("fallback not confirmed") >= 0, "DV-only caveat is explicit")
    Assert(CinemaSourceNotice({ name: "4K TrueHD HDR10" }).InStr("TrueHD unsupported") >= 0, "TrueHD warning is explicit")
    Assert(CinemaSourceNotice(direct4k).InStr("source label") >= 0, "Source quality not called decoded quality")
    tied = CinemaChooseStreams([{name:"4K first",url:"https://example.com/1"}, {name:"4K second",url:"https://example.com/2"}], true)
    Assert(tied[0].name = "4K first" and tied[1].name = "4K second", "Ranking is stable for equal quality")
    Assert(CinemaChooseStreams([invalid, 42, "wrong", {url:"https://example.com/file",name:42,behaviorHints:"wrong"}], false).Count() = 1, "Malformed provider records cannot crash selection")
    Assert(CinemaChooseStreams("wrong", true).Count() = 0, "Non-array stream responses safely empty")
    Assert(CinemaChooseStreams([hd, dv], false)[0].name = dv.name, "All-qualities mode keeps even cautioned 4K ahead of HD")
    Assert(CinemaQualityLabel(direct4k) = "2160p / 4K source label", "4K badge is a label, not a decoding claim")
    Assert(CinemaQualityLabel(hd) = "1080p source label", "HD quality remains explicit")
    Assert(CinemaQualityLabel({name:"384 kbps audio"}) = "Resolution not supplied", "Audio bitrate cannot create a 4K badge")
    cached = {name:"[TB+] Torrentio" + Chr(10) + "4k",url:"https://torrentio.strem.fun/resolve/torbox/PRIVATE_PLACEHOLDER/movie.mkv",behaviorHints:{filename:"Movie.2160p.HEVC.DDP5.1.mkv"}}
    download = {name:"[TB download] Torrentio" + Chr(10) + "4k",url:cached.url}
    status = {name:"Torrentio" + Chr(10) + "TB error",title:"Invalid TorBox ApiKey/Token!",url:"https://torrentio.strem.fun/videos/failed_access_v3.mp4"}
    ready = CinemaChooseStreams([download,hd,cached,status],false)
    Assert(ready.Count() = 2, "Torrentio protocol fixture drops download placeholders and error clips")
    Assert(ready[0].name = cached.name, "Cached 4K survives ahead of HD")
    Assert(CinemaSourceBlockReason(status) = "provider-status", "Provider error entry classified separately")
    Assert(CinemaSourceBlockReason(download) = "uncached", "TorBox download placeholder is not ready playback")
    Assert(CinemaSourceBlockReason({name:"[RD download] Torrentio 2160p",url:cached.url}) = "uncached", "RD uses the same recognized placeholder protocol")
    Assert(CinemaSourceBlockReason({name:"Download Movie 4K",url:hd.url}) = "", "Ordinary movie wording is not a cache flag")
    Assert(CinemaSourceBlockReason({name:"TB Error Movie",url:hd.url}) = "", "Error word on unrelated source is not a provider status")
    Assert(CinemaSourceBlockReason({url:"https://other.example/videos/failed_access_v3.mp4"}) = "", "Known status paths require the recognized provider host")
    Assert(CinemaSourceBlockReason({url:"https://torrentio.strem.fun/videos/downloading_v3.mp4?key=PRIVATE#ignored"}) = "provider-status", "Status path ignores private query and fragment")
    Assert(CinemaSourceBlockReason({url:"https://torrentio.strem.fun/videos/failed_opening_v3.mp4"}) = "provider-status", "Known opening failure clip is not a film")
    Assert(CinemaSourceBlockReason({name:42,url:42}) = "", "Malformed fields cannot crash classification")
    skipped = CinemaSkippedSources([cached,download,status])
    Assert(skipped.uncached = 1 and skipped.status = 1, "Counts retain a readable explanation for skipped candidates")
    Assert(CinemaChooseStreams([download,cached,status],true).Count() = 1, "4K-only keeps ready cached source without status videos")
    Assert(CinemaSourceBlockReason({name:"4K HEVC",url:hd.url,behaviorHints:{notWebReady:true}}) = "", "notWebReady is not confused with an uncached torrent")
    Assert(CinemaSourceBlockReason({url:"https://torrentio.elfhosted.com/videos/failed_unavailable_v1.mp4"}) = "provider-status", "Known Torrentio hosted status path is recognized")
    large = []
    for i = 0 to 1023
        name = "1080p H264"
        if i mod 4 = 1 then name = "4K HEVC DDP HDR10"
        if i mod 4 = 2 then name = "4K DV TrueHD"
        if i mod 4 = 3 then name = "1080p HEVC DDP"
        large.Push({name:name,url:"https://example.com/" + i.ToStr(),originalIndex:i})
    end for
    m.cinemaRankCalls = 0
    readyLarge = CinemaChooseStreams(large, false)
    Assert(readyLarge.Count() = 1024, "Large provider batch retains every ready stream")
    Assert(m.cinemaRankCalls = 1024, "Large batch scores each candidate exactly once instead of once per comparison")
    Assert(readyLarge[0].originalIndex = 1 and readyLarge[1].originalIndex = 5, "Native descending sort preserves source order for tied quality hints")
    Assert(readyLarge[1023].originalIndex = 1020, "Lowest ranked sources retain stable order too")
    Assert(large[0].originalIndex = 0 and large[1023].originalIndex = 1023, "Ranking does not reorder provider input")
    m.cinemaRankCalls = 0
    onlyLarge4K = CinemaFilterReadyStreams(readyLarge, true)
    Assert(onlyLarge4K.Count() = 512, "Cached list can switch to 4K without losing sources")
    Assert(m.cinemaRankCalls = 0, "Quality toggle never re-ranks cached streams")
    Assert(onlyLarge4K[0].originalIndex = 1 and onlyLarge4K[256].originalIndex = 2, "4K toggle preserves the previously established quality order")
    Assert(CinemaCountReadyStreams([download,cached,status,hd,unsupported]) = 2, "Status counts only ready HTTPS sources")
    Assert(m.cinemaRankCalls = 0, "Status counting never invokes source ranking")
    aac = {name:"4K HEVC AAC 2.0 HDR10",url:hd.url}
    aacSurround = {name:"4K HEVC AAC 5.1 HDR10",url:hd.url}
    dolby = {name:"4K HEVC AC3 5.1 HDR10",url:hd.url}
    projector = CinemaChooseStreams([direct4k,dolby,aacSurround,aac],false,"projector")
    Assert(projector[0].name = aac.name, "Projector preset prefers AAC stereo among 4K sources")
    Assert(projector[1].name = aacSurround.name, "AAC with unspecified downmix follows stereo before Dolby")
    surround = CinemaChooseStreams([aac,dolby,direct4k],false,"surround")
    Assert(surround[0].name = direct4k.name, "AX700 preset prefers DD+ among 4K sources")
    Assert(surround[1].name = dolby.name, "AX700 preset prefers AC3 over AAC")
    Assert(CinemaChooseStreams([hd,aac],false,"projector")[0].name = aac.name, "Projector preset keeps compatible 4K ahead of 1080p")
    Assert(projector.Count() = 2, "Projector list excludes labelled Dolby-only candidates")
    Assert(CinemaChooseStreams([dolby,direct4k],true,"projector").Count() = 0, "4K-only cannot re-enable incompatible projector audio")
    Assert(CinemaChooseStreams([{name:"2160p DTS-HD MA",url:hd.url}],false,"projector").Count() = 0, "DTS-only labels are excluded for projector speakers")
    Assert(CinemaChooseStreams([{name:"4K DDP5.1 AAC 2.0",url:hd.url}],true,"projector").Count() = 1, "Known AAC alternate keeps a multitrack candidate available")
    Assert(CinemaSourceNotice(direct4k,"projector").InStr("prefer AAC stereo") >= 0, "Projector source notice never promises Dolby conversion")
    hdStereo = {name:"1080p H264 AAC2.0",url:"https://example.com/stereo.mkv"}
    fourUnknown = {name:"2160p HEVC",url:"https://example.com/unknown.mkv"}
    automaticAudio = CinemaChooseStreams([aacSurround,fourUnknown,hdStereo,aac],false,"projector",false)
    Assert(automaticAudio[0].name = aac.name, "4K stereo AAC is first when available")
    Assert(automaticAudio[1].name = aacSurround.name, "4K first does not silently prioritize stereo HD over remaining UHD candidates")
    Assert(automaticAudio.Count() = 4, "Audio hints rank candidates without deleting unknown layouts")
    rememberedOrder = CinemaPreferUhdFirst([hdStereo,aac,fourUnknown])
    Assert(rememberedOrder[0].name = aac.name, "remembered HD cannot override UHD-first automatic selection")
    Assert(rememberedOrder[2].name = hdStereo.name, "remembered HD remains available as a fallback")
    Assert(CinemaChooseStreams([hdStereo,fourUnknown],true,"projector",false)[0].name = fourUnknown.name, "Explicit 4K-only never silently selects stereo HD")
    Assert(CinemaStreamRank(hdStereo,invalid,"projector") > CinemaStreamRank({name:"1080p AAC5.1"},invalid,"projector"), "Attached AAC2.0 label is preferred within the HD quality tier")
    Assert(CinemaStreamRank({name:"1080p AAC5.1 Movie 2.0"},invalid,"projector") < CinemaStreamRank(fourUnknown,invalid,"projector"), "Unrelated 2.0 title cannot turn AAC5.1 into a stereo hint")
    Assert(CinemaChooseStreams([hdStereo,direct4k],false,"surround")[0].name = direct4k.name, "Future surround mode retains 4K Dolby priority")
    labelledSix = CinemaCleanSourceLines({name:"Film.2.0.2160p.HEVC.AAC5.1"},"projector")
    Assert(labelledSix[0].InStr("multichannel hint") >= 0 and labelledSix[0].InStr("1-2 channel") < 0, "Movie title 2.0 cannot mislabel AAC5.1 as stereo")
    labelledStereo = CinemaCleanSourceLines({name:"Film.5.1.2160p.AAC2.0"},"projector")
    Assert(labelledStereo[0].InStr("1-2 channel hint") >= 0 and labelledStereo[0].InStr("multichannel") < 0, "Unrelated title 5.1 cannot change an AAC2.0 hint")
    mixedHints = CinemaCleanSourceLines({name:"2160p AAC2.0 AAC5.1"},"projector")
    Assert(mixedHints[0].InStr("mixed-layout hints") >= 0, "Conflicting AAC layouts remain explicit hints")
    bothCodecs = CinemaCleanSourceLines({name:"2160p AAC2.0 DD+ 5.1"},"projector")
    Assert(bothCodecs[0].InStr("AAC") >= 0 and bothCodecs[0].InStr("DD+ hint") >= 0, "Multiple codec hints remain readable without discarding the stereo alternative")
    Assert(CinemaChooseStreams([{name:"2160p Dolby Digital DTS",url:hd.url}],false,"projector",false).Count() = 1, "Ready mixed-track candidates survive audio filename uncertainty")
    print "Cinema stream policy: " + m.cinemaAssertions.ToStr() + " assertions passed"
end sub

sub Assert(ok as boolean, label as string)
    m.cinemaAssertions = m.cinemaAssertions + 1
    if not ok
        print "FAIL: " + label
        stop
    end if
end sub
