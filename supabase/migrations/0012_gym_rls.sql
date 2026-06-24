-- 監査S: ユーザー作成ジム（lat/lng・メモ含む）を全公開にしない。own＋preset のみ参照可。
-- 本番には supabase db query で適用済み（ここは履歴）。
drop policy if exists gyms_select_all on public.gyms;
create policy gyms_select on public.gyms for select to authenticated using (
  created_by = auth.uid() or source = 'preset'
);

drop policy if exists gym_equipment_select_all on public.gym_equipment;
create policy gym_equipment_select on public.gym_equipment for select to authenticated using (
  created_by = auth.uid()
  or exists (select 1 from public.gyms g where g.id = gym_equipment.gym_id and (g.created_by = auth.uid() or g.source = 'preset'))
);
