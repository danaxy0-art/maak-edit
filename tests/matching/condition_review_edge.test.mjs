import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=stripTypeScriptTypes(readFileSync(new URL('../../supabase/functions/review-condition-name/index.ts',import.meta.url),'utf8').replace(/^import .*;\n/gm,''));
const id='00000000-0000-0000-0000-000000000001';
function setup({admin=true,key='test-only',status='pending',answer={is_health_condition:true},providerError=false}={}){
 let handler;const writes=[];const provider=[];
 const client={auth:{getUser:async()=>({data:{user:{id:'admin'}},error:null})},rpc:async(name,args)=>{if(name==='is_maak_admin')return {data:admin,error:null};assert.equal(name,'record_condition_name_check');writes.push(args);return {error:null};},from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>({data:{submitted_name:'Lupus',status},error:null})})})})};
 const Deno={env:{get:n=>n==='GEMINI_API_KEY'?key:'test'},serve:fn=>handler=fn};
 const fetch=async(url,options)=>{provider.push(JSON.parse(options.body));return providerError?new Response('{}',{status:500}):new Response(JSON.stringify({candidates:[{content:{parts:[{text:JSON.stringify(answer)}]}}]}));};
 new Function('Deno','createClient','fetch',source)(Deno,()=>client,fetch);
 const invoke=(body={request_id:id},signed=true)=>handler(new Request('https://test/check',{method:'POST',headers:signed?{Authorization:'Bearer token'}:{},body:JSON.stringify(body)}));
 return {invoke,provider,writes};
}
test('REVIEW-EDGE01 unsigned access denied before AI',async()=>{const s=setup();assert.equal((await s.invoke({},false)).status,401);assert.equal(s.provider.length,0)});
test('REVIEW-EDGE02 non-admin cannot check names',async()=>{const s=setup({admin:false});assert.equal((await s.invoke()).status,403);assert.equal(s.provider.length,0)});
test('REVIEW-EDGE03 only pending requests can be checked',async()=>{const s=setup({status:'accepted'});assert.equal((await s.invoke()).status,409);assert.equal(s.provider.length,0)});
test('REVIEW-EDGE04 absent key preserves manual workflow',async()=>{const s=setup({key:null});assert.equal((await s.invoke()).status,503);assert.equal(s.writes.length,0)});
test('REVIEW-EDGE05 false verdict is only an advisory warning',async()=>{const s=setup({answer:{is_health_condition:false}});const r=await(await s.invoke()).json();assert.equal(r.state,'warning');assert.equal(r.advisory_only,true);assert.equal(s.writes[0].p_state,'warning');assert.deepEqual(JSON.parse(s.provider[0].contents[0].parts[0].text),{name:'Lupus'});});
test('REVIEW-EDGE06 health verdict never accepts or links request',async()=>{const s=setup();const r=await(await s.invoke()).json();assert.equal(r.state,'health');assert.equal(s.writes.length,1);assert.deepEqual(Object.keys(s.writes[0]).sort(),['p_request_id','p_state']);});
test('REVIEW-EDGE07 malformed verdict records uncertainty instead of rejection',async()=>{const s=setup({answer:{is_health_condition:'yes'}});const r=await(await s.invoke()).json();assert.equal(r.state,'unknown');});
test('REVIEW-EDGE08 provider failure remains advisory unknown',async()=>{const s=setup({providerError:true});const r=await(await s.invoke()).json();assert.equal(r.state,'unknown');});
