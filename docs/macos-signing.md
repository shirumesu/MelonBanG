# macOS development signing and credentials

For persistent login Keychain access across rebuilds, use an Apple-issued
Apple Development identity. Xcode Personal Teams support development with a free
Apple Account; Developer ID distribution and notarization require program membership.

A self-signed certificate stabilizes the designated requirement but is insufficient
for this Keychain guarantee. Apple Security's `partitionIdForProcess` still assigns
otherwise unclassified signed apps a `cdhash:` partition. A native two-build test
confirmed this: both builds had the same certificate and bundle requirement, but
the second build's quiet credential read was denied. Do not disable Keychain access
controls or promise that local self-signing alone fixes update-time authorization.

## Local development

1. Sign in to an Apple Account in Xcode Settings > Apple Accounts. A free account
   appears as a Personal Team. Complete account authentication and any agreements
   in Xcode.
2. Create `macos/Runner/Configs/Signing.local.xcconfig` with the local team:

   ```xcconfig
   CODE_SIGN_IDENTITY = Apple Development
   CODE_SIGN_STYLE = Automatic
   DEVELOPMENT_TEAM = YOUR_TEAM_ID
   ```

   The team identifier is available in Xcode's team configuration; on a configured
   Mac, `defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier` also
   lists it. This file is ignored by Git; do not commit personal team information.
3. Let Xcode create and manage the development identity for the project:

   ```sh
   flutter build macos --debug --config-only
   xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
     -configuration Debug -destination 'platform=macOS,arch=arm64' \
     -derivedDataPath build/macos -allowProvisioningUpdates -quiet build
   ```

   Personal Team's manual Create Certificate menu can be disabled even after
   login; project automatic signing works in that state. On the tested Mac,
   automatic signing created Apple Development without registering a device.
   If Xcode reports an account or provisioning problem, resolve the specific
   request rather than enabling unrelated capabilities or device registration.
4. Subsequent `flutter run`, tests and builds use the local configuration. Verify
   `codesign -d --verbose=4` reports an Apple Development authority and Team ID,
   then run the native credential rebuild test below.

The repository still builds ad-hoc without a local signing configuration. Keep
private keys in the system Keychain managed by Xcode. Do not create a parallel
self-signing workflow or relax login Keychain ACLs to suppress update prompts.
For CI or public release, supply appropriate signing settings and credentials
outside Git rather than copying the local development identity into the repository.

## Account behavior

Account tokens, OAuth secrets and the Xcode-managed signing identity stay in the
system Keychain as separate items. Startup and background renewal do not open
password dialogs. Settings reads a service's secrets only when that service is
explicitly edited; successful reads are cached for the process.

A temporarily inaccessible token produces a pending-authorization state. A cached
public account profile keeps the same local collection scope available; no token
or client secret is copied into SQLite. This profile is saved after the first
successful account recovery or login with the new version. An older installation
without that profile needs one successful recovery before offline identity can be
retained. Explicit logout removes the active profile and token while keeping the
account's local collection history.

Unlock Sync restores the token and authorizes the OAuth configuration needed for
renewal in the same interaction. The shell updates its account state before
attempting network synchronization, and retains it if synchronization fails.
Repeated clicks cannot start overlapping login flows. The operating system may
still request access to each old Keychain item when moving to an Apple-issued
certificate. Self-signed and ad-hoc rebuilds may require authorization again even
after Always Allow, because the Keychain partition also changes. The application
keeps local account data usable while this authorization is pending.

## Distribution and verification

Git hosting does not require an Apple Developer account. A public macOS binary
still benefits from Developer ID signing and notarization so Gatekeeper can verify
its source; local self-signing does not replace that distribution process.

`integration_test/credentials_test.dart` can verify persistence across two actual
builds signed with an Apple-issued identity, using a fresh test-only profile:

```sh
profile="$(mktemp -d)/credentials"
flutter test integration_test/credentials_test.dart -d macos \
  --dart-define=CREDENTIAL_REBUILD_PROFILE="$profile" \
  --dart-define=CREDENTIAL_REBUILD_PHASE=write
flutter test integration_test/credentials_test.dart -d macos \
  --dart-define=CREDENTIAL_REBUILD_PROFILE="$profile" \
  --dart-define=CREDENTIAL_REBUILD_PHASE=read
```

With an Apple-issued signing identity, the second build must restore the account
and read OAuth configuration with interaction disabled; it removes the test items afterward. Other cases verify
profile isolation and deferred ACL authorization. `account_recovery_test.dart`
checks the real shell with controlled credential/network failures, including a
successful unlock followed by failed collection synchronization.

References: [Apple Security partition implementation](https://github.com/apple-oss-distributions/Security/blob/main/securityd/src/clientid.cpp),
[free Personal Teams and paid distribution](https://developer.apple.com/support/compare-memberships/),
[Apple's signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements),
[macOS code signing and Keychain identity](https://developer.apple.com/library/archive/technotes/tn2206/),
[signing identities and distribution](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html).
