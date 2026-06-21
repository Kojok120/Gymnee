-- Gymnee Storage バケットとアクセス制御 (§3 画像ストレージ / §6.7 進捗写真)
-- パス規約: バケット直下を user_id で切る → "<auth.uid()>/<filename>"。RLS でパス先頭の所有者を判定。

-- バケット作成（既存ならスキップ）
insert into storage.buckets (id, name, public)
values
    ('visit-photos',    'visit-photos',    false),
    ('progress-photos', 'progress-photos', false),
    ('avatars',         'avatars',         true)
on conflict (id) do nothing;

-- 進捗写真: 体型写真は厳格に本人のみ（既定 private, §6.7）。署名URLで都度配信。
create policy "progress own read" on storage.objects for select to authenticated
    using (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "progress own write" on storage.objects for insert to authenticated
    with check (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "progress own update" on storage.objects for update to authenticated
    using (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "progress own delete" on storage.objects for delete to authenticated
    using (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- 来店写真: 本人が書込。共有はフィード経由＋署名URL想定のため読取も本人のみ（必要なら後で friends 緩和）。
create policy "visit own read" on storage.objects for select to authenticated
    using (bucket_id = 'visit-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "visit own write" on storage.objects for insert to authenticated
    with check (bucket_id = 'visit-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "visit own update" on storage.objects for update to authenticated
    using (bucket_id = 'visit-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "visit own delete" on storage.objects for delete to authenticated
    using (bucket_id = 'visit-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- アバター: 公開バケット（読取は誰でも）。書込は本人フォルダのみ。
create policy "avatars public read" on storage.objects for select to public
    using (bucket_id = 'avatars');
create policy "avatars own write" on storage.objects for insert to authenticated
    with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars own update" on storage.objects for update to authenticated
    using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars own delete" on storage.objects for delete to authenticated
    using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
