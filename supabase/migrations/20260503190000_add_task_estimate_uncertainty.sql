-- Add estimate_uncertainty column to support estimator's confidence interval
alter table public.tasks
  add column if not exists estimate_uncertainty numeric;

comment on column public.tasks.estimate_uncertainty is
  'Standard deviation (minutes) of the AI estimate posterior. NULL when estimator did not produce a confidence value.';
