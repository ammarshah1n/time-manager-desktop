set lock_timeout = '5s';

grant execute on function public.current_profile_id() to authenticated, service_role;
grant execute on function public.current_workspace_ids() to authenticated, service_role;
