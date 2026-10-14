const fs = require('fs');
const os = require('os');
const path = require('path');
const {spawnSync} = require('child_process');
const root = path.resolve(__dirname, '..');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'rokumio-audio-caps-'));
try {
  const code = fs.readFileSync(path.join(root,'tests/harness.brs'),'utf8') + '\n' +
    fs.readFileSync(path.join(root,'source/util/AudioCapabilities.brs'),'utf8').replace(/CreateObject\("roDeviceInfo"\)/g,'CapsMockDevice()') + `
function CapsMockDevice() as dynamic
    return m.capsDevice
end function
function CapsOutput() as string
    return m.output
end function
function CapsDecode(query as object) as dynamic
    m.calls.Push(query)
    return m.answers[query.codec]
end function
function CapsDecoders() as dynamic
    return m.decoders
end function
Harness_Suite("Reported audio output capabilities")
m.capsDevice = {output:"Stereo",calls:[],answers:{aac:{result:true},mp3:{result:true},pcm:{result:false},ac3:{result:false},eac3:invalid,dts:{result:"unsupported"}},decoders:{AAC:"2:0:0:0:"},GetAudioOutputChannel:CapsOutput,CanDecodeAudio:CapsDecode,GetAudioDecodeInfo:CapsDecoders}
fresh = AudioCapabilities_ReadDevice()
Harness_Ok(fresh.output = "Stereo","Actual reader obtains output from the native boundary")
Harness_Ok(fresh.codecs.aac = true and fresh.codecs.ac3 = false,"Reader preserves native positive and negative boolean results")
Harness_Ok(not fresh.codecs.DoesExist("eac3") and not fresh.codecs.DoesExist("dts"),"Missing or malformed native results stay unknown")
Harness_Ok(m.capsDevice.calls.Count() = 6,"Every read freshly checks all queried audio codecs")
Harness_Ok(fresh.codecs.mp3 = true and fresh.codecs.pcm = false,"MP3 and PCM preserve explicit local decoder responses")
Harness_Ok(m.capsDevice.calls[0].codec = "aac" and m.capsDevice.calls[1].codec = "mp3" and m.capsDevice.calls[2].codec = "pcm","Projector codecs use their individual native query names")
Harness_Ok(not m.capsDevice.calls[0].DoesExist("passthru") and not m.capsDevice.calls[1].DoesExist("passthru") and not m.capsDevice.calls[2].DoesExist("passthru"),"AAC, MP3 and PCM are queried for local decoding")
Harness_Ok(m.capsDevice.calls[3].passthru = 1 and m.capsDevice.calls[4].passthru = 1 and m.capsDevice.calls[5].passthru = 1,"Dolby and DTS query the receiving passthrough device")
m.capsDevice.output = "5.1 surround"
m.capsDevice.answers.eac3 = {result:true}
m.capsDevice.answers.mp3 = invalid
m.capsDevice.answers.pcm = {result:true}
fresh2 = AudioCapabilities_ReadDevice()
Harness_Ok(fresh2.output = "5.1 surround" and fresh2.codecs.eac3 = true,"Changing the connected output does not inherit stale refusal")
Harness_Ok(m.capsDevice.calls.Count() = 12,"A second playback rechecks capabilities")
Harness_Ok(not fresh2.codecs.DoesExist("mp3") and fresh2.codecs.pcm = true,"Missing MP3 response stays unknown while PCM is refreshed")
Harness_Ok(fresh.codecs.mp3 = true and fresh.codecs.pcm = false,"Earlier local decoder results are not modified by a new query")
Harness_Ok(fresh.output = "Stereo" and not fresh.codecs.DoesExist("eac3"),"Previous capability snapshots remain isolated")
m.capsDevice.answers.mp3 = {result:"true"}
m.capsDevice.answers.pcm = {result:0}
fresh3 = AudioCapabilities_ReadDevice()
Harness_Ok(not fresh3.codecs.DoesExist("mp3") and not fresh3.codecs.DoesExist("pcm"),"Malformed native MP3 and PCM answers stay unknown instead of inheriting old results")
Harness_Ok(m.capsDevice.calls.Count() = 18,"Malformed answers do not prevent a fresh query for every codec")
m.capsDevice = invalid
Harness_Ok(AudioCapabilities_ReadDevice().codecs.Count() = 0,"Unavailable native component remains an unknown capability")
limits = AudioCapabilities_ChannelLimits({AAC:"2:0:0:0:",MP3:"2:0:0:0",PCM:"2:0:0:0",AC3:"6:6:0:1", "DD+":"8:6:0:1",DTS:"6:0:0:1"})
Harness_Ok(limits.aac = 2,"AAC channel limit is separately preserved")
Harness_Ok(limits.ac3 = 6,"AC3 channel limit reports six channels")
Harness_Ok(limits.eac3 = 8,"DD+ maps to native EAC3")
Harness_Ok(limits.dts = 6,"DTS output is recorded rather than assumed from a preset")
Harness_Ok(limits.mp3 = 2 and limits.pcm = 2,"MP3 and PCM channel reports stay separate from AAC support")
limits = AudioCapabilities_ChannelLimits({" AAC_ADTS ":"2:0:0:0",AAC_MAGIC:"6:0:0:0"})
Harness_Ok(limits.aac = 2,"Native AAC aliases use the same normalized channel capability key")
Harness_Ok(not limits.DoesExist("aac_magic") and limits.Count() = 1,"Invented AAC alias does not become a channel support claim")
limits = AudioCapabilities_ChannelLimits({AAC:"6",AC3:"6:0:0:2",DTS:"96:0:0:1", "DD+":invalid})
Harness_Ok(limits.Count() = 0,"Malformed or incomplete EDID decoder strings are unknown")
Harness_Ok(AudioCapabilities_ChannelLimits(invalid).Count() = 0,"Unavailable decoder data remains empty")
Harness_Ok(AudioCapabilities_ExplicitlyUnsupported({codecs:{ac3:false,eac3:true}},"ac3"),"Explicit receiver refusal blocks incompatible Dolby")
Harness_Ok(not AudioCapabilities_ExplicitlyUnsupported({codecs:{ac3:false,eac3:true}},"eac3"),"Positive DD+ result is not rejected")
Harness_Ok(not AudioCapabilities_ExplicitlyUnsupported({codecs:{}},"eac3"),"Unknown capability does not invent a negative verdict")
Harness_Ok(not AudioCapabilities_ExplicitlyUnsupported(invalid,"aac"),"Missing API object remains unknown")
Harness_Ok(AudioCapabilities_ExplicitlyUnsupported({codecs:{aac:false}},"aac_adts"),"Native AAC aliases use the AAC capability query")
for each nativeAlias in ["aac_adif","aac_adts","aac_latm"," AAC_LATM "]
    Harness_Ok(AudioCapabilities_ExplicitlyUnsupported({codecs:{aac:false}},nativeAlias),"Recognized native AAC alias uses the AAC capability refusal")
end for
for each inventedAlias in ["aac_unknown","aac_magic","aac_","aac_hev2"]
    Harness_Ok(not AudioCapabilities_ExplicitlyUnsupported({codecs:{aac:false}},inventedAlias),"Invented AAC prefix does not borrow the AAC query result")
end for
Harness_Ok(AudioCapabilities_ExplicitlyUnsupported({codecs:{mp3:false}}," MP3 "),"Explicit local MP3 refusal is recognized")
Harness_Ok(AudioCapabilities_ExplicitlyUnsupported({codecs:{pcm:false}},"pcm"),"Explicit local PCM refusal is recognized")
Harness_Ok(not AudioCapabilities_ExplicitlyUnsupported({codecs:{mp3:"no",pcm:0}},"mp3") and not AudioCapabilities_ExplicitlyUnsupported({codecs:{mp3:"no",pcm:0}},"pcm"),"Malformed local codec booleans do not invent refusal")
Harness_Ok(not AudioCapabilities_ExplicitlyUnsupported({codecs:{}},"mp3") and not AudioCapabilities_ExplicitlyUnsupported({codecs:{}},"pcm"),"Unavailable local codec query results remain unknown")
Harness_Ok(not AudioCapabilities_ExplicitlyUnsupported({codecs:{aac:0}},"aac"),"Malformed boolean cannot create a refusal")
Harness_Ok(AudioCapabilities_Text({output:"Stereo"}).InStr("Stereo") >= 0,"Output preference is visible")
Harness_Ok(AudioCapabilities_Text({}).InStr("Not reported") >= 0,"Missing output never claims surround")
Harness_Finish()
`;
  const file = path.join(dir,'audio-caps.brs');
  fs.writeFileSync(file,code);
  const result = spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',dir,file],{encoding:'utf8'});
  process.stdout.write(result.stdout || '');
  process.stderr.write(result.stderr || '');
  process.exitCode = result.status === 0 && !(result.stderr || '').trim() && /RESULT: PASS/.test(result.stdout || '') ? 0 : 1;
} finally {
  const resolved = path.resolve(dir);
  if (path.dirname(resolved) !== path.resolve(os.tmpdir()) || !path.basename(resolved).startsWith('rokumio-audio-caps-')) throw Error('Unexpected audio capability fixture path');
  fs.rmSync(resolved,{recursive:true,force:true});
}
