-- ============================================================
-- Trigger: update user_profiles.avg_estimate_error_pct on each estimation_history insert
-- Rolling 30-day average of estimate_error for the user.
-- Migration: 20260401000006_avg_estimate_error_trigger.sql
-- ============================================================

create or replace function public.update_avg_estimate_error()
returns trigger language plpgsql security definer as $$
begin
    update public.user_profiles
    set avg_estimate_error_pct = (
        select avg(estimate_error)
        from public.estimation_history
        where profile_id = NEW.profile_id
          and created_at >= now() - interval '30 days'
          and actual_minutes is not null
    ),
    updated_at = now()
    where profile_id = NEW.profile_id;
    return NEW;
end;
$$;

create trigger estimation_history_update_avg_error
after insert on public.estimation_history
for each row execute function public.update_avg_estimate_error();
