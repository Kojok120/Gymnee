-- 0034: ワークアウト投稿写真のバケット（visit-photos の後継）
-- パス規約は既存と同じ "<auth.uid()>/<filename>"。
-- 読取は 0025（visit-photos）と同じ「本人 or その写真を参照する可視な feed_item 経由」。
-- フォルダ単位ではなくオブジェクト単位で厳密一致させ、同フォルダの未共有/孤児写真を
-- 列挙・取得されないようにする。photoRef は "workout-photos/<uid>/<file>" = bucket_id || '/' || name。
-- 書込/更新/削除は本人のみ。

insert into storage.buckets (id, name, public)
values ('workout-photos', 'workout-photos', false)
on conflict (id) do nothing;

-- 再適用できるよう既存ポリシーを落としてから作る（setup_all.sql の再実行対策）。
drop policy if exists "workout photo read own or via feed" on storage.objects;
drop policy if exists "workout photo own write" on storage.objects;
drop policy if exists "workout photo own update" on storage.objects;
drop policy if exists "workout photo own delete" on storage.objects;

create policy "workout photo read own or via feed" on storage.objects for select to authenticated
    using (
        bucket_id = 'workout-photos'
        and (
            (storage.foldername(name))[1] = auth.uid()::text
            or exists (
                select 1 from public.feed_items f
                where f.user_id::text = (storage.foldername(name))[1]
                  and f.type = 'workout'
                  and (f.stats_json::jsonb ->> 'photoRef') = bucket_id || '/' || name
                  and (
                      f.visibility = 'public'
                      or (f.visibility = 'friends' and public.is_following(f.user_id))
                  )
            )
        )
    );
create policy "workout photo own write" on storage.objects for insert to authenticated
    with check (bucket_id = 'workout-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "workout photo own update" on storage.objects for update to authenticated
    using (bucket_id = 'workout-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "workout photo own delete" on storage.objects for delete to authenticated
    using (bucket_id = 'workout-photos' and (storage.foldername(name))[1] = auth.uid()::text);
