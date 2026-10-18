import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {cosine,rankMatches} from '../../supabase/functions/match-volunteers/matching.mjs';
const source=readFileSync(new URL('../../supabase/functions/match-volunteers/index.ts',import.meta.url),'utf8').replace(/^import .*;\r?\n/gm,'');
const js=stripTypeScriptTypes(source);
const condition={id:'c1',name:'Asthma'};
const context={seeker:{description:'Daily routines',language:'English',conditions:[condition]},candidates:[{user_id:'v1',full_name:'Private name',language:'English',description:'Daily routines support',conditions:[condition],status:'approved',ai_consent:true}]};
function setup({key='secret-test-only',data=context,authError=null,rpcError=null,providerError=false}={}){
 let handler;const calls=[];let authCalls=0;
 const client={auth:{getUser:async()=>{authCalls++;return {data:{user:authError?null:{id:'s1'}},error:authError};}},rpc:async(name)=>{assert.equal(name,'maak_matching_context');return {data,error:rpcError};}};
 const Deno={env:{get:name=>name==='GEMINI_API_KEY'?key:'test'},serve:fn=>handler=fn};
 const fetch=async(url,options)=>{calls.push(JSON.parse(options.body));if(providerError)return new Response('{}',{status:503});return new Response(JSON.stringify({embedding:{values:Array(768).fill(1)}}),{status:200});};
 new Function('Deno','createClient','cosine','rankMatches','fetch',js)(Deno,()=>client,cosine,rankMatches,fetch);
 const invoke=async(body={},authorized=true)=>handler(new Request('https://test/functions/v1/match-volunteers',{method:'POST',headers:authorized?{Authorization:'Bearer token'}:{},body:JSON.stringify(body)}));
 return {invoke,calls,authCalls:()=>authCalls};
}
test('EDGE-01 unsigned requests never reach profile lookup',async()=>{const s=setup();assert.equal((await s.invoke({},false)).status,401);assert.equal(s.authCalls(),0)});
test('EDGE-02 invalid session rejected',async()=>{const s=setup({authError:new Error('invalid')});assert.equal((await s.invoke()).status,401)});
test('EDGE-03 seeker-only SQL permission failure respected',async()=>{const s=setup({rpcError:{message:'not_allowed'}});assert.equal((await s.invoke()).status,403)});
test('EDGE-04 AI off causes zero external calls',async()=>{const s=setup();const r=await (await s.invoke()).json();assert.equal(r.mode,'conditions');assert.equal(s.calls.length,0)});
test('EDGE-05 missing key transparently returns condition recommendations',async()=>{const s=setup({key:null});const r=await (await s.invoke({use_ai:true})).json();assert.equal(r.mode,'conditions');assert.match(r.notice,/not configured/);assert.equal(s.calls.length,0)});
test('EDGE-06 volunteer opt-out prevents all external requests',async()=>{const s=setup({data:{...context,candidates:context.candidates.map(c=>({...c,ai_consent:false}))}});await s.invoke({use_ai:true});assert.equal(s.calls.length,0)});
test('EDGE-07 AI sends descriptions only and returns semantic result',async()=>{const s=setup();const r=await (await s.invoke({use_ai:true,seeker_id:'victim'})).json();assert.equal(r.mode,'ai');assert.equal(s.calls.length,2);assert.equal(r.matches[0].experience_similarity,1);for(const c of s.calls){assert.ok(c.content.parts[0].text.includes('Daily routines'));assert.ok(!JSON.stringify(c).includes('Private name'));assert.ok(!JSON.stringify(c).includes('victim'));}});
test('EDGE-08 failed provider falls back without fake similarity',async()=>{const s=setup({providerError:true});const r=await (await s.invoke({use_ai:true})).json();assert.equal(r.mode,'conditions');assert.equal(r.matches[0].experience_similarity,null);assert.match(r.notice,/temporarily unavailable/)});
test('EDGE-09 repeated AI calls fall back during cooldown',async()=>{const s=setup();await s.invoke({use_ai:true});const r=await (await s.invoke({use_ai:true})).json();assert.equal(s.calls.length,2);assert.equal(r.mode,'conditions');assert.match(r.notice,/30 seconds/)});
test('EDGE-10 empty support description avoids external requests',async()=>{const s=setup({data:{...context,seeker:{...context.seeker,description:' '}}});await s.invoke({use_ai:true});assert.equal(s.calls.length,0)});
