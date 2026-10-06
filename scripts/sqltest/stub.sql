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
-- 0043（ジョブ・攻撃の系統・トレ中）が読むテーブル。
create table public.exercises(id uuid primary key default gen_random_uuid(), name text not null default 'x', muscle_group text not null);
create table public.workout_exercises(id uuid primary key default gen_random_uuid(), workout_id uuid not null references public.workouts(id) on delete cascade, exercise_id uuid references public.exercises(id));
create table public.exercise_sets(id uuid primary key default gen_random_uuid(), workout_exercise_id uuid not null references public.workout_exercises(id) on delete cascade, is_completed boolean not null default false);
create table public.follows(follower_id uuid not null, followee_id uuid not null, primary key (follower_id, followee_id));
create function public.is_following(target uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.follows where follower_id = auth.uid() and followee_id = target)
$$;
create function public.live_session_max_duration() returns interval language sql immutable as $$ select interval '3 hours' $$;
create table public.live_sessions(id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id), started_at timestamptz not null default now(), ended_at timestamptz);
create function public.is_live(s public.live_sessions) returns boolean language sql stable as $$
  select s.ended_at is null and s.started_at > now() - public.live_session_max_duration()
$$;
