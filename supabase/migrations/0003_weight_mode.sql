-- ③ 重量の数え方（両側/片側）。種目に既定、セットで上書き。
-- 本番には supabase db query で適用済み（ここは履歴として保持）。
alter table public.exercises add column if not exists weight_mode text not null default 'both';
alter table public.exercise_sets add column if not exists weight_mode_override text;
