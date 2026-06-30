-- 来店写真をフォロワーにも見せる（フィード共有のため）。
-- 従来は本人のみ読取可だったが、来店投稿(feed_items.type='visit')が閲覧者から見える
-- （public、または friends かつフォロー中）場合は、その投稿者の来店写真の読取を許可する。
-- 注: 写真ごとではなく投稿者単位の判定（その人の可視な来店投稿が1件でもあれば読取可）。
-- 書込/更新/削除は引き続き本人のみ。

drop policy if exists "visit own read" on storage.objects;

create policy "visit read own or via feed" on storage.objects for select to authenticated
    using (
        bucket_id = 'visit-photos'
        and (
            (storage.foldername(name))[1] = auth.uid()::text
            or exists (
                select 1 from public.feed_items f
                where f.user_id::text = (storage.foldername(name))[1]
                  and f.type = 'visit'
                  and (
                      f.visibility = 'public'
                      or (f.visibility = 'friends' and public.is_following(f.user_id))
                  )
            )
        )
    );
