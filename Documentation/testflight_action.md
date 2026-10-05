# TestFlight Action

`.github/workflows/testflight.yml` archives the `Swiftfin` and `Swiftfin tvOS` schemes on the self-hosted Mac runner (`swiftfin-mac`) and uploads them to TestFlight with `xcodebuild`.

Signing and upload go through the Apple account signed in to Xcode on the runner's Mac (Xcode ▸ Settings ▸ Accounts) with automatic signing (`-allowProvisioningUpdates`), so **no secrets are needed**. The tvOS archive is built unsigned and signed for the App Store during export, so no registered Apple TV is required.

## Optional: App Store Connect API key

To sign with an API key instead (role **Admin**, which cloud-managed signing needs), add these repository secrets:

- `APP_STORE_KEY_ID`: Key ID
- `APP_STORE_ISSUER_ID`: Issuer ID
- `APP_STORE_KEY_CONTENTS`: the `.p8` file, as-is or base64-encoded

## Running

- Manually: Actions ▸ TestFlight ✈️ ▸ Run workflow (platform, optional version and build number).
- On every push to `main`: set the repository variable `TESTFLIGHT_ON_PUSH` to `true`.

The build number defaults to the UTC time (`yyyymmddHHMM`), so it always increases, including alongside uploads made from Xcode. The version defaults to the project's `MARKETING_VERSION`.
