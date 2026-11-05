-- 外部連携（0046・#171）の関数の検証。ローカル Supabase（全 migration 済み）に対して流す。
-- 使い方: /opt/homebrew/opt/postgresql@16/bin/psql postgresql://postgres:postgres@127.0.0.1:54422/postgres -v ON_ERROR_STOP=1 -f scripts/sqltest/connect_local_test.sql
-- 全体を begin / rollback で包むので、ローカルの DB にも何も残らない。
begin;

create function pg_temp.u(n int) returns uuid language sql immutable as $$
  select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid
$$;

insert into auth.users (id, instance_id, aud, role, email)
select pg_temp.u(i), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'connect' || i || '@test.local'
from generate_series(1, 2) i;

do $$
declare
  bench uuid := (select id from public.exercises where name = 'ベンチプレス' and created_by is null limit 1);
  payload jsonb;
  r json;
  n int;
  v float8;
begin
  assert bench is not null, 'プリセットのベンチプレスがある';

  payload := jsonb_build_object(
    'id', pg_temp.u(101), 'name', '胸の日', 'date', now() - interval '1 hour', 'completed_at', now(),
    'duration_seconds', 3600, 'note', 'LINE から',
    'exercises', jsonb_build_array(jsonb_build_object(
      'id', pg_temp.u(201), 'exercise_id', bench,
      'sets', jsonb_build_array(
        jsonb_build_object('id', pg_temp.u(301), 'set_index', 0, 'weight', 60, 'reps', 10, 'is_pr', true),
        jsonb_build_object('id', pg_temp.u(302), 'set_index', 1, 'weight', 62.5, 'reps', 8, 'is_pr', true)
      ))),
    'personal_records', jsonb_build_array(
      jsonb_build_object('exercise_id', bench, 'type', 'max_weight', 'value', 62.5),
      jsonb_build_object('exercise_id', bench, 'type', 'est_1rm', 'value', 80)
    ));

  r := public.connect_log_workout(pg_temp.u(1), payload);
  assert (r->>'created')::boolean, '初回は作られる';
  select count(*) into n from public.exercise_sets where workout_exercise_id = pg_temp.u(201);
  assert n = 2, 'セットが 2 件入る';
  select count(*) into n from public.personal_records where user_id = pg_temp.u(1) and exercise_id = bench;
  assert n = 2, '自己ベストが種別ごとに 1 行ずつ入る';

  -- 冪等: 同じ id をもう一度送っても増えない
  r := public.connect_log_workout(pg_temp.u(1), payload);
  assert not (r->>'created')::boolean, '再送は created=false';
  select count(*) into n from public.workouts where id = pg_temp.u(101);
  assert n = 1, '記録は 1 件のまま';

  -- 他人が同じ id を使うことはできない
  begin
    perform public.connect_log_workout(pg_temp.u(2), payload);
    assert false, '他人の id は拒否されるはず';
  exception when insufficient_privilege then null;
  end;

  -- 自己ベスト: 弱い値では置き換えない / 強い値では置き換える
  payload := jsonb_set(jsonb_set(payload, '{id}', to_jsonb(pg_temp.u(102))),
    '{exercises}', jsonb_build_array(jsonb_build_object('id', pg_temp.u(202), 'exercise_id', bench,
      'sets', jsonb_build_array(jsonb_build_object('id', pg_temp.u(303), 'set_index', 0, 'weight', 70, 'reps', 3)))));
  payload := jsonb_set(payload, '{personal_records}', jsonb_build_array(
    jsonb_build_object('exercise_id', bench, 'type', 'max_weight', 'value', 70),
    jsonb_build_object('exercise_id', bench, 'type', 'est_1rm', 'value', 77)));
  perform public.connect_log_workout(pg_temp.u(1), payload);
  select value into v from public.personal_records where user_id = pg_temp.u(1) and exercise_id = bench and type = 'max_weight';
  assert v = 70, '最大重量は 70 に更新';
  select value into v from public.personal_records where user_id = pg_temp.u(1) and exercise_id = bench and type = 'est_1rm';
  assert v = 80, '推定1RM は弱い 77 では置き換えない';

  -- 他人の種目には記録できない
  insert into public.exercises (id, name, muscle_group, equipment, is_custom, created_by)
  values (pg_temp.u(900), 'U2 の種目', 'chest', 'other', true, pg_temp.u(2));
  begin
    perform public.connect_log_workout(pg_temp.u(1), jsonb_build_object(
      'id', pg_temp.u(103), 'completed_at', now(),
      'exercises', jsonb_build_array(jsonb_build_object('id', pg_temp.u(203), 'exercise_id', pg_temp.u(900),
        'sets', jsonb_build_array(jsonb_build_object('id', pg_temp.u(304), 'weight', 10, 'reps', 10))))));
    assert false, '他人の種目は拒否されるはず';
  exception when foreign_key_violation then null;
  end;
  assert not exists (select 1 from public.workouts where id = pg_temp.u(103)), '失敗した記録は残らない（1 トランザクション）';

  -- パーティの状況: 入っていなければ空配列
  assert public.connect_party_overview(pg_temp.u(1))::text = '[]', 'パーティ無しは空';

  raise notice 'connect: PASSED';
end $$;

-- 権限: アプリ（authenticated）と匿名（anon）からは呼べない
do $$
begin
  assert not has_function_privilege('authenticated', 'public.connect_log_workout(uuid, jsonb)', 'execute'), 'authenticated は呼べない';
  assert not has_function_privilege('anon', 'public.connect_log_workout(uuid, jsonb)', 'execute'), 'anon は呼べない';
  assert not has_function_privilege('authenticated', 'public.connect_party_overview(uuid, timestamptz)', 'execute'), 'authenticated は呼べない';
  assert has_function_privilege('service_role', 'public.connect_log_workout(uuid, jsonb)', 'execute'), 'service_role は呼べる';
  assert not has_table_privilege('authenticated', 'public.connect_api_tokens', 'select'), 'トークンの表は読めない';
  raise notice 'connect privileges: PASSED';
end $$;

rollback;
