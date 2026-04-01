-- Expand sender_rules check constraint to include 'later' and 'delegate' rule types.
-- These are soft priors (not hard overrides like inbox_always/black_hole).

ALTER TABLE public.sender_rules
    DROP CONSTRAINT IF EXISTS sender_rules_rule_type_check;
ALTER TABLE public.sender_rules
    ADD CONSTRAINT sender_rules_rule_type_check
    CHECK (rule_type IN ('inbox_always', 'black_hole', 'later', 'delegate'));
