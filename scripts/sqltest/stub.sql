-- Supabase の最小スタブ（Docker なしで migration の SQL を検証するため）。
-- auth.uid() は GUC test.uid、net.http_post は net.calls への記録で代用する。
create schema auth; create schema net;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid', true),'')::uuid $$;
create table net.calls(id serial, body jsonb);
create function net.http_post(url text, headers jsonb, body jsonb) returns bigint language plpgsql as $$ begin insert into net.calls(body) values (body); return 1; end $$;
create role anon; create role authenticated;
create table public.push_config(id int primary key, send_push_url text, push_secret text);
insert into public.push_config values (1,'http://push.test','secret');
create table public.profiles(id uuid primary key references auth.users(id), display_name text not null default 'ゲスト', avatar_url text);
create table public.workouts(id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id), completed_at timestamptz, date timestamptz default now());
