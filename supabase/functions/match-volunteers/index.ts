import { createClient } from 'npm:@supabase/supabase-js@2';
import { cosine, rankMatches, generalSuggestions } from './matching.mjs';
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store'};
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...headers,'Content-Type':'application/json'}});
const recent=new Map<string,number>();
Deno.serve(async(req)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers});
 if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
 try {
  const authorization=req.headers.get('Authorization');
  if(!authorization?.startsWith('Bearer '))return reply({error:'sign_in_required'},401);
  const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:authorization}},auth:{persistSession:false}});
  const {data:{user},error:authError}=await client.auth.getUser(authorization.slice(7));
  if(authError||!user)return reply({error:'sign_in_required'},401);
  const input=await req.json().catch(()=>({}));
  // Never accept a seeker ID or profiles from the caller. SQL scopes to auth.uid().
  const {data:context,error}=await client.rpc('maak_matching_context');
  // account_blocked: an administrator blocked this account (20261021_account_blocking.sql).
  if(error)return error.message.includes('account_blocked')?reply({error:'account_blocked'},403):reply({error:error.message.includes('not_allowed')?'help_seeker_only':'matching_setup_or_profile_incomplete'},error.message.includes('not_allowed')?403:409);
  const {seeker,candidates}=context;
  if(context.general_mode===true) return reply({...generalSuggestions(seeker,candidates),mode:'general',notice:'General suggestions only. Your submitted condition is not used for matching until approved. No disease score or AI comparison is applied.',seeker_conditions:seeker.conditions,scoring_version:'general-v1'});
  let mode='conditions';let notice='Ranked by shared conditions, then preferred language.';
  const semantic:Record<string,number>={};
  const key=Deno.env.get('GEMINI_API_KEY');
  const eligible=candidates.filter((c:any)=>c.ai_consent&&c.description?.trim());
  if(input.use_ai===true) {
   if(!key)notice='AI is not configured. Condition-based recommendations are shown.';
   else if(!seeker.description?.trim())notice='Add a support description in your profile to compare experiences.';
   else if(!eligible.length)notice='No matching volunteers have opted into AI experience comparison. Condition-based recommendations are shown.';
   else if(Date.now()-(recent.get(user.id)??0)<30000)notice='Please wait 30 seconds before another AI comparison. Condition-based recommendations are shown.';
   else {
    recent.set(user.id,Date.now());
    if(recent.size>2000){const now=Date.now();for(const [id,time]of recent)if(now-time>60000)recent.delete(id);}
    const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),18000);
    try {
     const model=Deno.env.get('GEMINI_EMBEDDING_MODEL')??'gemini-embedding-001';
     const embed=async(text:string)=>{
      const response=await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:embedContent`,{
       method:'POST',signal:controller.signal,headers:{'Content-Type':'application/json','x-goog-api-key':key},
       body:JSON.stringify({model:`models/${model}`,content:{parts:[{text:text.slice(0,1200)}]},taskType:'SEMANTIC_SIMILARITY',outputDimensionality:768})});
      if(!response.ok)throw new Error('provider_unavailable');
      const json=await response.json();const vector=json.embedding?.values;
      if(!Array.isArray(vector)||vector.length!==768||!vector.every(Number.isFinite))throw new Error('invalid_embedding');
      return vector;
     };
     // Only descriptions are sent: no account IDs, names, email or verification files.
     const ownVector=await embed(seeker.description);
     const pool=rankMatches(seeker,eligible).matches.slice(0,20);let index=0;
     await Promise.all(Array.from({length:Math.min(4,pool.length)},async()=>{
      while(index<pool.length){const c=pool[index++];const value=cosine(ownVector,await embed(c.description));if(value!==null)semantic[c.user_id]=value;}
     }));
     mode='ai';notice='Shared conditions rank first. AI experience similarity breaks ties; language breaks remaining ties. This is not a prediction of support outcomes.';
     if(eligible.length>20)notice+=' AI compared the first 20 eligible candidates; all condition matches remain listed.';
    } catch {
     controller.abort();
     // No partially enhanced ranking: every provider failure falls back consistently.
     for(const id of Object.keys(semantic))delete semantic[id];
     notice='AI comparison is temporarily unavailable. Condition-based recommendations are shown.';
    } finally {clearTimeout(timer);}
   }
  }
  return reply({...rankMatches(seeker,candidates,semantic),mode,notice,
   seeker_conditions:seeker.conditions,scoring_version:'shared-count-v1'});
 }catch{return reply({error:'matching_unavailable'},500);}
});
