# Critique AI 2.0

Public source mirror: [Dash1971/critique-ai-2](https://github.com/Dash1971/critique-ai-2).

Independent native application under development. No subscriptions or paywalls.
Distribution target: TestFlight only. This repository is not LockIn and does not
reuse LockIn's app identifier, signing runner or storage.

This repository is a reviewed source mirror, not a complete release.
Model weights, downloaded runtime sources, build products, device evidence,
credentials and local historical planning notes are not committed.

## Current state

**Unfinished application; nothing has been uploaded to TestFlight.** The owner
confirmed iPhone 13. Its physical performance remains untested.

- `CritiqueAI2`: real persistent tracker modules. Expanded unsigned iPhone and
  simulator builds passed. The reminder-enabled device build passed. One
  habit/meal/focus persistence UI test and a goal/workout/calendar flow passed.
  The hidden save-error alert was fixed and its regression passed. The main
  coach now generates from saved tracker records and saves checked conversation
  history; a native simulator check passed. All three tracker UI regressions
  passed after integration. An additional profile/settings navigation check
  exposed draft loss; the fix, focused UI regression and updated iPhone build
  passed.
- `CritiqueEvaluation`: clearly labeled synthetic local-coach harness, now using
  a pinned 696 MB model, grammar-constrained proposals, app-owned factual text,
  Swift validation and explicit nonmedical/capability boundaries. Its iPhone
  and simulator builds passed. No model is release-approved.
- 33 core tests and 30 host runtime checks passed. These are not real-iPhone
  memory, speed, battery or thermal acceptance.
- Optional social/sync, desktop, native screen-time integration, full UI coverage,
  AI quality/lifecycle acceptance and release preparation remain incomplete.
  No server is exposed.

See `Docs/20261123_v0_delivery_acceptance.md` for verified scope, release-blocking
model-review caveats and current gaps. Detailed local trial evidence and
historical development notes are not published. Large models/build evidence
remain outside Git under ignored `local/` and `build/`.

## Reproducible evaluation build

Prerequisites: Xcode with iOS SDK, CMake, Python 3, and Ruby `xcodeproj`.
Use the exact source/model revisions in the candidate manifest. Large downloads,
build products and device evidence belong under ignored `local/` and `build/`.
Verify the selected model size/SHA-256 against the pinned candidate manifest.
The current evaluation selection is `LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf`; it is
an experimental candidate, not approved for release.

The runtime source must be extracted to
`local/vendor/llama.cpp-44d50873b56b568c28ef2ad8d6445069feaa9fbd`.
The observed GitHub source archive SHA-256 is
`c4ff42917031c3e4b8c7ca1ce3895283aaf24e18c6985d64d7006ef9a7f5cae4`.
Source provenance is distinct from an upstream signed release attestation.

For a fresh clone, download the pinned assets separately:

```sh
mkdir -p local/vendor local/models
curl -fL https://github.com/ggml-org/llama.cpp/archive/44d50873b56b568c28ef2ad8d6445069feaa9fbd.tar.gz -o local/runtime-source.tar.gz
shasum -a 256 local/runtime-source.tar.gz
# Compare with the source archive SHA-256 above before extracting.
tar -xzf local/runtime-source.tar.gz -C local/vendor
curl -fL https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/8ed288026e23958ad9dfa92d53ed773a8eee7125/LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf -o local/models/LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf
shasum -a 256 local/models/LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf
```

Verify the model is exactly 695,755,488 bytes with SHA-256
`bb741ebb106d543e9de114b843a3d3d73d51c74b5801e69da2abde821a0cb3e1`
before loading it. Do not rerun the example downloads over existing local work.
The commands are a fresh-checkout recipe, not a claim of a clean-room rebuild.

```sh
python3 scripts/build_evaluation_runtime.py host
cmake --build build/runtime-host --config Release --target critique-bridge-tests -j 2
build/runtime-host/bin/critique-bridge-tests local/models/LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf
build/runtime-host/bin/critique-coach local/models/LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf
python3 scripts/build_evaluation_runtime.py ios
python3 scripts/build_evaluation_runtime.py sim
python3 scripts/build_evaluation_runtime.py package
xcodebuild -project CritiqueEvaluation.xcodeproj -scheme CritiqueAI2 \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/app-device CODE_SIGNING_ALLOWED=NO build
```

The checked-in project already contains both app targets. Generator scripts are
for creating new projects/targets and refuse to overwrite existing ones. The
simulator runtime slice is x86_64 for the current build host; add/test arm64
simulator support deliberately if needed on another host. No signing, Apple
registration, GitHub publication or TestFlight upload is performed by these
commands. Do not include source downloads or model binaries in Git history.

The evaluation project explicitly selects x86_64 for its simulator SDK, matching
the packaged simulator slice; its actual iPhone build remains arm64. A generic
multi-architecture simulator build cannot link an unbuilt arm64 simulator slice.

## Measurements and privacy

The evaluation screen reports its hardware identifier/OS, recorded model load,
first-token latency and generation duration. Completed requests write local
diagnostic metrics; sharing those metrics is explicitly user initiated. They
exclude prompt/answer text, account IDs and serial numbers. The app samples
process physical footprint every 250 ms, which can miss short spikes
and is not an Instruments-certified peak or thermal/battery acceptance result.
All model operations run on a serial background queue; cancellation and queued
release protect context lifetime. Foreground departure and memory pressure
cancel generation and release the model. No silent cloud fallback exists.

Host CPU inference and simulator execution are compatibility checks, not an
iPhone performance result. The physical target is confirmed as iPhone 13.
The complete 60-case quality review and real-device lifecycle/resource
checks in the acceptance ledger are release gates, not claims of completed testing.

## Parked cloud-adapter experiment

`backend/` contains an offline-tested Maple adapter from an earlier architecture
experiment. It is not connected to either app, does not start a server, contains
no provider credential and is not a deployed authenticated API. The active app
uses the bundled on-device runtime only; there is no cloud fallback.

## License

Original project code is licensed under the [MIT License](LICENSE).
Third-party runtime dependencies, model weights and license notices retain
their respective licenses; MIT licensing does not relicense those components.
See `Resources/ThirdParty/` and the pinned model manifest.
