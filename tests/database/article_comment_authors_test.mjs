// Checks for supabase/migrations/20261128020000_article_comment_authors.sql:
// comments stay when the author's account is deleted, and comments from
// deleted or deactivated (blocked) accounts are labelled as such.
// Run: cd tests/database && npm install && node article_comment_authors_test.mjs
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const base=fileURLToPath(new URL('../../',import.meta.url));
const read=f=>readFileSync(base+f,'utf8');
const migration=read('supabase/migrations/20261126000000_article_management_comments.sql');
const authors=read('supabase/migrations/20261128020000_article_comment_authors.sql');
const rollback=read('supabase/rollbacks/20261128020000_article_comment_authors_rollback.sql');

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
 await db.exec(migration);
 await db.exec(authors);
 await db.exec(authors); // repeatable
 return db;
}


const ids={admin:'30000000-0000-0000-0000-000000000001',s1:'30000000-0000-0000-0000-000000000002',s2:'30000000-0000-0000-0000-000000000003',
 v1:'30000000-0000-0000-0000-000000000004'};
let n=0;async function check(label,f){await f();n++;console.log('PASS',label);}

const db=await setup({production:false});
const names={admin:'Admin',s1:'Sara Seeker',s2:'Omar Seeker',v1:'Vera Volunteer'};
for(const [k,id] of Object.entries(ids))await db.query('insert into auth.users(id,raw_user_meta_data) values($1,$2)',[id,JSON.stringify({full_name:names[k],role:k[0]==='v'?'volunteer':'help_seeker'})]);
await db.query(`update profiles set role='admin' where id=$1`,[ids.admin]);
await db.query("insert into help_seeker_profiles(user_id,chronic_condition,preferred_language) values($1,'Diabetes','English'),($2,'Diabetes','English')",[ids.s1,ids.s2]);
await db.query("insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'Diabetes','English','x','approved')",[ids.v1]);
const typeId=(await db.query("select id from chronic_conditions where name='Diabetes'")).rows[0].id;
async function as(name){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[name]??'']);if(name)await db.exec('set role authenticated');}
const add=(who,body,replyTo=null)=>as(who).then(()=>db.query('select add_article_comment($1,$2,$3) id',[art,body,replyTo])).then(r=>r.rows[0].id);
const list=async(who)=>{await as(who);return Object.fromEntries((await db.query('select * from get_article_comments($1)',[art])).rows.map(r=>[r.id,r]));};

await as('admin');
const art=(await db.query("select admin_save_article(null,'Living well with diabetes','A short practical summary.','Long article content that is clearly over twenty characters.',$1,'WHO','https://www.who.int/diabetes',null,'published') id",[typeId])).rows[0].id;
const c1=await add('s1','Very helpful, thank you!');
const r1=await add('v1','Glad it helped. Try walking after meals.',c1);
const r2=await add('s2','Same here!',r1);

await check('AUTH-01 active authors: name, role, user id and status "active"',async()=>{const c=await list('s2');assert.equal(c[r1].author_name,'Vera Volunteer');assert.equal(c[r1].author_role,'volunteer');assert.equal(c[r1].user_id,ids.v1);assert.equal(c[r1].author_status,'active');assert.equal(c[r2].reply_to_name,'Vera Volunteer');assert.equal(c[r2].is_mine,true);});

await check('AUTH-02 deactivated (blocked) author: "[deactivated account]", text kept, no profile link',async()=>{await as('');await db.query("insert into account_blocks(user_id,reason,blocked_by) values($1,'spam',$2)",[ids.v1,ids.admin]);const c=await list('s1');assert.equal(c[r1].author_status,'deactivated');assert.equal(c[r1].author_name,'[deactivated account]');assert.equal(c[r1].body,'Glad it helped. Try walking after meals.');assert.equal(c[r1].user_id,null);assert.equal(c[r1].author_role,null);assert.equal(c[r1].is_deleted,false);assert.equal(c[r2].reply_to_name,'[deactivated account]');await as('');await db.query('delete from account_blocks where user_id=$1',[ids.v1]);assert.equal((await list('s1'))[r1].author_name,'Vera Volunteer');});

await check('AUTH-03 deleting the account keeps the comment and its replies',async()=>{await as('');await db.query('delete from auth.users where id=$1',[ids.v1]);const left=(await db.query('select id,user_id,body from article_comments where id=any($1)',[[c1,r1,r2]])).rows;assert.equal(left.length,3);assert.equal(left.find(r=>r.id===r1).user_id,null);});

await check('AUTH-04 deleted author: "[deleted account]", text kept, no profile link',async()=>{const c=await list('s1');assert.equal(c[r1].author_status,'deleted');assert.equal(c[r1].author_name,'[deleted account]');assert.equal(c[r1].body,'Glad it helped. Try walking after meals.');assert.equal(c[r1].user_id,null);assert.equal(c[r1].author_role,null);assert.equal(c[r1].is_mine,false);assert.equal(c[r2].reply_to_name,'[deleted account]');assert.equal(c[c1].author_name,'Sara Seeker');});

await check('AUTH-05 replying to a deleted account\'s comment works and notifies nobody',async()=>{await as('');const before=(await db.query("select count(*)::int n from notifications where kind='article_reply'")).rows[0].n;const r3=await add('s1','Thanks to whoever wrote this.',r1);assert.ok(r3);await as('');assert.equal((await db.query("select count(*)::int n from notifications where kind='article_reply'")).rows[0].n,before);});

await check('AUTH-06 an admin can still remove a deleted account\'s comment',async()=>{await as('admin');await db.query('select delete_article_comment($1)',[r1]);const c=await list('s1');assert.equal(c[r1].is_deleted,true);assert.equal(c[r1].body,'');assert.equal(c[r1].author_name,null);});

await check('AUTH-07 a comment the author deleted is unchanged: no text, no name',async()=>{await as('s1');await db.query('select delete_article_comment($1)',[c1]);const c=await list('s2');assert.equal(c[c1].is_deleted,true);assert.equal(c[c1].author_name,null);assert.equal(c[c1].user_id,null);assert.equal(c[c1].author_status,'active');});

await check('AUTH-08 rollback restores the cascade and removes author-less comments',async()=>{await as('');await db.exec(rollback);assert.equal((await db.query('select count(*)::int n from article_comments where user_id is null')).rows[0].n,0);const nn=(await db.query("select is_nullable from information_schema.columns where table_name='article_comments' and column_name='user_id'")).rows[0].is_nullable;assert.equal(nn,'NO');await db.exec(authors);});

console.log(`\nAll ${n} checks passed.`);
