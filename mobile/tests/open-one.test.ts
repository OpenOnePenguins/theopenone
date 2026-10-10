/// <reference types="node" />
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {ApiError, Conversation, getConversation, OpenOneClient, operationID, parsePairing, Receipt, sendMessage, watchReceipt} from '../src/lib/open-one';
const pairing={endpoint:'https://192.168.86.73',token:'x'.repeat(43)};
const conversation:Conversation={id:'one',conversationKey:'same-session',folder:'my-worktree',title:'A conversation',provider:'Codex',state:'done',canReceive:true,readOnlyReason:'',requestID:null,choices:[],messages:[],name:'Codex'};
const operation={id:'ef6ac36d-1d23-4338-9f82-5571e0e21bfa',text:'Continue this task',at:123,conversationKey:conversation.conversationKey};
test('operation IDs accept random bytes without requiring browser randomUUID on LAN HTTP',()=>{
 const bytes = Uint8Array.from({length:16},(_,index)=>index);
 assert.equal(operationID(bytes),'00010203-0405-4607-8809-0a0b0c0d0e0f');
 assert.equal(bytes[6],6); assert.equal(bytes[8],8);
 assert.throws(()=>operationID(new Uint8Array(0)));
});
test('accepts Open One links and refuses insecure remote credentials or other protocols',()=>{
 assert.deepEqual(parsePairing(`${pairing.endpoint}/#${pairing.token}`),pairing);
 assert.equal(parsePairing(`http://127.0.0.1:1234/#${pairing.token}`).endpoint,'http://127.0.0.1:1234');
 for(const url of [`http://8.8.8.8/#${pairing.token}`,`orca://pair?code=abc`,`https://user:pass@mac/#${pairing.token}`,`${pairing.endpoint}/path#${pairing.token}`,`${pairing.endpoint}/?token=${pairing.token}`,`${pairing.endpoint}/#short`])assert.throws(()=>parsePairing(url));
});
test('LAN addresses pair directly; Tailscale, public addresses and remote names are refused',()=>{
 for(const host of ['10.20.30.40','172.16.0.1','172.31.255.254','192.168.86.73'])
  assert.equal(parsePairing(`http://${host}:1234/#${pairing.token}`).endpoint,`http://${host}:1234`);
 for(const host of ['8.8.8.8','172.15.0.1','172.32.0.1','100.63.0.1','100.64.0.1','100.127.255.254','100.128.0.1','192.168.1.1.evil.example','my-mac.tail123.ts.net','sample.trycloudflare.com'])
  for(const scheme of ['http','https']) {
   const endpoint=`${scheme}://${host}:1234`;
   assert.throws(()=>parsePairing(`${endpoint}/#${pairing.token}`));
   assert.throws(()=>parsePairing(JSON.stringify({endpoint,token:pairing.token})));
   assert.throws(()=>parsePairing(`open-one:///?endpoint=${encodeURIComponent(endpoint)}#${pairing.token}`));
  }
});
test('native QR opens the root route and preserves the exact HTTPS Mac credential',()=>{
 const link=`open-one:///?endpoint=${encodeURIComponent(pairing.endpoint+'/')}#${pairing.token}`;
 assert.deepEqual(parsePairing(link),pairing);
 assert.deepEqual(parsePairing(JSON.stringify(pairing)),pairing);
 for(const url of [
  `open-one://other/?endpoint=${encodeURIComponent(pairing.endpoint)}#${pairing.token}`,
  `open-one:///chat?endpoint=${encodeURIComponent(pairing.endpoint)}#${pairing.token}`,
  `${link.replace('#','&endpoint=https%3A%2F%2Fother.example#')}`,
  `${link.replace('#','&extra=1#')}`,
  `open-one:///?endpoint=${encodeURIComponent('http://127.0.0.1:1234')}#${pairing.token}`,
  `open-one:///?endpoint=${encodeURIComponent(pairing.endpoint+'/#different')}#${pairing.token}`,
  `open-one:///?endpoint=${encodeURIComponent(pairing.endpoint+'/?token=leak')}#${pairing.token}`,
 ]) assert.throws(()=>parsePairing(url));
});
test('HTTP client authenticates, forbids redirects, and never puts credentials in URL',async()=>{
 const c=new OpenOneClient(pairing,(async function(this: unknown,url,options){
  assert.equal(this,undefined);
  assert.equal(url,`${pairing.endpoint}/api/info`);assert.equal(options?.redirect,'error');assert.equal((options?.headers as Record<string,string>).Authorization,`Bearer ${pairing.token}`);
  return new Response(JSON.stringify({app:'open-one',protocolVersion:2}));
 }) as typeof fetch);
 await c.connect();c.close();await assert.rejects(c.connect(),/Reconnect/);
});
test('client rejects unrelated hosts and authentication failure',async()=>{
 const c=new OpenOneClient(pairing,(async()=>new Response(JSON.stringify({app:'other',protocolVersion:2}))) as typeof fetch);
 await assert.rejects(c.connect(),/Update Open One/);
 const denied=new OpenOneClient(pairing,(async()=>new Response(JSON.stringify({error:'Expired'}),{status:401})) as typeof fetch);
 await assert.rejects(denied.connect(),e=>e instanceof ApiError&&e.status===401);
});
function fixture(mode='ok'){
 let posts=0;let persisted=false;let body:any;
 const client={conversations:async()=>{throw Error('Send must not download histories');},request:async(path:string,input:any)=>{
  assert.equal(path,'/api/commands');
  assert.equal(persisted,true);posts++;body=input;
  if(mode==='refused')throw new ApiError('No longer available',409);
  if(mode==='network')throw Error('Connection lost');
  return {id:operation.id};
 }} as unknown as OpenOneClient;
 return {client,persist:async()=>{persisted=true;},clear:async()=>{persisted=false;},get posts(){return posts;},get persisted(){return persisted;},get body(){return body;}};
}
test('send targets exact conversation and persists operation before first write',async()=>{
 const f=fixture();await sendMessage(f.client,conversation,operation,f.persist,f.clear);
 assert.equal(f.posts,1);assert.equal(f.persisted,true);assert.deepEqual(f.body,{operationID:operation.id,agentID:'one',conversationKey:'same-session',requestID:null,text:operation.text,choiceIndex:null});
});
test('an operation for another session, readonly recipient, or invalid choice is refused locally',async()=>{
 const f=fixture();
 await assert.rejects(sendMessage(f.client,conversation,{...operation,conversationKey:'different'},f.persist,f.clear));
 await assert.rejects(sendMessage(f.client,{...conversation,canReceive:false},operation,f.persist,f.clear));
 await assert.rejects(sendMessage(f.client,conversation,operation,f.persist,f.clear,0));
 assert.equal(f.posts,0);assert.equal(f.persisted,false);
});
test('chat refresh downloads only the exact conversation and still fences changed sessions',async()=>{
 let changed=false;const paths:string[]=[];
 const c=new OpenOneClient(pairing,(async url=>{
  paths.push(String(url));return new Response(JSON.stringify({...conversation,id:'observed:tree/session',conversationKey:changed?'new-session':conversation.conversationKey}));
 }) as typeof fetch);
 const selected={...conversation,id:'observed:tree/session'};
 assert.equal((await getConversation(c,selected)).id,selected.id);
 assert.equal(paths[0],`${pairing.endpoint}/api/conversations/observed%3Atree%2Fsession`);
 changed=true;await assert.rejects(getConversation(c,selected),/conversation changed/);
});
test('chat refresh remains compatible with older version-2 desktops',async()=>{
 const c=new OpenOneClient(pairing,(async url=>String(url).endsWith('/api/state')
  ?new Response(JSON.stringify({agents:[conversation]})):new Response(JSON.stringify({error:'Not found'}),{status:404})) as typeof fetch);
 assert.deepEqual(await getConversation(c,conversation),conversation);
});
test('fast receipt checks are sequential and stop on confirmed delivery without sending again',async()=>{
 let requests=0;let inflight=0;const statuses:string[]=[];
 const c={receipt:async()=>{
  requests++;inflight++;assert.equal(inflight,1);
  await new Promise(resolve=>setTimeout(resolve,5));inflight--;
  return {status:requests===1?'queued':'delivered',message:'Fixture'} as Receipt;
 }};
 await new Promise<void>(resolve=>{
  watchReceipt(c,operation.id,async receipt=>{statuses.push(receipt.status);if(receipt.status==='delivered')resolve();},error=>{throw error;},1);
 });
 await new Promise(resolve=>setTimeout(resolve,15));
 assert.equal(requests,2);assert.deepEqual(statuses,['queued','delivered']);
});
test('leaving a chat ignores an in-flight receipt and cancels further checks',async()=>{
 let resolve!: (value:Receipt)=>void;let notifications=0;let requests=0;
 const c={receipt:()=>{requests++;return new Promise<Receipt>(done=>{resolve=done;});}};
 const stop=watchReceipt(c,operation.id,async()=>{notifications++;},()=>{notifications++;},1);
 stop();resolve({status:'delivered',message:'Fixture'});
 await new Promise(done=>setTimeout(done,10));assert.equal(notifications,0);assert.equal(requests,1);
});
test('definite refusal clears operation, uncertain failure retains it without retry',async()=>{
 for(const mode of ['refused','network']){const f=fixture(mode);await assert.rejects(sendMessage(f.client,conversation,operation,f.persist,f.clear));assert.equal(f.posts,1);assert.equal(f.persisted,mode==='network');}
});
test('a failed durable write prevents delivery',async()=>{
 const f=fixture();await assert.rejects(sendMessage(f.client,conversation,operation,async()=>{throw Error('disk full');},f.clear));assert.equal(f.posts,0);
});
test('request abort times out without retrying',async()=>{
 let calls=0;
 const c=new OpenOneClient(pairing,((url,options)=>{calls++;return new Promise((resolve,reject)=>{options?.signal?.addEventListener('abort',()=>reject(Error('aborted')));});}) as typeof fetch,5);
 await assert.rejects(c.connect(),/Could not reach/);assert.equal(calls,1);
});
