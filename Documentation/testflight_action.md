# TestFlight Action

`.github/workflows/testflight.yml` archives the `Swiftfin` and `Swiftfin tvOS` schemes on the self-hosted Mac runner (`swiftfin-mac`) and uploads them to TestFlight with `xcodebuild`.

Signing uses Xcode's automatic signing authenticated with an App Store Connect API key (`-allowProvisioningUpdates`): Xcode creates the cloud-managed distribution certificate and App Store profiles itself. No `.p12` or `.mobileprovision` secrets are needed.

## App Store Connect API Key

App Store Connect ▸ Users and Access ▸ Integrations ▸ App Store Connect API ▸ ➕, with role **Admin** (cloud-managed signing needs Admin). Download the `.p8` (only possible once).

Add these repository secrets:

- `APP_STORE_KEY_ID`: Key ID
- `APP_STORE_ISSUER_ID`: Issuer ID
- `APP_STORE_KEY_CONTENTS`: the `.p8` file, as-is or base64-encoded

```sh
gh secret set APP_STORE_KEY_ID --body XXXXXXXXXX
gh secret set APP_STORE_ISSUER_ID --body xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
gh secret set APP_STORE_KEY_CONTENTS < AuthKey_XXXXXXXXXX.p8
```

## Running

- Manually: Actions ▸ TestFlight ✈️ ▸ Run workflow (platform, optional version and build number).
- On every push to `main`: set the repository variable `TESTFLIGHT_ON_PUSH` to `true`.

The build number defaults to the workflow run number, so it always increases. The version defaults to the project's `MARKETING_VERSION`.
