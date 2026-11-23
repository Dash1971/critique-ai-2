# Critique AI 2.0 — OpenClaw TestFlight prototype handoff

This repository contains the native tracker and experimental on-device coach. It is suitable as the source for an early beta build, subject to successful native build, signing and device checks. No TestFlight archive or upload has been produced by this handoff. The original complete-app feature list is not yet fulfilled.

## Get the current changes

The local-coach changes are on `codex/local-coach-reliability`. Use that branch until it is merged into `main`:

```sh
git fetch origin
git switch codex/local-coach-reliability
```

The branch includes the latest goal-workflow commits available when it was pushed. Preserve any existing local work before switching a checkout. Do not regenerate the Xcode project or reuse a stale runtime build from before the grammar changes.

## App identity

| Setting | Use |
| --- | --- |
| Project | `CritiqueEvaluation.xcodeproj` |
| Distribution scheme / target | `CritiqueAI2` |
| App bundle ID | `com.dash1971.critiqueai2` |
| Display name | Critique AI 2.0 |
| Deployment target | iOS 17 or later |
| Version currently in source | 0.1.0, build 1; select an unused build number before upload |
| First physical test device | iPhone 13 |

Do not distribute the `CritiqueEvaluation` synthetic-data/model harness instead of the tracker.

## What the build machine must supply

The source, icon, manifests, model license notices, runtime bridge and build scripts are tracked. These machine/account dependencies are not supplied by Git:

- Full Xcode and the iOS SDK. Apple's current upload page lists Xcode 26 or later for building iOS uploads; check the current requirement before distributing. Command Line Tools alone cannot build/sign this app.
- CMake and Python 3. Ruby `xcodeproj` is needed only for the optional project-generation/editing scripts; the checked-in project already exists.
- The pinned llama.cpp source in `local/vendor/llama.cpp-44d50873b56b568c28ef2ad8d6445069feaa9fbd`.
- The exact 695,755,488-byte model at `local/models/LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf`, with the SHA-256 specified in the README and `Resources/EvaluationModel.json`.
- A freshly built `build/CritiqueRuntime.xcframework` containing the updated bridge/grammar. Downloads and build artifacts are intentionally Git-ignored; reuse matching verified artifacts or follow the README's pinned download/checksum instructions.
- An Apple Developer Program team, permission to distribute the app, available signing identity/provisioning, and authenticated Xcode or App Store Connect upload access. Those may already exist on OpenClaw's Mac, but their availability has not been verified here. No team ID is configured in the tracker target.
- An App Store Connect app record matching the bundle ID, plus appropriate TestFlight groups/test information. App Store Connect processing/compliance and any required external beta review are separate from a successful upload.

No AI API key or hosted inference service is needed for the current implementation. Apple signing keys, passwords, API keys and provisioning assets must remain outside Git.

## Build and verify before archive

From the repository root on the build Mac, verify Xcode selection and use the README to obtain and verify any missing model/runtime files. The following build commands do not upload anything:

```sh
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-path
swift test
swift build --product critique-coach-fixtures
.build/debug/critique-coach-fixtures --verify-protocol Tests/CoachProtocolCases.json
python3 scripts/build_evaluation_runtime.py ios
python3 scripts/build_evaluation_runtime.py sim
python3 scripts/build_evaluation_runtime.py package
xcodebuild -project CritiqueEvaluation.xcodeproj -scheme CritiqueAI2 \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/app-device CODE_SIGNING_ALLOWED=NO build
mkdir -p build/verification
python3 scripts/audit_tracker_build.py \
  --app build/app-device/Build/Products/Release-iphoneos/CritiqueAI2.app \
  --output build/verification/prototype-bundle-audit.json
```

Use a fresh audit output filename for each attempt. The runtime packager refuses to replace an existing XCFramework: preserve/move an older artifact and rebuild deliberately. Its iOS slice is arm64; its current simulator slice and project settings are x86_64. That simulator configuration needs an Intel-compatible test environment or a corresponding arm64 simulator configuration/build change on Apple Silicon; it is not evidence of iPhone 13 verification. Device archives use the arm64 device slice.

Install a development build on an iPhone 13 and check cold launch, trackers saving across relaunch, backup/restore, notification permission and coach load/generation/cancellation. Check memory pressure and background/foreground behavior. Keep the AI described as experimental in beta test notes. A rejected coach response must remain an error; do not insert a fabricated answer.

The latest local work passed core/fixture compilation, 19 portable protocol cases and native C++ host-inference bridge checks. Full XCTest and SwiftUI/iPhone checks did not run on the handoff machine because it has Command Line Tools without Xcode/XCTest. See [the detailed checkpoint](local-coach-record-answers.md) for actual model failures and the limits of the evidence.

## Signed archive and upload

Select the existing Apple team associated with the intended App Store Connect app. Supply its actual ID and a new build number in the shell environment; these values are not inferred by the repository:

```sh
export CRITIQUE_APPLE_TEAM_ID='YOUR_ACTUAL_TEAM_ID'
export CRITIQUE_BUILD_NUMBER='YOUR_UNUSED_BUILD_NUMBER'
xcodebuild -project CritiqueEvaluation.xcodeproj -scheme CritiqueAI2 \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "build/CritiqueAI2-${CRITIQUE_BUILD_NUMBER}.xcarchive" \
  DEVELOPMENT_TEAM="$CRITIQUE_APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION="$CRITIQUE_BUILD_NUMBER" \
  -allowProvisioningUpdates archive
```

This requires a working authorized signing account on that machine. Open the resulting archive in Xcode Organizer, validate it, then use Distribute App → App Store Connect → Upload with the intended account. Existing authorized automation can perform the equivalent export/upload using securely configured credentials.

After Apple processes the uploaded build, complete the applicable compliance/test information and assign it to the intended TestFlight group. For a first prototype, start with internal testing if the intended testers are eligible App Store Connect users; external testing requires the applicable TestFlight App Review. A successful archive or upload alone does not mean testers can install the build.

Record the source commit, version/build, archive result, upload result, App Store Connect processing status and confirmed TestFlight availability. Do not report delivery complete until the intended group can access the processed build.

## Apple references

- [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Upload builds, roles and supported Xcode versions](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
- [External testers and beta review](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)
