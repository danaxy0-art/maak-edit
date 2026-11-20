const headers = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
const reply=(data,status=200)=>new Response(JSON.stringify(data),{status,headers});
export function createEmailCheckHandler({check,clientHash}) {
 return async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers});
  if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
  try {
   const text=await req.text();if(text.length>1024)return reply({error:'invalid_email'},400);
   let input;try{input=JSON.parse(text);}catch{return reply({error:'invalid_email'},400);}
   const email=typeof input?.email==='string'?input.email.trim().toLowerCase():'';
   if(email.length>254||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))return reply({error:'invalid_email'},400);
   const result=await check(email,await clientHash(req));
   if(result.error)return reply({error:'check_unavailable'},503);
   if(result.data?.limited===true)return reply({error:'too_many_checks'},429);
   if(typeof result.data?.exists!=='boolean')return reply({error:'check_unavailable'},503);
   // Never return identifiers, role, profile, or authentication records.
   return reply({exists:result.data.exists});
  }catch{return reply({error:'check_unavailable'},503);}
 };
}
