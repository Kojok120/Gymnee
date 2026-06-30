-- 来店写真をフォロワーにも見せる（フィード共有のため）。
-- 従来は本人のみ読取可。本人に加え、「その写真を参照している来店投稿(feed_items.type='visit')」が
-- 閲覧者から見える（public、または friends かつフォロー中）場合に限り読取を許可する。
-- 重要: フォルダ単位ではなく「投稿が参照する当該オブジェクト」に厳密一致させる
-- （同フォルダの未共有/削除済み/孤児写真を列挙・取得されないようにする）。
-- photoRef は "visit-photos/<uid>/<file>" = bucket_id || '/' || name と一致する。
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
                  and (f.stats_json::jsonb ->> 'photoRef') = bucket_id || '/' || name
                  and (
                      f.visibility = 'public'
                      or (f.visibility = 'friends' and public.is_following(f.user_id))
                  )
            )
        )
    );
