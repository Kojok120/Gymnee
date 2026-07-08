-- 種目マスタの重複掃除＋決定的id化（同名別idのプリセット増殖を根治）。
-- プリセット名は決定的id（uuid_generate_v5(ns, name)＝クライアント SeedData.presetId と一致）へ収束させ、
-- 同名の参照（workout_exercises / personal_records / routine_exercises）を付け替えてから重複を削除する。
-- カスタム種目（プリセット名以外）の同名重複は、参照最多の1件へマージ（id はそのまま）。
-- 冪等: 収束後に再実行しても影響なし（新規DBは exercises 空で no-op）。単一 DO ブロックで原子的に実行する。

create extension if not exists "uuid-ossp";

do $$
declare
  ns constant uuid := '1b671a64-40d5-491e-99b0-da01ff1f3341';
  preset_names text[] := array[
    'ベンチプレス','インクラインベンチプレス','ダンベルプレス','チェストプレス','ペックフライ',
    'スミスマシンベンチプレス','ディップス','デッドリフト','ベントオーバーロウ','ラットプルダウン',
    'シーテッドロウ','懸垂','スクワット','スミスマシンスクワット','レッグプレス',
    'レッグエクステンション','レッグカール','ルーマニアンデッドリフト','カーフレイズ','ショルダープレス',
    'ダンベルショルダープレス','スミスマシンショルダープレス','サイドレイズ','リアレイズ','アップライトロウ',
    'バーベルカール','ダンベルカール','ハンマーカール','トライセプスプレスダウン','スカルクラッシャー',
    'クランチ','シットアップ','レッグレイズ','ケーブルクランチ','アブローラー',
    'プランク','ヒップスラスト','バーピー','ケトルベルスイング','クリーン&ジャーク',
    'ウォーキング','ランニング','バイシクル'
  ];
  nm text;
  cid uuid;
  mg text;
  eq text;
  r record;
  keeper uuid;
begin
  -- (1) プリセット名 → 決定的id へ収束
  foreach nm in array preset_names loop
    cid := uuid_generate_v5(ns, nm);
    -- 正準行を用意（無ければ同名の代表行の属性を複製し preset として正規化）
    select e.muscle_group, e.equipment into mg, eq
      from public.exercises e where e.name = nm order by e.updated_at desc limit 1;
    -- 既存の同名行が1件も無い（新規DB等）なら何もしない＝空DBで bogus 行を作らず no-op。
    if cid is not null and exists (select 1 from public.exercises where name = nm) then
      insert into public.exercises (id, name, muscle_group, equipment, is_custom, created_by, updated_at)
        values (cid, nm, coalesce(mg, 'chest'), coalesce(eq, 'barbell'), false, null, now())
        on conflict (id) do nothing;
      -- 同名別id行の参照を正準へ付け替え
      update public.workout_exercises w set exercise_id = cid
        from public.exercises e where w.exercise_id = e.id and e.name = nm and e.id <> cid;
      update public.personal_records p set exercise_id = cid
        from public.exercises e where p.exercise_id = e.id and e.name = nm and e.id <> cid;
      update public.routine_exercises rr set exercise_id = cid
        from public.exercises e where rr.exercise_id = e.id and e.name = nm and e.id <> cid;
      -- 同名別id行を削除
      delete from public.exercises e where e.name = nm and e.id <> cid;
    end if;
  end loop;

  -- (2) カスタム（プリセット名以外）の同名重複 → 参照最多の1件へマージ
  for r in
    select name from public.exercises
    where name <> all(preset_names)
    group by name having count(*) > 1
  loop
    select e.id into keeper from public.exercises e
      where e.name = r.name
      order by (select count(*) from public.workout_exercises w where w.exercise_id = e.id)
             + (select count(*) from public.routine_exercises rr where rr.exercise_id = e.id)
             + (select count(*) from public.personal_records p where p.exercise_id = e.id) desc,
             e.updated_at asc
      limit 1;
    update public.workout_exercises w set exercise_id = keeper
      from public.exercises e where w.exercise_id = e.id and e.name = r.name and e.id <> keeper;
    update public.personal_records p set exercise_id = keeper
      from public.exercises e where p.exercise_id = e.id and e.name = r.name and e.id <> keeper;
    update public.routine_exercises rr set exercise_id = keeper
      from public.exercises e where rr.exercise_id = e.id and e.name = r.name and e.id <> keeper;
    delete from public.exercises e where e.name = r.name and e.id <> keeper;
  end loop;
end $$;
