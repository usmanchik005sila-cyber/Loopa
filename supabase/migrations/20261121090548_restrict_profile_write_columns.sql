begin;

-- Profile creation time is set by PostgreSQL. Keep the fields used by
-- existing clients, including id for upsert and updated_at for avatar refresh.
revoke insert, update on public.profiles from authenticated;
grant insert (id, display_name, username, avatar_path, updated_at,
              allow_friend_requests, room_invite_policy, dm_policy, notification_sound),
      update (id, display_name, username, avatar_path, updated_at,
              allow_friend_requests, room_invite_policy, dm_policy, notification_sound)
on public.profiles to authenticated;

notify pgrst, 'reload schema';

commit;
