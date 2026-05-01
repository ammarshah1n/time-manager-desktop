set lock_timeout = '5s';

create or replace function public._normalize_task_bucket_type(value text)
returns text
language sql
immutable
as $$
  select case lower(btrim(value))
    when 'reply' then 'reply_email'
    when 'reply email' then 'reply_email'
    when 'reply_email' then 'reply_email'
    when 'reply wa' then 'reply_wa'
    when 'reply_wa' then 'reply_wa'
    when 'reply other' then 'reply_other'
    when 'reply_other' then 'reply_other'
    when 'action' then 'action'
    when 'calls' then 'calls'
    when 'read' then 'read_today'
    when 'read today' then 'read_today'
    when 'readtoday' then 'read_today'
    when 'read_today' then 'read_today'
    when 'read this week' then 'read_this_week'
    when 'readthisweek' then 'read_this_week'
    when 'read_this_week' then 'read_this_week'
    when 'transit' then 'transit'
    when 'waiting' then 'waiting'
    when 'cc / fyi' then 'cc_fyi'
    when 'cc/fyi' then 'cc_fyi'
    when 'ccfyi' then 'cc_fyi'
    when 'cc_fyi' then 'cc_fyi'
    when 'other' then 'other'
    else btrim(value)
  end
$$;

alter table public.tasks
  drop constraint if exists tasks_bucket_type_check;
alter table public.estimation_history
  drop constraint if exists estimation_history_bucket_type_check;
alter table public.behaviour_events
  drop constraint if exists behaviour_events_bucket_type_check;
alter table public.bucket_completion_stats
  drop constraint if exists bucket_completion_stats_bucket_type_check;
alter table public.bucket_estimates
  drop constraint if exists bucket_estimates_bucket_type_check;

update public.tasks
set bucket_type = public._normalize_task_bucket_type(bucket_type)
where bucket_type is distinct from public._normalize_task_bucket_type(bucket_type);

update public.estimation_history
set bucket_type = public._normalize_task_bucket_type(bucket_type)
where bucket_type is distinct from public._normalize_task_bucket_type(bucket_type);

update public.behaviour_events
set bucket_type = public._normalize_task_bucket_type(bucket_type)
where bucket_type is not null
  and bucket_type is distinct from public._normalize_task_bucket_type(bucket_type);

with mapped as (
  select
    workspace_id,
    profile_id,
    public._normalize_task_bucket_type(bucket_type) as bucket_type,
    hour_range,
    sum(completions)::int as completions,
    sum(deferrals)::int as deferrals,
    max(updated_at) as updated_at
  from public.bucket_completion_stats
  where bucket_type is distinct from public._normalize_task_bucket_type(bucket_type)
  group by workspace_id, profile_id, public._normalize_task_bucket_type(bucket_type), hour_range
)
insert into public.bucket_completion_stats (
  workspace_id, profile_id, bucket_type, hour_range, completions, deferrals, updated_at
)
select workspace_id, profile_id, bucket_type, hour_range, completions, deferrals, updated_at
from mapped
on conflict (workspace_id, profile_id, bucket_type, hour_range)
do update set
  completions = public.bucket_completion_stats.completions + excluded.completions,
  deferrals = public.bucket_completion_stats.deferrals + excluded.deferrals,
  updated_at = greatest(public.bucket_completion_stats.updated_at, excluded.updated_at);

delete from public.bucket_completion_stats
where bucket_type is distinct from public._normalize_task_bucket_type(bucket_type);

with mapped as (
  select
    workspace_id,
    profile_id,
    public._normalize_task_bucket_type(bucket_type) as bucket_type,
    case
      when sum(sample_count) > 0 then
        sum(mean_minutes * sample_count)::double precision / sum(sample_count)::double precision
      else avg(mean_minutes)
    end as mean_minutes,
    sum(sample_count)::int as sample_count,
    max(updated_at) as updated_at
  from public.bucket_estimates
  where bucket_type is distinct from public._normalize_task_bucket_type(bucket_type)
  group by workspace_id, profile_id, public._normalize_task_bucket_type(bucket_type)
)
insert into public.bucket_estimates (
  workspace_id, profile_id, bucket_type, mean_minutes, sample_count, updated_at
)
select workspace_id, profile_id, bucket_type, mean_minutes, sample_count, updated_at
from mapped
on conflict (workspace_id, profile_id, bucket_type)
do update set
  mean_minutes = case
    when public.bucket_estimates.sample_count + excluded.sample_count > 0 then
      (
        public.bucket_estimates.mean_minutes * public.bucket_estimates.sample_count +
        excluded.mean_minutes * excluded.sample_count
      ) / (public.bucket_estimates.sample_count + excluded.sample_count)
    else excluded.mean_minutes
  end,
  sample_count = public.bucket_estimates.sample_count + excluded.sample_count,
  updated_at = greatest(public.bucket_estimates.updated_at, excluded.updated_at);

delete from public.bucket_estimates
where bucket_type is distinct from public._normalize_task_bucket_type(bucket_type);

alter table public.tasks
  add constraint tasks_bucket_type_check
  check (bucket_type in (
    'action', 'reply_email', 'reply_wa', 'reply_other',
    'read_today', 'read_this_week', 'calls', 'transit',
    'waiting', 'cc_fyi', 'other'
  ));

alter table public.estimation_history
  add constraint estimation_history_bucket_type_check
  check (bucket_type in (
    'action', 'reply_email', 'reply_wa', 'reply_other',
    'read_today', 'read_this_week', 'calls', 'transit',
    'waiting', 'cc_fyi', 'other'
  ));

alter table public.behaviour_events
  add constraint behaviour_events_bucket_type_check
  check (bucket_type is null or bucket_type in (
    'action', 'reply_email', 'reply_wa', 'reply_other',
    'read_today', 'read_this_week', 'calls', 'transit',
    'waiting', 'cc_fyi', 'other'
  ));

alter table public.bucket_completion_stats
  add constraint bucket_completion_stats_bucket_type_check
  check (bucket_type in (
    'action', 'reply_email', 'reply_wa', 'reply_other',
    'read_today', 'read_this_week', 'calls', 'transit',
    'waiting', 'cc_fyi', 'other'
  ));

alter table public.bucket_estimates
  add constraint bucket_estimates_bucket_type_check
  check (bucket_type in (
    'action', 'reply_email', 'reply_wa', 'reply_other',
    'read_today', 'read_this_week', 'calls', 'transit',
    'waiting', 'cc_fyi', 'other'
  ));

drop function public._normalize_task_bucket_type(text);
