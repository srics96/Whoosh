// Read-only bridge. No query(), resume, mutation, credentials, or private DB access.
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
import {readFile} from 'node:fs/promises';
export const notice = 'Claude Agent SDK normalized active conversation chain, including exposed system/tool blocks. Not original transcript bytes; alternate branches, subagents, external attachment bytes and non-message records are not captured. Chat/Cowork coverage and desktop origin are not established. Source activity is unknown.';
export async function handle(sdk, request) {
  const dir = request.dir;
  if (request.action === 'list') {
    const offset = Number(request.offset || 0);
    if (!Number.isSafeInteger(offset) || offset < 0) throw Error('Invalid offset');
    const rows = await sdk.listSessions({dir, limit:50, offset, includeWorktrees:false, includeProgrammatic:true});
    return {sessions:rows.map(({sessionId,summary,customTitle,cwd,lastModified,fileSize})=>({sessionId,summary:customTitle||summary,cwd,lastModified,fileSize})), nextOffset:rows.length===50 ? offset+50 : null};
  }
  if (!/^[a-f0-9-]{36}$/i.test(request.id || '')) throw Error('Invalid session');
  const before = await sdk.getSessionInfo(request.id,{dir});
  if (!before || before.sessionId !== request.id) throw Error('Session identity mismatch');
  if (dir && (!before.cwd || resolve(dir).normalize('NFC') !== resolve(before.cwd).normalize('NFC'))) throw Error('Project mismatch');
  if(request.action==='info') return {info:before};
  if(request.action!=='read') throw Error('Unsupported operation');
  const messages=[]; const seen=new Set(); let exhausted=false;
  for(let offset=0;offset<10000;offset+=100) {
    const page=await sdk.getSessionMessages(request.id,{dir,limit:100,offset,includeSystemMessages:true});
    for(const message of page) { if(seen.has(message.uuid)) throw Error('Unstable pagination'); seen.add(message.uuid); messages.push(message); }
    if(Buffer.byteLength(JSON.stringify(messages))>32*1024*1024) throw Error('History exceeds safe capture size');
    if(page.length<100) {exhausted=true;break;}
  }
  const after=await sdk.getSessionInfo(request.id,{dir});
  if(!after || after.sessionId!==request.id || before.cwd!==after.cwd || before.lastModified!==after.lastModified || before.fileSize!==after.fileSize) throw Error('Source changed; stop it and select again');
  if(messages.length===0) throw Error('No readable messages');
  return {info:after, archive:JSON.stringify({provider:'claude-agent-sdk',version:'0.3.306',session:after,messages,apiChainExhausted:exhausted,notice})+'\n', partial:true, notice:notice+(exhausted?' All API chain pages captured.':' Capture stopped at 10000 messages; more may exist.')};
}
if (process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  try {
    process.stderr.write('BLINK:started\n');
    const config=JSON.parse(await readFile(new URL('./runtime.json',import.meta.url),'utf8'));
    process.stderr.write('BLINK:config-loaded\n');
    const sdkURL = new URL(config.sdkModule, import.meta.url);
    await readFile(sdkURL);
    process.stderr.write('BLINK:sdk-readable\n');
    const sdk=await import(sdkURL.href);
    process.stderr.write('BLINK:sdk-loaded\n');
    const input=process.argv[2] || ''; if(input.length>16384) throw Error('Request too large');
    const result=await handle(sdk,JSON.parse(input));
    process.stderr.write('BLINK:read-complete\n');
    process.stdout.write(JSON.stringify(result));
  } catch(error) {
    const known=['Session identity mismatch','Project mismatch','Source changed; stop it and select again','No readable messages','Unstable pagination','History exceeds safe capture size','Invalid session','Unsupported operation'];
    process.stderr.write('BLINK:error:'+(known.includes(error.message)?error.message:'Reader unavailable'));
    process.exitCode=1;
  }
}
