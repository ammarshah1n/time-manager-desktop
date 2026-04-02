# Deployment

## Supabase (Database + Edge Functions)
```bash
supabase db push                              # Push migrations to cloud
supabase functions deploy graph-webhook       # Deploy webhook receiver
supabase functions deploy classify-email      # Deploy classification function
supabase functions deploy extract-tasks       # Deploy task extraction
supabase functions deploy estimate-time       # Deploy time estimation
supabase functions deploy generate-daily-plan # Deploy planning engine
supabase functions deploy process-email-pipeline # Deploy orchestrator
supabase functions deploy refresh-graph-subscription # Deploy subscription renewal
```

## macOS App
```bash
swift build -c release
bash scripts/package_app.sh    # Signs and packages
bash scripts/install_app.sh    # Installs locally
```

## Verify Edge Functions
```bash
supabase functions list        # Confirm all deployed
supabase functions logs graph-webhook --tail  # Watch for incoming webhooks
```
