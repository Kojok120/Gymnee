-- visits ↔ visit_partners の RLS 相互参照が無限再帰(42P17)するため、
-- SECURITY DEFINER 関数で RLS を介さずに判定して再帰を断ち切る。
-- 0002_rls.sql 適用済みの環境に対して流す（冪等：create or replace / drop if exists）。

-- 合トレ相手か？（visit_partners を RLS 無しで参照）
create or replace function public.is_visit_partner(v_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.visit_partners
        where visit_id = v_id and partner_user_id = auth.uid()
    );
$$;

-- その来店の所有者か？（visits を RLS 無しで参照）
create or replace function public.owns_visit(v_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.visits
        where id = v_id and user_id = auth.uid()
    );
$$;

-- visits: 本人 or 合トレ相手（関数経由で再帰回避）。
drop policy if exists visits_select on public.visits;
create policy visits_select on public.visits for select to authenticated
    using (user_id = auth.uid() or public.is_visit_partner(id));

-- visit_partners: 相手本人 or 来店オーナー（関数経由で再帰回避）。
drop policy if exists visit_partners_select on public.visit_partners;
create policy visit_partners_select on public.visit_partners for select to authenticated
    using (partner_user_id = auth.uid() or public.owns_visit(visit_id));

drop policy if exists visit_partners_modify_owner on public.visit_partners;
create policy visit_partners_modify_owner on public.visit_partners for all to authenticated
    using (public.owns_visit(visit_id)) with check (public.owns_visit(visit_id));
