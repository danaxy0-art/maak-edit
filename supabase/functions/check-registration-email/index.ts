import {createClient} from 'npm:@supabase/supabase-js@2';
import {createEmailCheckHandler} from './handler.mjs';
const secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const client=createClient(Deno.env.get('SUPABASE_URL')!,secret,{auth:{persistSession:false,autoRefreshToken:false}});
Deno.serve(createEmailCheckHandler({
 check:(email:string,hash:string)=>client.rpc('check_maak_registration_email',{p_email:email,p_client_hash:hash}),
 clientHash:async(req:Request)=>{
  const ip=req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()??'unknown';
  const bytes=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(secret+':registration:'+ip));
  return Array.from(new Uint8Array(bytes),b=>b.toString(16).padStart(2,'0')).join('');
 }
}));
