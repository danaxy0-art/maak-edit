// coturn TURN REST credentials. Master secret stays server-side.
import {createClient} from 'npm:@supabase/supabase-js@2';
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
const reply=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers});
Deno.serve(async(req)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers});
 if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
 try {
  const token=req.headers.get('Authorization')??'';
  const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:token}},auth:{persistSession:false}});
  const {data:{user},error}=await client.auth.getUser();
  if(error||!user)return reply({error:'sign_in_required'},401);
  const {request_id}=await req.json();
  const {data:allowed,error:checkError}=await client.rpc('can_send_maak_message',{p_request_id:request_id});
  if(checkError||allowed!==true)return reply({error:'conversation_unavailable'},403);
  const secret=Deno.env.get('VOICE_TURN_SECRET');
  const urls=(Deno.env.get('VOICE_TURN_URLS')??'').split(',').map(s=>s.trim()).filter(Boolean);
  if(!secret||urls.length===0)return reply({error:'turn_not_configured'},503);
  const username=`${Math.floor(Date.now()/1000)+3600}:${user.id}`;
  const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-1'},false,['sign']);
  const signature=new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(username)));
  const credential=btoa(String.fromCharCode(...signature));
  return reply({iceServers:[{urls:'stun:stun.l.google.com:19302'},{urls,username,credential}]});
 }catch{return reply({error:'ice_configuration_unavailable'},500);}
});
