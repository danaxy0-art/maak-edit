// Pure, deterministic ranking. Used in production and Node tests.
export function cosine(a, b) {
 if (!Array.isArray(a)||!Array.isArray(b)||!a.length||a.length!==b.length||
 !a.every(Number.isFinite)||!b.every(Number.isFinite)) return null;
 const dot=a.reduce((s,v,i)=>s+v*b[i],0);
 const norm=Math.sqrt(a.reduce((s,v)=>s+v*v,0)*b.reduce((s,v)=>s+v*v,0));
 return norm ? Math.max(0,Math.min(1,dot/norm)) : null;
}
export function rankMatches(seeker, candidates, semantic = {}) {
 const wanted=new Map((seeker.conditions??[]).map(c=>[c.id,c.name]));
 const unique=new Map();
 for(const c of candidates??[]) {
  if(c.status!=='approved'||unique.has(c.user_id))continue;
  const ids=[...new Set((c.conditions??[]).map(v=>v.id))].filter(id=>wanted.has(id));
  if(!ids.length)continue;
  const similarity=Number.isFinite(semantic[c.user_id])?Math.max(0,Math.min(1,semantic[c.user_id])):null;
  unique.set(c.user_id,{...c, shared_conditions:ids.map(id=>({id,name:wanted.get(id)})),
   shared_count:ids.length,coverage_percent:Math.round(100*ids.length/wanted.size),
   experience_similarity:similarity,same_language:c.language===seeker.language});
 }
 const ranked=[...unique.values()].sort((a,b)=> b.shared_count-a.shared_count ||
 (b.experience_similarity??0)-(a.experience_similarity??0) ||
 Number(b.same_language)-Number(a.same_language) || a.user_id.localeCompare(b.user_id));
 // Greedy complementary coverage, independently of the ranking list.
 const uncovered=new Set(wanted.keys()); const team=[];const remaining=[...ranked];
 while(uncovered.size&&remaining.length) {
  remaining.sort((a,b)=>b.shared_conditions.filter(c=>uncovered.has(c.id)).length-
   a.shared_conditions.filter(c=>uncovered.has(c.id)).length||ranked.indexOf(a)-ranked.indexOf(b));
  const best=remaining.shift();const adds=best.shared_conditions.filter(c=>uncovered.has(c.id));
  if(!adds.length)break;
  team.push({user_id:best.user_id,covers:adds});adds.forEach(c=>uncovered.delete(c.id));
 }
 return {matches:ranked,complementary:team,uncovered_conditions:[...uncovered].map(id=>({id,name:wanted.get(id)}))};
}

export function generalSuggestions(seeker,candidates) {
 const seen=new Set();
 const matches=(candidates??[]).filter(c=>c.status==='approved'&&!seen.has(c.user_id)&&seen.add(c.user_id)).map(c=>({...c,shared_conditions:[],shared_count:0,coverage_percent:null,experience_similarity:null,same_language:c.language===seeker.language})).sort((a,b)=>Number(b.same_language)-Number(a.same_language)||a.user_id.localeCompare(b.user_id));
 return {matches,complementary:[],uncovered_conditions:[]};
}
