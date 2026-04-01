# Microsoft Graph OAuth Setup

1. Go to https://portal.azure.com
2. Azure Active Directory → App Registrations → New Registration
3. Name: Timed
4. Supported account types: Single tenant
5. Redirect URI: msauth.com.timeblock.app://auth (macOS)
6. After creation:
   - Copy Application (client) ID → GRAPH_CLIENT_ID
   - Copy Directory (tenant) ID → GRAPH_TENANT_ID
7. API Permissions → Add Permission → Microsoft Graph → Delegated:
   - Mail.ReadWrite
   - Mail.Send
   - Calendars.ReadWrite
   - offline_access
8. Grant admin consent (if org requires it)
9. Certificates & secrets → NOT needed (MSAL handles public client flow)
