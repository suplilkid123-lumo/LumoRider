const {PGlite} = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
import fs from 'node:fs';
const db=new PGlite(); await db.waitReady;
await db.exec(`create role anon; create role authenticated; create role service_role bypassrls; create role supabase_admin superuser; create role authenticator; create schema auth; create schema extensions; create schema storage;
create function auth.jwt() returns jsonb language sql stable as $$ select nullif(current_setting('request.jwt.claims',true),'')::jsonb $$;
create function auth.role() returns text language sql stable as $$ select auth.jwt()->>'role' $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub','')::uuid $$;
create table auth.users(id uuid primary key);
create table storage.buckets(id text primary key,name text,public boolean);
create table storage.objects(id uuid primary key,bucket_id text,name text,owner uuid);
grant usage on schema auth to public; grant execute on all functions in schema auth to public;`);
const schemaPath=process.argv[2];
const backendRoot=process.argv[3];
const remainingOnly=process.argv[4] === '--remaining-only';
const testPayment=process.argv[4] === '--test-payment';
const approval=process.argv[4] === '--approval';
const cashLifecycle=process.argv[4] === '--cash-lifecycle';
const paymentDispatch=process.argv[4] === '--payment-dispatch';
if(!schemaPath || !backendRoot) throw new Error('Usage: node run.mjs <schema-snapshot.sql> <backend-root>');
const s=fs.readFileSync(schemaPath,'utf8');
function split(sql){let parts=[],start=0,quote=null,dollar=null;for(let i=0;i<sql.length;i++){if(dollar){if(sql.startsWith(dollar,i)){i+=dollar.length-1;dollar=null;}continue;}if(quote){if(sql[i]===quote){if(sql[i+1]===quote)i++;else quote=null;}continue;}if(sql.startsWith('--',i)){const n=sql.indexOf('\n',i);i=n<0?sql.length:n;continue;}if(sql[i]==="'"||sql[i]==='"'){quote=sql[i];continue;}const m=sql.slice(i).match(/^\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$/);if(m){dollar=m[0];i+=dollar.length-1;continue;}if(sql[i]===';'){parts.push(sql.slice(start,i+1));start=i+1;}}return parts;}
const errors=[];for(const statement of split(s)){try{await db.exec(statement)}catch(e){errors.push({sql:statement.trim().slice(0,160),error:e.message})}}
if(errors.length) throw new Error(JSON.stringify(errors));
console.log('PASS: schema snapshot restored without errors');
if (approval) {
  const verificationSQL=fs.readFileSync(backendRoot+'/supabase/migrations/20260822090000_driver_verification_phase1.sql','utf8');
  await db.exec(verificationSQL.match(/insert into public\.driver_verification_requirements[\s\S]*?;/i)[0]);
  await db.exec('insert into public.driver_verification_settings(singleton) values(true);');
  await db.exec('set row_security=on;');
  await db.exec('alter table auth.users add column instance_id uuid, add column aud text, add column role text, add column email text, add column encrypted_password text, add column email_confirmed_at timestamptz, add column created_at timestamptz, add column updated_at timestamptz;');
  await db.exec(fs.readFileSync(backendRoot+'/supabase/migrations/20261029010000_admin_list_driver_applications.sql','utf8'));
  try { await db.exec(fs.readFileSync(backendRoot+'/supabase/tests/admin_driver_approval_workflow.sql','utf8')); }
  catch(e) { console.error('APPROVAL FAIL',e.message,e.where); await db.close(); process.exit(1); }
  console.log('PASS: existing admin account/vehicle approval security and preservation regression');
  try { await db.exec(fs.readFileSync(new URL('./registration.sql',import.meta.url),'utf8')); }
  catch(e) { console.error('REGISTRATION FAIL',e.message,e.where); await db.close(); process.exit(1); }
  console.log('PASS: registration → pending admin listing → rejection; retries preserve account; unapproved online and nonadmin listing denied');
  await db.close();
  process.exit(0);
}
if (!remainingOnly && !testPayment) {
const missing=(await db.query("select to_regproc('public.create_passenger_fare_quote_v1') as quote, to_regproc('public.create_passenger_ride_for_payment_v1') as ride")).rows[0];
console.log('BASELINE booking contract:',JSON.stringify(missing));
if(!missing.quote || !missing.ride) console.log('BLOCKED on snapshot: checkout cannot create a ride through its required RPCs');
if (!missing.quote) {
  try {
    await db.query("select public.create_passenger_fare_quote_v1(gen_random_uuid(),41.878,-87.6298,41.885,-87.62,'STANDARD',1)");
    throw new Error('Expected the missing checkout RPC to fail');
  } catch (error) {
    if (error.code !== '42883') throw error;
    console.log('REPRODUCED: checkout fails before ride INSERT (undefined function 42883)');
  }
}
console.log('Snapshot push support:', (await db.query("select to_regclass('public.passenger_ride_offer_notification_events') as queue, to_regproc('public.claim_passenger_ride_offer_notification_v1') as claim")).rows[0]);
}
// The following compatibility setup is TEST ONLY. It is not a deployment bundle.
// Load real deferred SQL, including its required party-size and terminal helpers.
const party=fs.readFileSync(backendRoot+'/supabase/deferred_migrations/20260823-20260824/20260823210000_authoritative_passenger_party_size.sql','utf8');
await db.exec(party.slice(party.indexOf('create table public.passenger_party_size_rules'),party.indexOf('create or replace function public.get_passenger_party_size_rules_v1')));
await db.exec('alter table public.rides add column if not exists client_request_id uuid; create unique index if not exists rides_rider_client_request_unique on public.rides(rider_id,client_request_id) where client_request_id is not null;');
const cancellation=fs.readFileSync(backendRoot+'/supabase/deferred_migrations/20260823-20260824/20260824000000_authoritative_ride_cancellation.sql','utf8');
await db.exec(cancellation.match(/create or replace function public\.passenger_ride_cancellation_terminal_v1[\s\S]*?\$\$;/i)[0]);
for(const file of ['20260824010000_authoritative_passenger_pricing.sql','20260824020000_authoritative_passenger_payments.sql']) {
try {await db.exec(fs.readFileSync(backendRoot+'/supabase/deferred_migrations/20260823-20260824/'+file,'utf8'));console.log('loaded',file)} catch(e) {throw new Error('Migration failed: '+file+': '+e.message);}}
if (testPayment || cashLifecycle) {
  const accountSQL=fs.readFileSync(backendRoot+'/supabase/deferred_migrations/20260823-20260824/20260823090000_driver_account_eligibility.sql','utf8');
  for (const name of ['driver_account_operational_v1','driver_account_current_operational_v1']) {
    await db.exec(accountSQL.match(new RegExp('create or replace function public\\.'+name+'[\\s\\S]*?\\$\\$;', 'i'))[0]);
  }
  // Snapshot predates the vehicle snapshot columns consumed by trip execution.
  await db.exec('alter table public.rides add column if not exists driver_vehicle_id uuid; alter table public.rides add column if not exists driver_vehicle_snapshot jsonb;');
  const tripSQL=fs.readFileSync(backendRoot+'/supabase/deferred_migrations/20260823-20260824/20260824030000_authoritative_trip_execution.sql','utf8');
  await db.exec(tripSQL.replace('add column driver_speed_mps', 'add column if not exists driver_speed_mps'));
  if (testPayment) {
    await db.exec("set jiylo.local_test_install='isolated-only'");
    await db.exec(fs.readFileSync(new URL('../../supabase/local-only/test-payment.sql',import.meta.url),'utf8'));
  }
  console.log('Loaded authoritative trip execution dependencies');
}
try {
  const fixture = paymentDispatch ? './payment_dispatch.sql' : cashLifecycle ? './cash_lifecycle.sql' : testPayment ? './test_payment_flow.sql' : remainingOnly ? './acceptance_edges.sql' : './flow.sql';
  await db.exec(fs.readFileSync(new URL(fixture,import.meta.url),'utf8'));
  console.log(paymentDispatch ? 'PASS: electronic authorization → automatic offer; duplicate provider event idempotent' : cashLifecycle ? 'PASS: cash creation → dispatch → acceptance → arrival → start → GPS → completion; cash_due visible to Rider; no provider actions' : testPayment ? 'PASS: isolated Test Payment lifecycle, zero receipt and account restrictions' : remainingOnly
    ? 'PASS: 4 additional checks — live-offer isolation, competing acceptance rejection, idempotent acceptance, expired acceptance rejection'
    : 'PASS: creation → automatic dispatch → Driver offer → acceptance → Rider RLS read; negative access and presence checks');
} catch(e){console.error('FLOW FAIL',e.message,e.where); process.exitCode=1;} await db.close();
