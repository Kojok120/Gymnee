-- 0039: プリセット種目の拡充（issue #114）
--
-- 背景: プリセット 43 件では足りず、ユーザーがカスタム登録で補っていた（本番のカスタム種目 40 種の
-- 上位はインクラインダンベルプレス / ヒップアダクション / ケーブルサイドレイズ / ダンベルフライ など）。
-- クライアント（SeedData.presetExercises v5）に 53 件を追加するのに合わせ、サーバーマスタ
-- （created_by IS NULL・決定的 id = uuid_generate_v5(ns, name)、migration 0030 と同方式）にも同じ行を入れる。
-- サーバーに行が無いと、その種目を含む workout_exercises の push が FK(23503) で滞留するため、
-- **アプリ配信より先に適用する**。
--
-- 内容: 53 件を決定的 id で upsert（has_angle 含む全属性を正準値へ）。
-- 既存のユーザー作成種目（is_custom=true・同名でも別 id）には触れない。同名解決はクライアント側
-- （RecordView.rebuildCatalog）が名前で 1 件に畳むため、二重表示にはならない。
-- 冪等: 再実行しても updated_at が進む以外は無影響。

create extension if not exists "uuid-ossp";

do $$
declare
  ns constant uuid := '1b671a64-40d5-491e-99b0-da01ff1f3341';
  p record;
begin
  for p in
    select * from (values
      -- 胸
      ('デクラインベンチプレス', 'chest', 'barbell', 'weight', 'both', 'none', false),
      ('インクラインダンベルプレス', 'chest', 'dumbbell', 'weight', 'perSide', 'none', false),
      ('ダンベルフライ', 'chest', 'dumbbell', 'weight', 'perSide', 'none', false),
      ('ダンベルプルオーバー', 'chest', 'dumbbell', 'weight', 'none', 'none', false),
      ('インクラインチェストプレス', 'chest', 'machine', 'weight', 'none', 'none', false),
      ('デクラインチェストプレス', 'chest', 'machine', 'weight', 'none', 'none', false),
      ('ケーブルクロスオーバー', 'chest', 'cable', 'weight', 'perSide', 'none', false),
      ('スミスマシンインクラインベンチプレス', 'chest', 'machine', 'weight', 'both', 'none', false),
      ('腕立て伏せ', 'chest', 'bodyweight', 'bodyweight', 'none', 'none', false),
      -- 背中
      ('ワンハンドロウ', 'back', 'dumbbell', 'weight', 'perSide', 'none', false),
      ('Tバーロウ', 'back', 'machine', 'weight', 'none', 'none', false),
      ('ハイロウ', 'back', 'machine', 'weight', 'perSide', 'none', false),
      ('ローロウ', 'back', 'machine', 'weight', 'perSide', 'none', false),
      ('ケーブルプルオーバー', 'back', 'cable', 'weight', 'none', 'none', false),
      ('バーベルシュラッグ', 'back', 'barbell', 'weight', 'both', 'none', false),
      ('ダンベルシュラッグ', 'back', 'dumbbell', 'weight', 'perSide', 'none', false),
      ('バックエクステンション', 'back', 'bodyweight', 'bodyweight', 'none', 'weighted', false),
      -- 脚
      ('フロントスクワット', 'legs', 'barbell', 'weight', 'both', 'none', false),
      ('ゴブレットスクワット', 'legs', 'dumbbell', 'weight', 'none', 'none', false),
      ('ブルガリアンスクワット', 'legs', 'dumbbell', 'weight', 'perSide', 'none', false),
      ('ランジ', 'legs', 'dumbbell', 'weight', 'perSide', 'none', false),
      ('ハックスクワット', 'legs', 'machine', 'weight', 'none', 'none', false),
      ('ヒップアダクション', 'legs', 'machine', 'weight', 'none', 'none', false),
      -- 肩
      ('バーベルショルダープレス', 'shoulders', 'barbell', 'weight', 'both', 'none', false),
      ('アーノルドプレス', 'shoulders', 'dumbbell', 'weight', 'perSide', 'none', false),
      ('ケーブルサイドレイズ', 'shoulders', 'cable', 'weight', 'perSide', 'none', false),
      ('マシンサイドレイズ', 'shoulders', 'machine', 'weight', 'none', 'none', false),
      ('フロントレイズ', 'shoulders', 'dumbbell', 'weight', 'perSide', 'none', false),
      ('ケーブルフロントレイズ', 'shoulders', 'cable', 'weight', 'none', 'none', false),
      ('リアデルトフライ', 'shoulders', 'machine', 'weight', 'none', 'none', false),
      ('フェイスプル', 'shoulders', 'cable', 'weight', 'none', 'none', false),
      -- 腕
      ('プリーチャーカール', 'arms', 'barbell', 'weight', 'both', 'none', false),
      ('インクラインダンベルカール', 'arms', 'dumbbell', 'weight', 'perSide', 'none', false),
      ('コンセントレーションカール', 'arms', 'dumbbell', 'weight', 'perSide', 'none', false),
      ('マシンアームカール', 'arms', 'machine', 'weight', 'none', 'none', false),
      ('ケーブルカール', 'arms', 'cable', 'weight', 'none', 'none', false),
      ('キックバック', 'arms', 'dumbbell', 'weight', 'perSide', 'none', false),
      ('オーバーヘッドエクステンション', 'arms', 'dumbbell', 'weight', 'none', 'none', false),
      ('ナローベンチプレス', 'arms', 'barbell', 'weight', 'both', 'none', false),
      -- 腹
      ('ハンギングレッグレイズ', 'abs', 'bodyweight', 'bodyweight', 'none', 'none', false),
      ('ロシアンツイスト', 'abs', 'bodyweight', 'bodyweight', 'none', 'none', false),
      ('アブドミナルクランチ', 'abs', 'machine', 'weight', 'none', 'none', false),
      ('トーソローテーション', 'abs', 'machine', 'weight', 'none', 'none', false),
      -- 体幹
      ('サイドプランク', 'core', 'bodyweight', 'time', 'none', 'none', false),
      -- 臀部
      ('ヒップアブダクション', 'glutes', 'machine', 'weight', 'none', 'none', false),
      ('ケーブルキックバック', 'glutes', 'cable', 'weight', 'perSide', 'none', false),
      ('ヒップリフト', 'glutes', 'bodyweight', 'bodyweight', 'none', 'none', false),
      -- 全身
      ('マウンテンクライマー', 'full_body', 'bodyweight', 'bodyweight', 'none', 'none', false),
      ('パワークリーン', 'full_body', 'barbell', 'weight', 'both', 'none', false),
      -- 有酸素
      ('クロストレーナー', 'cardio', 'machine', 'cardio', 'none', 'none', false),
      ('ステアクライマー', 'cardio', 'machine', 'cardio', 'none', 'none', false),
      ('ローイングマシン', 'cardio', 'machine', 'cardio', 'none', 'none', false),
      ('水泳', 'cardio', 'other', 'cardio', 'none', 'none', false)
    ) as v(name, muscle_group, equipment, measurement_type, weight_mode, load_mode, has_angle)
  loop
    insert into public.exercises
      (id, name, muscle_group, equipment, is_custom, created_by,
       weight_mode, measurement_type, load_mode, has_angle, updated_at)
    values
      (uuid_generate_v5(ns, p.name), p.name, p.muscle_group, p.equipment, false, null,
       p.weight_mode, p.measurement_type, p.load_mode, p.has_angle, now())
    on conflict (id) do update
      set created_by       = null,
          is_custom        = false,
          name             = excluded.name,
          muscle_group     = excluded.muscle_group,
          equipment        = excluded.equipment,
          weight_mode      = excluded.weight_mode,
          measurement_type = excluded.measurement_type,
          load_mode        = excluded.load_mode,
          has_angle        = excluded.has_angle,
          updated_at       = now();
  end loop;
end $$;
