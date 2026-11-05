import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=readFileSync(new URL('../../supabase/functions/send-volunteer-email/index.ts',import.meta.url),'utf8').replace(/^import .*;\r?\n/gm,'');
const js=stripTypeScriptTypes(source);
const VOLUNTEER='11111111-1111-4111-8111-111111111111';
const CALLER='22222222-2222-4222-8222-222222222222';
function setup({authError=null,admin=false,app={status:'pending_review',rejection_reason:null},
 fullName='Vol <b>One</b>',targetEmail='volunteer@example.com',brevoKey='test-key',providerError=false}={}){
 let handler;const sent=[];const logs=[];let authCalls=0;let serviceCalls=0;const queried=[];
 const user={id:CALLER,email:'caller@example.com'};
 const userClient={auth:{getUser:async()=>{authCalls++;return {data:{user:authError?null:user},error:authError};}},
  rpc:async(name)=>{assert.equal(name,'is_maak_admin');return {data:admin,error:null};}};
 const service={from:(table)=>{serviceCalls++;const q={select:()=>q,eq:(col,val)=>{queried.push([table,val]);return q;},
  maybeSingle:async()=>({data:table==='volunteer_profiles'?app:{full_name:fullName},error:null})};return q;},
  auth:{admin:{getUserById:async(id)=>{queried.push(['auth.users',id]);return {data:{user:{email:targetEmail}},error:null};}}}};
 const env={'maak-supabase-email':brevoKey,SUPABASE_URL:'https://x',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service'};
 const Deno={env:{get:(n)=>env[n]},serve:(fn)=>handler=fn};
 const createClient=(_url,key)=>key==='service'?service:userClient;
 const fetch=async(_url,options)=>{sent.push(JSON.parse(options.body));
  return providerError?new Response('{"code":"secret_provider_detail"}',{status:400}):new Response('{"messageId":"m1"}',{status:201});};
 const console={log:(...a)=>logs.push(a.join(' ')),error:(...a)=>logs.push(a.join(' '))};
 new Function('Deno','createClient','fetch','console',js)(Deno,createClient,fetch,console);
 const invoke=async(body,authorized=true)=>handler(new Request('https://test/functions/v1/send-volunteer-email',
  {method:'POST',headers:authorized?{Authorization:'Bearer token'}:{},body:JSON.stringify(body)}));
 return {invoke,sent,logs,queried,authCalls:()=>authCalls,serviceCalls:()=>serviceCalls};
}
test('EMAIL-01 unsigned requests are rejected before any lookup',async()=>{const s=setup();assert.equal((await s.invoke({status:'pending'},false)).status,401);assert.equal(s.authCalls(),0);assert.equal(s.sent.length,0)});
test('EMAIL-02 invalid session is rejected',async()=>{const s=setup({authError:new Error('bad')});assert.equal((await s.invoke({status:'pending'})).status,401);assert.equal(s.sent.length,0)});
test('EMAIL-03 unknown status is rejected',async()=>{const s=setup();assert.equal((await s.invoke({status:'promo'})).status,400);assert.equal(s.sent.length,0)});
test('EMAIL-04 pending goes only to the caller and ignores client recipient fields',async()=>{const s=setup();
 const r=await s.invoke({status:'pending',email:'victim@example.com',name:'Spoof',volunteerId:VOLUNTEER});assert.equal(r.status,200);
 assert.equal(s.sent.length,1);assert.deepEqual(s.sent[0].to,[{email:'caller@example.com',name:'Vol <b>One</b>'}]);
 assert.ok(!JSON.stringify(s.sent[0]).includes('victim'));assert.ok(!JSON.stringify(s.sent[0]).includes('Spoof'));
 assert.ok(s.queried.every(([,id])=>id===CALLER));assert.ok(s.sent[0].htmlContent.includes('Vol &lt;b&gt;One&lt;/b&gt;'))});
test('EMAIL-05 pending requires a pending application',async()=>{const s=setup({app:{status:'approved'}});assert.equal((await s.invoke({status:'pending'})).status,409);assert.equal(s.sent.length,0)});
test('EMAIL-06 pending without any application is refused',async()=>{const s=setup({app:null});assert.equal((await s.invoke({status:'pending'})).status,409);assert.equal(s.sent.length,0)});
test('EMAIL-07 non-admins cannot send review emails',async()=>{for(const status of ['approved','rejected']){const s=setup({app:{status}});
 assert.equal((await s.invoke({status,volunteerId:VOLUNTEER,email:'victim@example.com'})).status,403);assert.equal(s.serviceCalls(),0);assert.equal(s.sent.length,0)}});
test('EMAIL-08 admin review email needs a valid volunteer ID',async()=>{const s=setup({admin:true,app:{status:'approved'}});assert.equal((await s.invoke({status:'approved',volunteerId:'x'})).status,400);assert.equal(s.sent.length,0)});
test('EMAIL-09 review email must match the stored decision',async()=>{const s=setup({admin:true});assert.equal((await s.invoke({status:'approved',volunteerId:VOLUNTEER})).status,409);assert.equal(s.sent.length,0)});
test('EMAIL-10 admin approval goes to the stored volunteer address',async()=>{const s=setup({admin:true,app:{status:'approved'}});
 assert.equal((await s.invoke({status:'approved',volunteerId:VOLUNTEER,email:'victim@example.com'})).status,200);
 assert.equal(s.sent[0].to[0].email,'volunteer@example.com');assert.ok(s.queried.some(([t,id])=>t==='auth.users'&&id===VOLUNTEER))});
test('EMAIL-11 rejection uses the stored, escaped reason and ignores client text',async()=>{const s=setup({admin:true,app:{status:'rejected',rejection_reason:'Unclear <script>x</script> document'}});
 assert.equal((await s.invoke({status:'rejected',volunteerId:VOLUNTEER,rejectionReason:'Click http://phish'})).status,200);
 const html=s.sent[0].htmlContent;assert.ok(html.includes('Unclear &lt;script&gt;'));assert.ok(!html.includes('<script>'));assert.ok(!html.includes('phish'))});
test('EMAIL-12 repeated sends are throttled',async()=>{const s=setup();await s.invoke({status:'pending'});assert.equal((await s.invoke({status:'pending'})).status,429);assert.equal(s.sent.length,1)});
test('EMAIL-13 provider failure hides details and allows a retry',async()=>{const s=setup({providerError:true});const r=await s.invoke({status:'pending'});
 assert.equal(r.status,502);assert.ok(!(await r.text()).includes('secret_provider_detail'));await s.invoke({status:'pending'});assert.equal(s.sent.length,2)});
test('EMAIL-14 missing provider key sends nothing',async()=>{const s=setup({brevoKey:null});assert.equal((await s.invoke({status:'pending'})).status,503);assert.equal(s.sent.length,0)});
test('EMAIL-15 recipient addresses are never logged',async()=>{const s=setup({admin:true,app:{status:'approved'}});await s.invoke({status:'approved',volunteerId:VOLUNTEER});
 const s2=setup({providerError:true});await s2.invoke({status:'pending'});
 for(const line of [...s.logs,...s2.logs])assert.ok(!line.includes('@'),line)});
