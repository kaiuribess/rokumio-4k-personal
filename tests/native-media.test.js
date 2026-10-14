const fs=require('fs'),path=require('path'),{spawnSync}=require('child_process');
function elem(id,b){
  if(b.length>8191)throw Error('fixture bound');
  const size=b.length<127?Buffer.from([128+b.length]):Buffer.from([0x40|(b.length>>8),b.length&255]);
  return Buffer.concat([Buffer.from(id,'hex'),size,b]);
}
function u(id,n){let hex=n.toString(16);if(hex.length%2)hex='0'+hex;return elem(id,Buffer.from(hex,'hex'));}
function tr(lang,codec,ch,extra=[]){return elem('ae',Buffer.concat([u('83',2),elem('86',Buffer.from(codec)),...(lang===null?[]:[elem('22b59c',Buffer.from(lang))]),elem('e1',ch===null?Buffer.alloc(0):u('9f',ch)),...extra]));}
function videoTrack(width,height,extra=[]){return elem('ae',Buffer.concat([u('83',1),elem('86',Buffer.from('V_MPEGH/ISO/HEVC')),elem('e0',Buffer.concat([u('b0',width),u('ba',height)])),...extra]));}
function doc(entries){return Buffer.concat([elem('1a45dfa3',Buffer.alloc(0)),Buffer.from('18538067ff','hex'),elem('1654ae6b',Buffer.concat(entries))]);}
const fixtures={english:doc([tr('eng','A_AAC',2)]),foreign:doc([tr('por','A_AAC',2)]),six:doc([tr('eng','A_AAC',6)]),dolby:doc([tr('eng','A_EAC3',6)]),ietf:doc([tr('por','A_AAC',2,[elem('22b59d',Buffer.from('en-US'))])])};
const safetyFixtures={
  mixed:doc([tr('eng','A_AAC',6),tr('eng','A_AAC',2)]),
  foreignMixed:doc([tr('eng','A_AAC',2),tr('ita','A_AAC',2)]),
  stereoPair:doc([tr('eng','A_AAC',2),tr('en-GB','A_AAC',1)]),
  disabledForeign:doc([tr('eng','A_AAC',2),tr('ita','A_AAC',6,[u('b9',0)])]),
  noLanguage:doc([tr(null,'A_AAC',2)]),
  emptyLanguage:doc([tr('','A_AAC',2)]),
  unknownLanguage:doc([tr('und','A_AAC',2)]),
  defaultChannels:doc([tr('eng','A_AAC',null)]),
  descriptive:doc([tr('eng','A_AAC',2,[u('55ac',1)])]),
  commentary:doc([tr('eng','A_AAC',2,[u('55af',1)])]),
  unicodeCommentary:doc([tr('eng','A_AAC',2,[elem('536e',Buffer.from('English commentary by José'))])]),
  unicodeDialogue:doc([tr('eng','A_AAC',2,[elem('536e',Buffer.from('English — cinéma 🎬'))])]),
  unknownName:doc([tr('eng','A_AAC',2,[elem('536e',Buffer.from([0xff]))])]),
  longName:doc([tr('eng','A_AAC',2,[elem('536e',Buffer.from('English commentary '+ 'x'.repeat(256)))])]),
  badFlag:doc([tr('eng','A_AAC',2,[u('55ac',2)])]),
  badEnabled:doc([tr('eng','A_AAC',2,[u('b9',2)])]),
  badChannels:doc([tr('eng','A_AAC',0)]),
  badCodec:doc([tr('eng','',2)]),
  missingAudio:doc([elem('ae',Buffer.concat([u('83',2),elem('86',Buffer.from('A_AAC')),elem('22b59c',Buffer.from('eng'))]))]),
  duplicateLanguage:doc([tr('eng','A_AAC',2,[elem('22b59c',Buffer.from('por'))])]),
  legacyLc:doc([tr('eng','A_AAC/MPEG4/LC',2)]),
  legacyMain:doc([tr('eng','A_AAC/MPEG4/MAIN',2)]),
  mp3:doc([tr('eng','A_MPEG/L3',2)]),
  mp3Mixed:doc([tr('eng','A_MPEG/L3',2),tr('ita','A_MPEG/L3',2)]),
  mp3NoLanguage:doc([tr(null,'A_MPEG/L3',2)]),
  mp3Commentary:doc([tr('eng','A_MPEG/L3',2,[u('55af',1)])]),
  mp3Six:doc([tr('eng','A_MPEG/L3',6)]),
  pcm:doc([tr('eng','A_PCM/INT/LIT',2)]),
  unknownCodec:doc([tr('eng','A_UNRECOGNIZED',2)]),
  undUpperAac:doc([tr('UND','A_AAC',2)]),
  undPaddedAac:doc([tr(' und ','A_AAC',1)]),
  mulMixedMp3:doc([tr('Mul','A_MPEG/L3',2)]),
  mulPaddedMp3:doc([tr(' MUL ','A_MPEG/L3',1)]),
  hyphenDescriptionAac:doc([tr('eng','A_AAC',2,[elem('536e',Buffer.from('English audio-description'))])]),
  underscoreDescriptionMp3:doc([tr('eng','A_MPEG/L3',2,[elem('536e',Buffer.from('English descriptive_audio'))])]),
  abbreviationAdAac:doc([tr('eng','A_AAC',1,[elem('536e',Buffer.from('English - AD'))])]),
  abbreviationDvsMp3:doc([tr('eng','A_MPEG/L3',2,[elem('536e',Buffer.from('English [DVS]'))])]),
  ordinaryWordAac:doc([tr('eng','A_AAC',2,[elem('536e',Buffer.from('English - Badlands radio studio'))])]),
  ordinaryWordMp3:doc([tr('eng','A_MPEG/L3',1,[elem('536e',Buffer.from('English - additional dialogue'))])])
};
let code=fs.readFileSync('tests/harness.brs','utf8')+'\n'+fs.readFileSync('source/util/EnglishAudio.brs','utf8')+'\n'+fs.readFileSync('source/util/NativeMedia.brs','utf8')+'\nHarness_Suite("Bounded native MKV audio inspection")\n';
for(let [n,b]of Object.entries(fixtures))code+=`${n} = NativeMedia_Parse([${[...b].join(',')}])\nHarness_Ok(${n}.complete,"${n} complete Tracks parsed")\n`;
code+=`Harness_Ok(not NativeMedia_HasSize({}),"Pending native file with empty stat is safe")
Harness_Ok(not NativeMedia_HasSize(invalid),"Missing native file is safe")
Harness_Ok(NativeMedia_HasSize({size:1048576}),"Completed bounded native file has a valid size")
Harness_Ok(NativeMedia_AudioPolicy(english,"projector").compatible,"English AAC stereo allowed")
Harness_Ok(not NativeMedia_AudioPolicy(foreign,"projector").compatible,"Foreign AAC rejected")
Harness_Ok(not NativeMedia_AudioPolicy(six,"projector").compatible,"Six-channel AAC not assumed decodable on Stick")
Harness_Ok(not NativeMedia_AudioPolicy(dolby,"projector").compatible,"Dolby cannot substitute for projector stereo")
Harness_Ok(NativeMedia_AudioPolicy(dolby,"surround").compatible,"English DD+ candidate permitted with speakers")
Harness_Ok(NativeMedia_AudioPolicy(ietf,"projector").compatible,"BCP47 language overrides legacy language")
Harness_Ok(NativeMedia_AudioPolicy(invalid,"projector").compatible,"Uninspected format relies on native checks")
`;
for(let [n,b]of Object.entries(safetyFixtures))code+=`${n} = NativeMedia_Parse([${[...b].join(',')}])\n`;
code+=`
Harness_Suite("Actual eligible AAC is distinct from guaranteed metadata fallback")
Harness_Ok(NativeMedia_AudioPolicy(english,"projector").englishOnlyAac,"explicit English AAC stereo permits empty-native-track fallback")
Harness_Ok(NativeMedia_AudioPolicy(ietf,"projector").englishOnlyAac,"declared English BCP47 takes precedence in fallback")
Harness_Ok(NativeMedia_AudioPolicy(mixed,"projector").compatible,"a mixed file still contains a potentially playable AAC stereo track")
Harness_Ok(NativeMedia_AudioPolicy(mixed,"projector").hasStereoEnglishAac,"mixed AAC file exposes its eligible stereo alternative")
Harness_Ok(not NativeMedia_AudioPolicy(mixed,"projector").englishOnlyAac,"AAC six-channel alternative prevents claiming selected stereo from codec alone")
Harness_Ok(not NativeMedia_AudioPolicy(foreignMixed,"projector").englishOnlyAac,"foreign AAC alternative prevents claiming English from codec alone")
Harness_Ok(NativeMedia_AudioPolicy(stereoPair,"projector").englishOnlyAac,"all selectable explicitly English AAC tracks are safe mono/stereo")
Harness_Ok(NativeMedia_AudioPolicy(disabledForeign,"projector").englishOnlyAac,"disabled foreign AAC track cannot be selected and does not contaminate fallback")
Harness_Equal(noLanguage.tracks[0].language,"eng","Matroska default language remains represented as a spec default")
Harness_Ok(noLanguage.tracks[0].languageDeclared = false,"absent language is distinguished from explicitly tagged English")
Harness_Ok(NativeMedia_AudioPolicy(noLanguage,"projector").compatible,"default-language file may still be verified through actual native track metadata")
Harness_Ok(not NativeMedia_AudioPolicy(noLanguage,"projector").englishOnlyAac,"absent language cannot independently authorize English audio")
Harness_Ok(not NativeMedia_AudioPolicy(noLanguage,"projector").hasStereoEnglishAac,"default language cannot force AAC and hide another explicitly English codec")
Harness_Ok(NativeMedia_AudioPolicy(emptyLanguage,"projector").compatible,"empty language defers to native metadata instead of a permanent exclusion")
Harness_Ok(not NativeMedia_AudioPolicy(emptyLanguage,"projector").known,"empty language does not become authoritative file audio proof")
Harness_Ok(not NativeMedia_AudioPolicy(emptyLanguage,"projector").englishOnlyAac,"empty declared language cannot authorize fallback")
Harness_Ok(not NativeMedia_AudioPolicy(unknownLanguage,"projector").known,"undetermined language is uncertain rather than falsely foreign")
Harness_Equal(defaultChannels.tracks[0].channels,1,"absent Matroska Channels retains the specified mono default")
Harness_Ok(defaultChannels.tracks[0].channelsDeclared = false,"channel default stays distinguishable from explicit channel count")

Harness_Suite("Descriptive and Unicode commentary metadata cannot disappear into dialogue")
Harness_Ok(descriptive.tracks[0].HasAccessibilityDescription,"FlagVisualImpaired is mapped to descriptive audio metadata")
Harness_Ok(not NativeMedia_AudioPolicy(descriptive,"projector").compatible,"English AAC audio description is not ordinary movie dialogue")
Harness_Ok(not NativeMedia_AudioPolicy(commentary,"projector").englishOnlyAac,"FlagCommentary prevents empty-track dialogue fallback")
Harness_Ok(unicodeCommentary.tracks[0].NameKnown,"valid Unicode track names are decoded rather than discarded")
Harness_Ok(unicodeCommentary.tracks[0].Name.InStr("commentary") >= 0,"commentary text before a Unicode character remains available to the guard")
Harness_Ok(not NativeMedia_AudioPolicy(unicodeCommentary,"projector").compatible,"Unicode commentary name is excluded")
Harness_Ok(unicodeDialogue.tracks[0].NameKnown,"valid multibyte and four-byte Unicode names are supported")
Harness_Ok(NativeMedia_AudioPolicy(unicodeDialogue,"projector").englishOnlyAac,"ordinary valid Unicode track name retains safe metadata fallback")
Harness_Ok(unknownName.tracks[0].NameKnown = false,"malformed UTF8 remains an explicit unknown-name marker")
Harness_Ok(NativeMedia_AudioPolicy(unknownName,"projector").compatible,"unreadable name leaves the native selected-track path usable")
Harness_Ok(not NativeMedia_AudioPolicy(unknownName,"projector").known,"unreadable name cannot produce permanent audio incompatibility proof")
Harness_Ok(not NativeMedia_AudioPolicy(unknownName,"projector").englishOnlyAac,"unreadable name cannot authorize empty-track dialogue fallback")
Harness_Ok(longName.tracks[0].NameKnown = false,"name decoding has a strict 256-byte bound")
Harness_Ok(not NativeMedia_AudioPolicy(longName,"projector").englishOnlyAac,"overlong present name does not become a blank dialogue name")
Harness_Ok(EnglishAudio_IsDialogue({Language:"eng",Track:"native",Name:"English"}),"native track structs without header-only marker retain their normal path")
Harness_Ok(not EnglishAudio_IsDialogue({NameKnown:false,Name:""}),"explicit uncertain header name is never ordinary dialogue proof")
Harness_Ok(not EnglishAudio_IsEnglish("en-"),"malformed empty English subtag is not an English language claim")
Harness_Ok(EnglishAudio_IsEnglish("en-Latn-US"),"valid English language-script-region tags remain accepted")

Harness_Suite("Malformed and uncertain metadata cannot become cached file proof")
Harness_Ok(not badFlag.complete,"out-of-range accessibility flag invalidates header proof")
Harness_Ok(not badEnabled.complete,"out-of-range enabled flag invalidates header proof")
Harness_Ok(not badChannels.complete,"zero channel count invalidates header proof")
Harness_Ok(not badCodec.complete,"empty mandatory codec ID invalidates header proof")
Harness_Ok(not missingAudio.complete,"missing mandatory Audio element invalidates header proof")
Harness_Ok(not duplicateLanguage.complete,"duplicate language field cannot contradict English fallback")
Harness_Ok(NativeMedia_AudioPolicy(legacyLc,"projector").englishOnlyAac,"legacy AAC LC mapping is recognized explicitly")
Harness_Ok(NativeMedia_AudioPolicy(legacyMain,"projector").compatible,"unverified AAC Main profile defers to native decoder")
Harness_Ok(not NativeMedia_AudioPolicy(legacyMain,"projector").known,"unverified profile is not a permanent negative file outcome")
Harness_Ok(not NativeMedia_AudioPolicy(legacyMain,"projector").englishOnlyAac,"AAC family prefix alone cannot authorize unknown profile")
Harness_Ok(NativeMedia_AudioPolicy(mp3,"projector").compatible,"documented MKV MP3 stereo candidate is not falsely excluded")
Harness_Ok(not NativeMedia_AudioPolicy(mp3,"projector").englishOnlyAac,"MP3 candidate cannot use an AAC-only metadata shortcut")
Harness_Ok(NativeMedia_AudioPolicy(mp3,"projector").englishOnlyMp3,"all selectable explicitly English MP3 stereo can provide its own codec-specific fallback")
Harness_Ok(not NativeMedia_AudioPolicy(mp3Mixed,"projector").englishOnlyMp3,"foreign MP3 alternative prevents a language claim from decoder codec alone")
Harness_Ok(not NativeMedia_AudioPolicy(mp3NoLanguage,"projector").englishOnlyMp3,"implicit default language cannot authorize MP3 fallback")
Harness_Ok(not NativeMedia_AudioPolicy(mp3Commentary,"projector").englishOnlyMp3,"MP3 commentary cannot authorize dialogue fallback")
Harness_Ok(not NativeMedia_AudioPolicy(mp3Six,"projector").compatible,"MP3 family does not bypass the mono/stereo channel condition")
Harness_Ok(not NativeMedia_AudioPolicy(mp3Six,"projector").englishOnlyMp3,"multichannel MP3 cannot claim stereo metadata fallback")
Harness_Ok(NativeMedia_AudioPolicy(pcm,"projector").compatible,"PCM without validated sample configuration is deferred rather than wrongly excluded")
Harness_Ok(not NativeMedia_AudioPolicy(pcm,"projector").known,"uncertain PCM configuration does not claim hardware support")
Harness_Ok(not NativeMedia_AudioPolicy(pcm,"projector").englishOnlyAac,"PCM never borrows AAC metadata fallback")
Harness_Ok(not NativeMedia_AudioPolicy(pcm,"projector").englishOnlyMp3,"PCM never borrows MP3 metadata fallback")
Harness_Ok(not NativeMedia_AudioPolicy(unknownCodec,"projector").known,"unknown codec remains a native-check candidate without permanent proof")

Harness_Suite("Unknown language normalization permits native checks without approving English")
for each unknown in [undUpperAac,undPaddedAac,mulMixedMp3,mulPaddedMp3]
    policy = NativeMedia_AudioPolicy(unknown,"projector")
    Harness_Ok(not policy.known and policy.compatible,"mixed-case and padded unknown language remains a native-check candidate")
    Harness_Ok(not policy.englishOnlyAac and not policy.englishOnlyMp3 and not policy.hasStereoEnglishAac,"unknown language never authorizes English fallback or a codec preference")
end for
Harness_Ok(not NativeMedia_AudioPolicy(foreign,"projector").compatible,"normalizing uncertainty never turns a known foreign track into English")

Harness_Suite("Explicit descriptive labels cannot pass AAC or MP3 dialogue fallback")
for each descriptiveTrack in [hyphenDescriptionAac,underscoreDescriptionMp3,abbreviationAdAac,abbreviationDvsMp3]
    policy = NativeMedia_AudioPolicy(descriptiveTrack,"projector")
    Harness_Ok(not policy.compatible,"explicit audio-description labels cannot substitute for ordinary English dialogue")
    Harness_Ok(not policy.englishOnlyAac and not policy.englishOnlyMp3,"descriptive labels cannot authorize either codec fallback")
end for
Harness_Ok(NativeMedia_AudioPolicy(ordinaryWordAac,"projector").englishOnlyAac,"ordinary words containing AD retain AAC dialogue fallback")
Harness_Ok(NativeMedia_AudioPolicy(ordinaryWordMp3,"projector").englishOnlyMp3,"ordinary words containing AD retain MP3 dialogue fallback")
for each label in ["English audio-description","English descriptive audio","English - AD","English [DVS]","English AudioDescription"]
    Harness_Ok(not EnglishAudio_IsDialogue({Language:"eng",Track:"native",Name:label}),"explicit descriptive native track name is rejected")
end for
for each label in ["English AAC 2.0","English - Badlands radio studio","English - additional dialogue","English - advisor"]
    Harness_Ok(EnglishAudio_IsDialogue({Language:"eng",Track:"native",Name:label}),"ordinary native dialogue name is preserved")
end for

Harness_Suite("Native projector codec evidence is limited to actual audio aliases")
for each nativeCodec in ["aac","aac_adif","aac_adts","aac_latm"," AAC_ADTS ","mp3"," PCM "]
    Harness_Ok(EnglishAudio_ProjectorCodec(nativeCodec),"documented projector codec is recognized after trim and case normalization")
    Harness_Ok(EnglishAudio_Check([{Language:"eng",Track:"native",Name:"English"}],"native",nativeCodec,"projector").verified,"actual selected English track can use a recognized native codec")
end for
for each inventedCodec in ["aac_unknown","aac_magic","aac_","aac-latm","aac_hev2",""]
    Harness_Ok(not EnglishAudio_ProjectorCodec(inventedCodec),"invented AAC-family text cannot supply a decoder")
    Harness_Ok(not EnglishAudio_Check([{Language:"eng",Track:"native",Name:"English"}],"native",inventedCodec,"projector").verified,"invented codec cannot authorize native English playback")
end for
`;
const qualityFixtures={
  inspectedHd:doc([videoTrack(1920,1080),tr('eng','A_AAC',2)]),
  inspectedHd720:doc([videoTrack(1280,720),tr('eng','A_AAC',2)]),
  inspectedUhd:doc([videoTrack(3840,2160),tr('eng','A_AAC',2)]),
  inspectedCroppedUhd:doc([videoTrack(3840,1600),tr('eng','A_AAC',2)]),
  inspectedMixedVideo:doc([videoTrack(1920,1080),videoTrack(3840,1600),tr('eng','A_AAC',2)]),
  inspectedDisabledUhd:doc([videoTrack(1920,1080),videoTrack(3840,2160,[u('b9',0)]),tr('eng','A_AAC',2)])
};
for(const [name,bytes] of Object.entries(qualityFixtures))code+=`${name} = NativeMedia_Parse([${[...bytes].join(',')}])\n`;
code+=`
Harness_Suite("Explicit 4K-only excludes measured lower resolution without certifying unknown files")
Harness_Ok(NativeMedia_KnownBelowUhd(inspectedHd),"actual 1920x1080 tracks are below UHD regardless of the provider label")
Harness_Ok(NativeMedia_KnownBelowUhd(inspectedHd720),"actual 1280x720 tracks are below UHD")
Harness_Ok(NativeMedia_AudioPolicy(inspectedHd,"projector").compatible,"resolution preference does not make a playable HD file intrinsically incompatible")
Harness_Ok(not NativeMedia_KnownBelowUhd(inspectedUhd),"measured UHD is not rejected as lower resolution")
Harness_Ok(not NativeMedia_KnownBelowUhd(inspectedCroppedUhd),"3840x1600 cinema crop preserves its UHD width")
Harness_Ok(not NativeMedia_KnownBelowUhd(inspectedMixedVideo),"a secondary HD track cannot disqualify an enabled UHD track")
Harness_Ok(NativeMedia_KnownBelowUhd(inspectedDisabledUhd),"disabled UHD track cannot authorize a file whose enabled video is HD")
Harness_Ok(not NativeMedia_KnownBelowUhd(english),"audio-only inspection is not video resolution proof")
Harness_Ok(not NativeMedia_KnownBelowUhd(invalid),"uninspected media remains unknown")
Harness_Ok(not NativeMedia_KnownBelowUhd({complete:false,tracks:[{kind:1,enabled:true,width:1920,height:1080}]}),"incomplete inspection cannot reject on partial dimensions")
Harness_Ok(not NativeMedia_KnownBelowUhd({complete:true,tracks:[{kind:1,enabled:true,width:"1920",height:1080}]}),"string dimensions cannot establish encoded resolution")
Harness_Ok(not NativeMedia_KnownBelowUhd({complete:true,tracks:[{kind:1,enabled:true,width:1920,height:0}]}),"missing dimensions remain unknown")
Harness_Ok(not NativeMedia_KnownBelowUhd({complete:true,tracks:[{kind:1,enabled:true,width:1920,height:1080},{kind:1,enabled:true}]}),"an additional unmeasured enabled video prevents a negative resolution claim")
`;
for(const [label,bytes] of Object.entries({overlong:[0xc0,0xaf],surrogate:[0xed,0xa0,0x80],tooHigh:[0xf4,0x90,0x80,0x80],truncated:[0xe2,0x82],control:[0],continuation:[0x80]}))
  code+=`Harness_Ok(not NativeMedia_Name([${bytes.join(',')}],{start:0,finish:${bytes.length}}).known,"${label} UTF8 is rejected before native string conversion")\n`;
for(let n=0;n<fixtures.english.length;n++)code+=`Harness_Ok(not NativeMedia_Parse([${[...fixtures.english.subarray(0,n)].join(',')}]).complete,"truncation ${n} cannot prove audio")\n`;
code+='Harness_Finish()\n';
const dir='out-test/native-media';fs.mkdirSync(dir,{recursive:true});fs.writeFileSync(dir+'/native.brs',code);let r=spawnSync(process.execPath,['node_modules/@rokucommunity/brs/bin/cli.js','--root',dir,dir+'/native.brs'],{encoding:'utf8'});process.stdout.write(r.stdout||'');process.stderr.write(r.stderr||'');process.exit(r.status===0&&!(r.stderr||'').trim()&&/RESULT: PASS/.test(r.stdout||'')?0:1);
