-- ============================================================
-- Trigger: auto-populate estimation_history when tasks.actual_minutes is set
-- Copies the task embedding into estimation_history so future similarity
-- searches can find completed tasks.
-- Migration: 20260331000004_estimation_history_trigger.sql
-- ============================================================

create or replace function public.trg_insert_estimation_history()
returns trigger as $$
begin
  -- Fire when actual_minutes transitions from NULL to a value (task completed with time)
  if NEW.actual_minutes is not null and (OLD.actual_minutes is null or OLD.actual_minutes is distinct from NEW.actual_minutes) then
    insert into public.estimation_history (
      workspace_id,
      task_id,
      profile_id,
      bucket_type,
      title_tokens,
      from_address,
      estimated_minutes_ai,
      estimated_minutes_manual,
      actual_minutes,
      estimate_error,
      embedding
    )
    values (
      NEW.workspace_id,
      NEW.id,
      NEW.profile_id,
      NEW.bucket_type,
      -- Tokenise title: lowercase, split on whitespace/punctuation
      regexp_split_to_array(lower(coalesce(NEW.title, '')), '[^a-z0-9]+'),
      -- Grab from_address from the source email if available
      (select em.from_address from public.email_messages em where em.id = NEW.source_email_id),
      NEW.estimated_minutes_ai,
      NEW.estimated_minutes_manual,
      NEW.actual_minutes,
      case
        when NEW.estimated_minutes_ai is not null and NEW.actual_minutes > 0
        then (NEW.actual_minutes - NEW.estimated_minutes_ai)::real / NEW.actual_minutes::real
        else null
      end,
      NEW.embedding
    )
    on conflict do nothing; -- guard against duplicate fires
  end if;

  return NEW;
end;
$$ language plpgsql security definer;

create trigger trg_task_completion_to_estimation_history
  after update on public.tasks
  for each row
  execute function public.trg_insert_estimation_history();
