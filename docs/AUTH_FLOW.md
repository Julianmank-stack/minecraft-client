# Authentication Flow (Microsoft only)

MetalCraft supports **official Microsoft/Xbox/Minecraft authentication only**. No
cracked accounts, no password handling, no auth bypass.

## Flow: OAuth 2.0 Device Code (native-app friendly, no embedded webview)

```
Launcher                        Microsoft / Xbox / Mojang
   │
   │ 1. POST login.microsoftonline.com/consumers/oauth2/v2.0/devicecode
   │    client_id=<MSA client id>  scope=XboxLive.signin offline_access
   │◄── device_code, user_code, verification_uri
   │
   │ 2. Show user_code in a clean sheet; open verification_uri in default browser
   │    (user signs in on microsoft.com — launcher never sees the password)
   │
   │ 3. Poll POST /consumers/oauth2/v2.0/token (grant_type=device_code)
   │◄── MSA access_token + refresh_token
   │
   │ 4. POST user.auth.xboxlive.com/user/authenticate   (RpsTicket=d=<access_token>)
   │◄── XBL token + user hash (uhs)
   │
   │ 5. POST xsts.auth.xboxlive.com/xsts/authorize      (RelyingParty=rp://api.minecraftservices.com/)
   │◄── XSTS token          (XErr 2148916233 → no Xbox account; 2148916238 → child account)
   │
   │ 6. POST api.minecraftservices.com/authentication/login_with_xbox
   │    identityToken = "XBL3.0 x=<uhs>;<xsts>"
   │◄── Minecraft access token (24h)
   │
   │ 7. GET api.minecraftservices.com/minecraft/profile
   │◄── username, UUID, skins[], capes[]   (404 → account owns no copy of Minecraft)
```

## Storage

- **Keychain** (`dev.metalcraft.launcher`, `kSecClassGenericPassword`,
  `kSecAttrAccessibleAfterFirstUnlock`):
  - `<account-uuid>.msa` → MSA refresh token
  - `<account-uuid>.mc` → `{ accessToken, expiresAt }`
- `accounts.json` holds only public metadata (username, UUID, skin URL).
- Raw passwords are never seen and never stored anywhere.

## Refresh & expiry

- On launch or app start, if the MC token expires within 5 min: refresh MSA token
  with the stored refresh token → repeat steps 4–7 silently.
- If the refresh token is revoked/expired: mark the account "Sign-in required" and
  show the login sheet on next play.

## Errors → UI

| Condition | UI |
|-----------|----|
| Device-code poll timeout | "Sign-in timed out — try again" |
| XErr 2148916233 | "This Microsoft account has no Xbox profile — create one at xbox.com" |
| XErr 2148916238 | "Child accounts must be added to a family by an adult" |
| Profile 404 | "This account doesn't own Minecraft: Java Edition" + Buy link |
| Network failure | Retryable banner, exponential backoff |
