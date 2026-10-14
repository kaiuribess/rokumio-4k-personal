// Actual public route and connection sweep; no network or device access.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..'),read=f=>fs.readFileSync(path.join(root,f),'utf8');
const source=read('source/util/SetupPage.brs');
const names=['CrLf','SetupHeaderValue','SetupSameOrigin','SetupRequestPath','SetupRequestMethod','SetupBody','SetupFormValue','SetupFormDecode','SetupPercentDecodeAscii','SetupHexByte','SetupReplaceChar','SetupConnectionExpired','SetupServerSweep','SetupServerDrop','SetupServerHandle'];
const methods=names.map(name=>{
 const match=new RegExp('^(?:sub|function) '+name+'\\([^]*?^end (?:sub|function)','mi').exec(source);
 assert.ok(match,name);return match[0];
});
assert.match(read('source/main.brs'),/message = Wait\(300, port\)\s+SetupServerSweep\(setup\)/);
const fixtures=`
sub SetupServerRespond(setup as object,key as string,conn as object,code as string,body as string)
 conn.code=code
end sub
function SetupHtmlStatus(code as string) as string
 return code
end function
function SetupHtmlPage() as string
 return "Form"
end function
function SetupHtmlSent() as string
 return "Sent"
end function
function SetupHtmlBusy() as string
 return "Busy"
end function
function SetupHtml(title as string,body as string) as string
 return title
end function
function SetupValidateManifestUrl(value as string) as string
 return value
end function
function TestRequest(path as string,body as string) as string
 return "POST "+path+" HTTP/1.1"+CrLf()+"Host: 192.168.1.20:8744"+CrLf()+"Content-Length: "+Len(body).ToStr()+CrLf()+CrLf()+body
end function
Harness_Suite("Public setup rejects playback mutation while preserving gated imports")
scene={calls:[],addonsOpen:true,callFunc:function(name as string,a=invalid as dynamic,b=invalid as dynamic) as boolean
 m.calls.Push(name)
 return m.addonsOpen
end function}
setup={scene:scene,address:"http://192.168.1.20:8744"}
for each kind in ["stop","movie","stereo-control","4k-control","4k-hls-control"]
 conn={inbound:TestRequest("/playback-test","mode="+kind+"&movieId=tt1234567")}
 SetupServerHandle(setup,"test",conn,"ready")
 Harness_Equal(conn.code,"403","public playback command is forbidden: "+kind)
end for
Harness_Equal(scene.calls.Count(),0,"rejected diagnostics never dispatch to the scene")
conn={inbound:TestRequest("/","manifest=https%3A%2F%2Faddon.example.test%2Fmanifest.json")}
SetupServerHandle(setup,"test",conn,"ready")
Harness_Equal(conn.code,"200","normal add-on import still dispatches")
Harness_Equal(scene.calls[0],"ImportFromSetup","ordinary import retains scene permission gate")
scene.addonsOpen=false
SetupServerHandle(setup,"test",conn,"ready")
Harness_Equal(conn.code,"409","closed Add-ons screen can still refuse import")

Harness_Suite("Idle setup slots are reclaimed without touching active connections")
setup={clock:{TotalMilliseconds:function() as integer
 return 10000
end function},connections:{}}
for index=0 to 7
 setup.connections[index.ToStr()]={startedAt:0,lastActivity:0,socket:{closed:false,Close:sub()
  m.closed=true
 end sub}}
end for
active={startedAt:9000,lastActivity:9000,socket:{closed:false,Close:sub()
 m.closed=true
end sub}}
setup.connections.active=active
old=setup.connections["0"]
SetupServerSweep(setup)
Harness_Equal(setup.connections.Count(),1,"all eight idle slots are reclaimed")
Harness_Ok(old.socket.closed,"expired client socket closes")
Harness_Ok(not active.socket.closed,"active request remains admitted")
SetupServerSweep(invalid)
Harness_Finish()
`;
const dir=path.join(root,'out-test','setup-server');fs.mkdirSync(dir,{recursive:true});
const file=path.join(dir,'tests.brs');fs.writeFileSync(file,[read('tests/harness.brs'),...methods,fixtures].join('\n'));
const run=spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',dir,file],{cwd:dir,encoding:'utf8'});
process.stdout.write(run.stdout||'');process.stderr.write(run.stderr||'');
process.exitCode=run.status===0&&!(run.stderr||'').trim()&&/RESULT: PASS/.test(run.stdout||'')?0:1;
