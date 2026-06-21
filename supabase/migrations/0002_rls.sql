-- Gymnee 行レベルセキュリティ (§7 セキュリティ / RLS で行レベル権限)
-- 0001_schema.sql の後に適用する。
--
-- 原則:
--   * ユーザー所有テーブルは本人(user_id = auth.uid())のみ全権。
--   * マスタ(gyms/exercises)はプリセット＝全員参照、ユーザー作成分＝作成者のみ更新。
--   * 公開コンテンツ(progress_photos/feed_items)は visibility と follow 関係で参照可否を判定。
--   * products は全員参照、書込はサービスロール(管理)のみ。

-- フォロー判定ヘルパ（friends 可視性で使用）
create or replace function public.is_following(target uuid)
returns boolean
language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.follows
        where follower_id = auth.uid() and followee_id = target
    );
$$;

-- visits ↔ visit_partners の相互参照ポリシーが無限再帰(42P17)するため、
-- RLS を介さない SECURITY DEFINER 関数で判定する。
create or replace function public.is_visit_partner(v_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.visit_partners
        where visit_id = v_id and partner_user_id = auth.uid()
    );
$$;

create or replace function public.owns_visit(v_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.visits
        where id = v_id and user_id = auth.uid()
    );
$$;

-- =========================================================
-- profiles : 本人のみ書込。プロフィールは全員参照可（ソーシャル表示のため）。
-- =========================================================
alter table public.profiles enable row level security;
create policy profiles_select_all on public.profiles for select to authenticated using (true);
create policy profiles_modify_self on public.profiles for all to authenticated
    using (id = auth.uid()) with check (id = auth.uid());

-- =========================================================
-- gyms : 全員参照、作成者のみ書込（preset は created_by NULL で全員参照のみ）。
-- =========================================================
alter table public.gyms enable row level security;
create policy gyms_select_all on public.gyms for select to authenticated using (true);
create policy gyms_insert_own on public.gyms for insert to authenticated
    with check (created_by = auth.uid());
create policy gyms_update_own on public.gyms for update to authenticated
    using (created_by = auth.uid()) with check (created_by = auth.uid());
create policy gyms_delete_own on public.gyms for delete to authenticated
    using (created_by = auth.uid());

-- gym_equipment : 全員参照、作成者のみ書込。
alter table public.gym_equipment enable row level security;
create policy gym_equipment_select_all on public.gym_equipment for select to authenticated using (true);
create policy gym_equipment_modify_own on public.gym_equipment for all to authenticated
    using (created_by = auth.uid()) with check (created_by = auth.uid());

-- =========================================================
-- visits : 本人のみ。合トレ相手は参照可。
-- =========================================================
alter table public.visits enable row level security;
create policy visits_select on public.visits for select to authenticated
    using (user_id = auth.uid() or public.is_visit_partner(id));
create policy visits_modify_own on public.visits for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

-- visit_partners : 来店オーナーが管理、相手は参照のみ（関数経由で再帰回避）。
alter table public.visit_partners enable row level security;
create policy visit_partners_select on public.visit_partners for select to authenticated
    using (partner_user_id = auth.uid() or public.owns_visit(visit_id));
create policy visit_partners_modify_owner on public.visit_partners for all to authenticated
    using (public.owns_visit(visit_id)) with check (public.owns_visit(visit_id));

-- =========================================================
-- workouts / 子テーブル : 本人のみ（子は親の所有者で判定）。
-- =========================================================
alter table public.workouts enable row level security;
create policy workouts_modify_own on public.workouts for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.workout_exercises enable row level security;
create policy workout_exercises_own on public.workout_exercises for all to authenticated
    using (exists (select 1 from public.workouts w where w.id = workout_id and w.user_id = auth.uid()))
    with check (exists (select 1 from public.workouts w where w.id = workout_id and w.user_id = auth.uid()));

alter table public.exercise_sets enable row level security;
create policy exercise_sets_own on public.exercise_sets for all to authenticated
    using (exists (
        select 1 from public.workout_exercises we
        join public.workouts w on w.id = we.workout_id
        where we.id = workout_exercise_id and w.user_id = auth.uid()
    ))
    with check (exists (
        select 1 from public.workout_exercises we
        join public.workouts w on w.id = we.workout_id
        where we.id = workout_exercise_id and w.user_id = auth.uid()
    ));

-- =========================================================
-- exercises : 全員参照、作成者のみ書込。
-- =========================================================
alter table public.exercises enable row level security;
create policy exercises_select_all on public.exercises for select to authenticated using (true);
create policy exercises_insert_own on public.exercises for insert to authenticated
    with check (created_by = auth.uid());
create policy exercises_update_own on public.exercises for update to authenticated
    using (created_by = auth.uid()) with check (created_by = auth.uid());
create policy exercises_delete_own on public.exercises for delete to authenticated
    using (created_by = auth.uid());

-- =========================================================
-- routines / routine_exercises : 本人のみ。
-- =========================================================
alter table public.routines enable row level security;
create policy routines_modify_own on public.routines for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.routine_exercises enable row level security;
create policy routine_exercises_own on public.routine_exercises for all to authenticated
    using (exists (select 1 from public.routines r where r.id = routine_id and r.user_id = auth.uid()))
    with check (exists (select 1 from public.routines r where r.id = routine_id and r.user_id = auth.uid()));

-- =========================================================
-- personal_records / body_metrics / supply_logs / subscriptions : 本人のみ。
-- =========================================================
alter table public.personal_records enable row level security;
create policy personal_records_own on public.personal_records for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.body_metrics enable row level security;
create policy body_metrics_own on public.body_metrics for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.supply_logs enable row level security;
create policy supply_logs_own on public.supply_logs for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.subscriptions enable row level security;
create policy subscriptions_select_own on public.subscriptions for select to authenticated
    using (user_id = auth.uid());
-- subscriptions の書込はサーバ(サービスロール)のみ＝クライアント書込ポリシーは作らない。

-- =========================================================
-- progress_photos : 本人＋可視性(public / friends)で参照。
-- =========================================================
alter table public.progress_photos enable row level security;
create policy progress_photos_select on public.progress_photos for select to authenticated
    using (
        user_id = auth.uid()
        or visibility = 'public'
        or (visibility = 'friends' and public.is_following(user_id))
    );
create policy progress_photos_modify_own on public.progress_photos for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

-- =========================================================
-- follows : 当事者(follower / followee)が参照、follower のみ作成/削除。
-- =========================================================
alter table public.follows enable row level security;
create policy follows_select on public.follows for select to authenticated
    using (follower_id = auth.uid() or followee_id = auth.uid());
create policy follows_modify_own on public.follows for all to authenticated
    using (follower_id = auth.uid()) with check (follower_id = auth.uid());

-- =========================================================
-- feed_items : 本人＋可視性で参照。
-- =========================================================
alter table public.feed_items enable row level security;
create policy feed_items_select on public.feed_items for select to authenticated
    using (
        user_id = auth.uid()
        or visibility = 'public'
        or (visibility = 'friends' and public.is_following(user_id))
    );
create policy feed_items_modify_own on public.feed_items for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

-- =========================================================
-- products : 全員参照（is_active）。書込はサービスロールのみ。
-- =========================================================
alter table public.products enable row level security;
create policy products_select_active on public.products for select to authenticated
    using (is_active = true);
-- 書込ポリシー無し＝anon/authenticated は不可。カタログ更新はサービスロール(Edge Function/管理)で行う。
