# Microsoft Sign-in Configuration

## Default: built-in Microsoft sign-in (no setup)

Out of the box the launcher signs in through **Microsoft's own public Xbox Live
client** using the device-code flow on `login.live.com`. This is the same
documented path other third-party launchers use: you get a short code, approve
it on microsoft.com in your browser, and the launcher receives OAuth tokens.
No Azure account, registration, or configuration is required, and it is still
100% official Microsoft authentication — no password ever touches the app.

## Optional: your own Azure AD application

If you prefer to authenticate under your own app identity (e.g. for
distribution), register one:

1. Go to <https://portal.azure.com> → **Microsoft Entra ID** → **App
   registrations** → **New registration**.
   - Supported account types: **Personal Microsoft accounts only**.
   - Redirect URI: leave empty (device-code flow doesn't need one).
2. In the app's **Authentication** settings, enable
   **Allow public client flows** ("Treat application as a public client").
3. Note the **Application (client) ID** (a UUID).
4. **Required:** apply for Minecraft API approval — Mojang restricts
   `api.minecraftservices.com` to approved client IDs. Submit the form at
   <https://aka.ms/mce-reviewappid> and wait for confirmation (this can take
   a while).
5. In MetalCraft: **Settings → Account → Custom Azure client ID**, paste the
   UUID. The next sign-in uses `login.microsoftonline.com` with the
   `XboxLive.signin offline_access` scopes under your app identity.

Leave the field empty at any time to fall back to the built-in sign-in.

## Token storage

Both modes store only OAuth tokens, in the macOS Keychain
(`dev.metalcraft.launcher`): the MSA refresh token and the short-lived
Minecraft access token. `accounts.json` on disk holds public profile metadata
only (username, UUID, skin URL). See docs/AUTH_FLOW.md for the full
MSA → XBL → XSTS → Minecraft Services chain.
