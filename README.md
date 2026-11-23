# Critique AI 2.0

Native self-improvement tracker with persistent local storage and experimental
on-device coaching. No subscriptions or paywalls.

## Features

- Habits, goals, workouts, meals, water intake and focus sessions.
- Activity history, calendar, statistics, profiles and local reminders.
- Offline coaching based on saved tracker records, with validated structured
  output and persistent conversation history.

Development status: incomplete. Social features, cloud synchronization, desktop
support and automatic screen-time collection are not implemented. Model quality
and physical-device performance remain under evaluation.

## Code structure

- `Sources/CritiqueCore/`: Swift package for data models, SQLite persistence,
  statistics, reminders and coach validation. Can be built independently.
- `App/Main/`: SwiftUI tracker application (`CritiqueAI2` target).
- `App/LocalCoachEvaluationApp.swift`: synthetic-data model evaluation harness
  (`CritiqueEvaluation` target).
- `Runtime/`: C++ inference bridge using llama.cpp; iPhone Metal support,
  constrained JSON generation, cancellation and model lifecycle management.
- `Tests/`: core and UI tests.
- `scripts/`: runtime builds, project generation and evaluation tooling.
- `backend/`: standalone experimental Maple adapter; not used by the apps.

## Local model

The current candidate is **LFM2.5-1.2B-Instruct-QAD-Q4_0**, approximately 696 MB.
It runs in-process without a server, API key or cloud fallback. Application code
calculates statistics; the model proposes actions against those recorded facts.
Swift validation rejects unsupported output. Medical and unsupported-action
requests are outside the coach's scope.

Model revisions, sizes, checksums and licenses are recorded in
[the candidate manifest](Docs/20261123_v0_local_model_candidates.json).
The active selection is in [EvaluationModel.json](Resources/EvaluationModel.json).
Model weights and downloaded runtime sources are not included in Git.

## Build and test

Requirements: Xcode with the iOS SDK, CMake, Python 3 and Ruby `xcodeproj`.
The app targets iOS 17 or later. The packaged simulator configuration currently
supports Intel x86_64; Apple Silicon simulator support requires an arm64 slice
and corresponding project configuration.

Core package tests do not require model downloads:

```sh
swift test
```

For an app build, download the pinned runtime and model into a fresh checkout:

```sh
mkdir -p local/vendor local/models
curl -fL https://github.com/ggml-org/llama.cpp/archive/44d50873b56b568c28ef2ad8d6445069feaa9fbd.tar.gz -o local/runtime-source.tar.gz
shasum -a 256 local/runtime-source.tar.gz
# Verify the archive checksum below before extracting.
tar -xzf local/runtime-source.tar.gz -C local/vendor
curl -fL https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/8ed288026e23958ad9dfa92d53ed773a8eee7125/LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf -o local/models/LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf
shasum -a 256 local/models/LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf
```

Verify the model is exactly 695,755,488 bytes with SHA-256
`bb741ebb106d543e9de114b843a3d3d73d51c74b5801e69da2abde821a0cb3e1`
before loading it.

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

The runtime archive SHA-256 is
`c4ff42917031c3e4b8c7ca1ce3895283aaf24e18c6985d64d7006ef9a7f5cae4`.
The checked-in Xcode project contains both app targets. Project generators are
optional and refuse to overwrite existing projects. The commands above build
an unsigned iOS app; signing and distribution require separate configuration.

## Evaluation and privacy

The evaluation harness measures model loading, first-token latency, generation
duration and sampled process memory. Host and simulator results do not establish
physical-device performance. Exported diagnostic metrics exclude prompts,
responses, account identifiers and serial numbers. Sharing is user initiated.
Generation is cancelled and the model released on backgrounding or memory
pressure.

See the [acceptance ledger](Docs/20261123_v0_delivery_acceptance.md) for test
coverage and outstanding limitations. Generated models, runtime downloads and
build artifacts are excluded from version control.

## License

Original project code is [MIT-licensed](LICENSE). Third-party runtime components
and model weights retain their own licenses; see
[third-party notices](Resources/ThirdParty/) and the candidate manifest.
