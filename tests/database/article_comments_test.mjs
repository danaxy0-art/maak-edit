// Checks for supabase/migrations/20261126000000_article_management_comments.sql:
// admin article management, member comments/replies and reply notifications.
// Run: cd tests/database && npm install && node article_comments_test.mjs
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const base=fileURLToPath(new URL('../../',import.meta.url));
const read=f=>readFileSync(base+f,'utf8');
const migration=read('supabase/migrations/20261126000000_article_management_comments.sql');
// The first delivered version (articles tagged with illness_types), to check
// that re-running the current file upgrades it. Optional: set PREV_MIGRATION.
const previous=process.env.PREV_MIGRATION?readFileSync(process.env.PREV_MIGRATION,'utf8'):null;
const rollback=read('supabase/rollbacks/20261126000000_article_management_comments_rollback.sql');

async function setup({production}){
 const db=new PGlite();
 await db.exec(read('tests/database/account_blocking/00_supabase_stub.sql').replace(/^\\.*$/gm,''));
 await db.exec('alter table storage.objects add column metadata jsonb; grant delete on storage.objects to authenticated;');
 await db.exec(read('supabase_schema.sql').replace('create extension if not exists pgcrypto;',''));
 for(const f of ['20261018_matching.sql','20261018_condition_reviews.sql','20261021090000_chat_reads_remove_booking.sql']) await db.exec(read('supabase/migrations/'+f));
 await db.exec('alter table public.support_requests add column restricted_at timestamptz;');
 await db.exec(read('supabase/migrations/20261021_account_blocking.sql'));
 await db.exec(`create schema vault; create schema net;
  create table vault.decrypted_secrets(name text primary key, decrypted_secret text);
  insert into vault.decrypted_secrets values('maak_project_url','https://ref.supabase.co'),('maak_push_secret','s');
  create table net.calls(id serial, body jsonb);
  create function net.http_post(url text, body jsonb, params jsonb default '{}', headers jsonb default '{}', timeout_milliseconds int default 5000)
   returns bigint language sql as $$ insert into net.calls(body) values(body) returning id::bigint $$;`);
 await db.exec(read('supabase/migrations/20261106000000_push_notifications.sql').replace('create extension if not exists pg_net with schema extensions;',''));
 if(production){
  // Approximates the live Health Library: tables made outside the repo, with
  // their own policies, a like-count RPC and foreign keys WITHOUT cascade.
  await db.exec(`
   create table public.illness_types(id uuid primary key default gen_random_uuid(), name text not null);
   -- Stricter than the app needs, like some live copies: NOT NULL on optional
   -- fields (error 23502 on save before the fix) and an extra required column.
   create table public.articles(id uuid primary key default gen_random_uuid(), title text not null, summary text,
    content text, illness_type_id uuid not null references illness_types(id), source_name text not null, source_url text, image_url text,
    status text default 'draft', published_at timestamptz not null default now(), created_at timestamptz default now(), updated_at timestamptz default now(),
    author text not null);
   create table public.article_likes(user_id uuid references auth.users(id), article_id uuid references articles(id), primary key(user_id,article_id));
   create table public.saved_articles(user_id uuid references auth.users(id), article_id uuid references articles(id), primary key(user_id,article_id));
   alter table articles enable row level security; create policy prod_read on articles for select to authenticated using(status='published');
   alter table illness_types enable row level security; create policy prod_types on illness_types for select to authenticated using(true);
   alter table article_likes enable row level security; create policy prod_likes on article_likes for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
   alter table saved_articles enable row level security; create policy prod_saves on saved_articles for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
   grant select on articles, illness_types to authenticated; grant select,insert,delete on article_likes, saved_articles to authenticated;
   create function public.health_article_like_counts() returns table(article_id uuid, like_count integer) language sql security definer as
    $$ select article_id, count(*)::int from article_likes group by article_id $$;
   grant execute on function public.health_article_like_counts() to authenticated;
   insert into illness_types(name) values('diabetes'),('Migraine');
   insert into articles(title,summary,content,illness_type_id,status,source_name,author) select 'Legacy diabetes','s','c',id,'published','WHO','x' from illness_types where name='diabetes';
   insert into articles(title,summary,content,illness_type_id,status,source_name,author) select 'Legacy migraine','s','c',id,'published','WHO','x' from illness_types where name='Migraine';`);
 }
 if(previous&&production)await db.exec(previous);
 await db.exec(migration);
 await db.exec(migration); // repeatable
 return db;
}

const ids={admin:'30000000-0000-0000-0000-000000000001',s1:'30000000-0000-0000-0000-000000000002',s2:'30000000-0000-0000-0000-000000000003',
 v1:'30000000-0000-0000-0000-000000000004',pend:'30000000-0000-0000-0000-000000000005'};
let n=0;async function check(label,f){await f();n++;console.log('PASS',label);}
const rejects=async(f,msg)=>assert.rejects(f,e=>new RegExp(msg).test(e.message),`expected ${msg}`);

for(const production of [true,false]){
 console.log(`--- ${production?'existing (production-like)':'fresh'} Health Library tables`);
 const db=await setup({production});
 const names={admin:'Admin',s1:'Sara Seeker',s2:'Omar Seeker',v1:'Vera Volunteer',pend:'Pending Vol'};
 for(const [k,id] of Object.entries(ids))await db.query('insert into auth.users(id,raw_user_meta_data) values($1,$2)',[id,JSON.stringify({full_name:names[k],role:k[0]==='v'||k==='pend'?'volunteer':'help_seeker'})]);
 await db.query(`update profiles set role='admin' where id=$1`,[ids.admin]);
 await db.query("insert into help_seeker_profiles(user_id,chronic_condition,preferred_language) values($1,'Diabetes','English'),($2,'Diabetes','English')",[ids.s1,ids.s2]);
 await db.query("insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'Diabetes','English','x','approved'),($2,'Diabetes','English','x','pending_review')",[ids.v1,ids.pend]);
 await db.query("insert into device_tokens(token,user_id) values($1,$2)",['tok-s1'.padEnd(30,'x'),ids.s1]);
 const typeId=(await db.query("select id from chronic_conditions where name='Diabetes'")).rows[0].id;
 const otherId=(await db.query("select id from chronic_conditions where is_other")).rows[0].id;
 const inactiveId=(await db.query("insert into chronic_conditions(name,is_active) values('Retired condition',false) returning id")).rows[0].id;
 if(production){
  await check('COND-01 earlier illness_types tags move to the matching condition',async()=>{await as('');const r=Object.fromEntries((await db.query("select title,condition_id from articles where title like 'Legacy%'")).rows.map(x=>[x.title,x.condition_id]));assert.equal(r['Legacy diabetes'],typeId);assert.equal(r['Legacy migraine'],null);await db.query("delete from articles where title like 'Legacy%'");});
 }
 async function as(name){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[name]??'']);if(name)await db.exec('set role authenticated');}
 const save=(p)=>db.query('select admin_save_article($1,$2,$3,$4,$5,$6,$7,$8,$9) id',[p.id??null,p.title??'Living well with diabetes',
  p.summary??'A short practical summary.',p.content??'Long article content that is clearly over twenty characters.',p.type??typeId,
  p.sourceName??'WHO',p.url??'https://www.who.int/diabetes',p.image??null,p.status??'published']);
 const notes=async(who)=>{await as('');return (await db.query("select title,body,kind,reference_id from notifications where user_id=$1 and kind='article_reply' order by created_at",[ids[who]])).rows;};

 let art,draft;
 await check('ART-01 admin creates a published article; published_at is set',async()=>{await as('admin');art=(await save({})).rows[0].id;await as('');const r=(await db.query('select status,published_at from articles where id=$1',[art])).rows[0];assert.equal(r.status,'published');assert.ok(r.published_at);});
 await check('ART-02 admin creates a draft without a source',async()=>{await as('admin');draft=(await save({title:'Draft piece',status:'draft',sourceName:'',url:''})).rows[0].id;assert.ok(draft);});
 await check('ART-03 validation: title, summary, content, url, status, source, condition',async()=>{await as('admin');
  await rejects(()=>save({title:'ab'}),'invalid_article_title');
  await rejects(()=>save({summary:'short'}),'invalid_article_summary');
  await rejects(()=>save({content:'too short'}),'invalid_article_content');
  await rejects(()=>save({url:'javascript:alert(1)'}),'invalid_article_url');
  await rejects(()=>save({image:'http://insecure.example.com/a.png'}),'invalid_article_image');
  await rejects(()=>save({status:'archived'}),'invalid_article_status');
  await rejects(()=>save({sourceName:'',url:''}),'article_source_required');
  await rejects(()=>save({type:'30000000-0000-0000-0000-0000000000ff'}),'invalid_article_condition');
  await rejects(()=>save({type:otherId}),'invalid_article_condition');
  await rejects(()=>save({type:inactiveId}),'invalid_article_condition');});
 await check('COND-02 an article keeps a condition deactivated after tagging',async()=>{await as('admin');const id=(await save({title:'Keeps its tag'})).rows[0].id;await as('');await db.query('update articles set condition_id=$1 where id=$2',[inactiveId,id]);await as('admin');await save({id,title:'Keeps its tag (edited)',type:inactiveId});await db.query('select admin_delete_article($1)',[id]);});
 await check('ART-04 members cannot use admin article RPCs',async()=>{for(const who of ['s1','v1']){await as(who);await rejects(()=>save({}),'not_allowed');await rejects(()=>db.query('select * from admin_list_articles()'),'not_allowed');await rejects(()=>db.query('select admin_delete_article($1)',[art]),'not_allowed');}});
 await check('ART-05 admin list includes drafts with condition name and counts',async()=>{await as('admin');const rows=(await db.query('select * from admin_list_articles()')).rows;assert.equal(rows.length,2);const a=rows.find(r=>r.id===art);assert.equal(a.condition_name,'Diabetes');assert.equal(a.condition_id,typeId);assert.equal(Number(a.comment_count),0);});
 await check('ART-06 readers see only published articles',async()=>{await as('s1');const rows=(await db.query('select id from articles')).rows.map(r=>r.id);assert.deepEqual(rows,[art]);});
 await check('ART-07 edit keeps the first published_at; unpublish hides it from readers',async()=>{await as('');const before=(await db.query('select published_at from articles where id=$1',[art])).rows[0].published_at;await as('admin');await save({id:art,title:'Living well with diabetes (updated)',status:'draft'});await save({id:art,status:'published'});await as('');const r=(await db.query('select title,published_at from articles where id=$1',[art])).rows[0];assert.equal(r.title,'Living well with diabetes');assert.equal(+r.published_at,+before);await as('admin');await save({id:art,title:'Living well with diabetes (updated)'});});
 await check('ART-08 editing a missing article fails',async()=>{await as('admin');await rejects(()=>save({id:'30000000-0000-0000-0000-0000000000aa'}),'article_unavailable');});

 // Comments
 let c1,r1,r2;
 await check('COM-01 help seeker comments on a published article',async()=>{await as('s1');c1=(await db.query('select add_article_comment($1,$2) id',[art,'  Very helpful, thank you!  '])).rows[0].id;await as('');assert.equal((await db.query('select body from article_comments where id=$1',[c1])).rows[0].body,'Very helpful, thank you!');});
 await check('COM-02 approved volunteer replies; comment author is notified (and pushed)',async()=>{await as('v1');r1=(await db.query('select add_article_comment($1,$2,$3) id',[art,'Glad it helped. Try walking after meals.',c1])).rows[0].id;const ns=await notes('s1');assert.equal(ns.length,1);assert.equal(ns[0].title,'Vera Volunteer replied on "Living well with diabetes (updated)"');assert.equal(ns[0].body,'Glad it helped. Try walking after meals.');assert.equal(ns[0].reference_id,art);await as('');const push=(await db.query("select body from net.calls where body->>'kind'='article_reply'")).rows;assert.equal(push.length,1);});
 await check('COM-03 a reply to a reply joins the thread and notifies the replied-to author',async()=>{await as('s2');r2=(await db.query('select add_article_comment($1,$2,$3) id',[art,'Same here!',r1])).rows[0].id;await as('');const r=(await db.query('select parent_id,reply_to_id from article_comments where id=$1',[r2])).rows[0];assert.equal(r.parent_id,c1);assert.equal(r.reply_to_id,r1);assert.equal((await notes('v1')).length,1);assert.equal((await notes('s1')).length,1);});
 await check('COM-04 replying to your own comment sends no notification',async()=>{await as('s1');await db.query('select add_article_comment($1,$2,$3)',[art,'Adding one more thought.',c1]);assert.equal((await notes('s1')).length,1);});
 await check('COM-05 pending volunteer, admin and signed-out users cannot comment',async()=>{await as('pend');await rejects(()=>db.query('select add_article_comment($1,$2)',[art,'Hi']),'comment_not_allowed');await as('admin');await rejects(()=>db.query('select add_article_comment($1,$2)',[art,'Hi']),'comment_not_allowed');await as('');await db.exec('set role anon');await assert.rejects(()=>db.query('select add_article_comment($1,$2)',[art,'Hi']));});
 await check('COM-06 empty, too long, draft article and foreign reply target are rejected',async()=>{await as('s2');await rejects(()=>db.query('select add_article_comment($1,$2)',[art,'   ']),'invalid_comment');await rejects(()=>db.query('select add_article_comment($1,$2)',[art,'x'.repeat(1001)]),'invalid_comment');await rejects(()=>db.query('select add_article_comment($1,$2)',[draft,'Hi']),'article_unavailable');await as('admin');const other=(await save({title:'Another article'})).rows[0].id;await as('s2');await rejects(()=>db.query('select add_article_comment($1,$2,$3)',[other,'Hi',c1]),'comment_unavailable');});
 await check('COM-07 restricted account cannot comment',async()=>{await as('');await db.query("insert into account_blocks(user_id,reason,blocked_by) values($1,'spam',$2)",[ids.s2,ids.admin]);await as('s2');await rejects(()=>db.query('select add_article_comment($1,$2)',[art,'Hi']),'comment_not_allowed');await as('');await db.query('delete from account_blocks where user_id=$1',[ids.s2]);});
 await check('COM-08 at most 5 comments per minute',async()=>{await as('v1');for(let i=0;i<4;i++)await db.query('select add_article_comment($1,$2)',[art,'Tip '+i]);await rejects(()=>db.query('select add_article_comment($1,$2)',[art,'One too many']),'comment_rate_limited');await as('');await db.query(`update article_comments set created_at=created_at-interval '2 minutes' where user_id=$1`,[ids.v1]);});
 await check('COM-09 members read comments with author names/roles, never the table directly',async()=>{await as('s2');const rows=(await db.query('select * from get_article_comments($1)',[art])).rows;assert.ok(rows.length>=3);const reply=rows.find(r=>r.id===r2);assert.equal(reply.author_name,'Omar Seeker');assert.equal(reply.author_role,'help_seeker');assert.equal(reply.reply_to_name,'Vera Volunteer');assert.equal(reply.is_mine,true);assert.equal(rows.find(r=>r.id===r1).author_role,'volunteer');await assert.rejects(()=>db.query('select * from article_comments'));await assert.rejects(()=>db.query("insert into article_comments(article_id,user_id,body) values($1,$2,'x')",[art,ids.s2]));await rejects(()=>db.query('select * from get_article_comments($1)',[draft]),'article_unavailable');await as('pend');await rejects(()=>db.query('select * from get_article_comments($1)',[art]),'comment_not_allowed');});
 await check('COM-10 comment counts for readers',async()=>{await as('s1');const rows=(await db.query('select * from health_article_comment_counts()')).rows;assert.equal(rows.length,1);assert.ok(Number(rows[0].comment_count)>=3);});
 await check('COM-11 members delete only their own comments; a reply with no replies disappears',async()=>{await as('s1');await rejects(()=>db.query('select delete_article_comment($1)',[r1]),'comment_not_allowed');await as('s2');await db.query('select delete_article_comment($1)',[r2]);await as('');assert.equal((await db.query('select count(*)::int n from article_comments where id=$1',[r2])).rows[0].n,0);});
 await check('COM-12 a comment with replies becomes "deleted" and keeps its replies',async()=>{await as('s1');await db.query('select delete_article_comment($1)',[c1]);await as('s2');const rows=(await db.query('select * from get_article_comments($1)',[art])).rows;const t=rows.find(r=>r.id===c1);assert.equal(t.is_deleted,true);assert.equal(t.body,'');assert.equal(t.author_name,null);assert.equal(t.user_id,null);assert.equal(t.is_mine,false);assert.ok(rows.some(r=>r.id===r1&&!r.is_deleted));
  await as('s2');await rejects(()=>db.query('select add_article_comment($1,$2,$3)',[art,'Hi',c1]),'comment_unavailable');await as('s1');await rejects(()=>db.query('select delete_article_comment($1)',[c1]),'comment_unavailable');
  await as('s1');const counts=(await db.query('select * from health_article_comment_counts()')).rows;const total=(await db.query('select * from get_article_comments($1)',[art])).rows.filter(r=>!r.is_deleted).length;assert.equal(Number(counts[0].comment_count),total);});
 await check('COM-13 a reply someone answered keeps its place; "Replying to" hides the deleted name',async()=>{await as('s2');const a=(await db.query('select add_article_comment($1,$2,$3) id',[art,'Answering Vera',r1])).rows[0].id;await as('v1');await db.query('select delete_article_comment($1)',[r1]);await as('s2');const rows=(await db.query('select * from get_article_comments($1)',[art])).rows;assert.equal(rows.find(r=>r.id===r1).is_deleted,true);assert.equal(rows.find(r=>r.id===a).reply_to_name,null);
  // Last real reply goes: the deleted placeholders it held up go too.
  await as('');for(const row of (await db.query("select id,user_id from article_comments where parent_id=$1 and deleted_at is null",[c1])).rows){await db.query("select set_config('request.jwt.claim.sub',$1,false)",[row.user_id]);await db.exec('set role authenticated');await db.query('select delete_article_comment($1)',[row.id]);await db.exec('reset role');}
  assert.equal((await db.query('select count(*)::int n from article_comments where id=$1 or parent_id=$1',[c1])).rows[0].n,0);});
 await check('COM-14 admin deletes any comment; admin sees comments on drafts',async()=>{await as('s1');const c=(await db.query('select add_article_comment($1,$2) id',[art,'Spam'])).rows[0].id;await as('admin');assert.ok((await db.query('select * from get_article_comments($1)',[art])).rows.length>0);await db.query('select delete_article_comment($1)',[c]);await as('');assert.equal((await db.query('select count(*)::int n from article_comments where id=$1',[c])).rows[0].n,0);});
 await check('ART-10 admin publishes / unpublishes without editing',async()=>{await as('admin');const d=(await save({title:'Quick toggle',status:'draft',sourceName:'',url:''})).rows[0].id;await rejects(()=>db.query('select admin_set_article_status($1,$2)',[d,'published']),'article_source_required');await save({id:d,title:'Quick toggle',status:'draft'});await db.query('select admin_set_article_status($1,$2)',[d,'published']);await as('');const r=(await db.query('select status,published_at from articles where id=$1',[d])).rows[0];assert.equal(r.status,'published');assert.ok(r.published_at);await as('admin');await db.query('select admin_set_article_status($1,$2)',[d,'draft']);await rejects(()=>db.query('select admin_set_article_status($1,$2)',[d,'archived']),'invalid_article_status');await as('s1');await rejects(()=>db.query('select admin_set_article_status($1,$2)',[d,'published']),'not_allowed');await as('admin');await db.query('select admin_delete_article($1)',[d]);});
 await check('ART-09 admin deletes an article with likes, saves and comments',async()=>{await as('s1');await db.query('insert into article_likes(user_id,article_id) values($1,$2)',[ids.s1,art]);await db.query('insert into saved_articles(user_id,article_id) values($1,$2)',[ids.s1,art]);await db.query('select add_article_comment($1,$2)',[art,'Bye']);await as('admin');await db.query('select admin_delete_article($1)',[art]);await as('');for(const t of ['articles','article_likes','saved_articles','article_comments'])assert.equal((await db.query(`select count(*)::int n from ${t} where ${t==='articles'?'id':'article_id'}=$1`,[art])).rows[0].n,0);await as('admin');await rejects(()=>db.query('select admin_delete_article($1)',[art]),'article_unavailable');});
 await check('ROLL-01 rollback removes comments and keeps articles; migration re-applies',async()=>{await as('');await db.exec(rollback);assert.equal((await db.query("select to_regclass('public.article_comments') t")).rows[0].t,null);assert.ok((await db.query('select count(*)::int n from articles')).rows[0].n>=1);await db.exec(migration);assert.ok((await db.query("select to_regclass('public.article_comments') t")).rows[0].t);});
}
console.log(`\n${n} checks passed`);
