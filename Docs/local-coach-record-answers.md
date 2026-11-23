# Local coach takeover checkpoint — 2026-11-24

Target: fully on-device coaching on iPhone 13. The existing LFM2.5 1.2B QAD Q4_0 weights and pinned llama.cpp revision are retained. The model remains evaluation-only; this change is not release approval.

## What changed

The previous grammar required an activity proposal for every question and forced `question` to null. Its policy also requested new activities regardless of the question. This made factual questions compete with a mandatory advice task. The native formatter additionally dropped validated clarifying questions.

The revised protocol declares `response_kind` before selecting evidence:

- `facts`: select the relevant app-owned facts, with no generated proposal or question.
- `plan`: propose activities when advice is requested, retaining the existing validation of generated actions.
- `clarification`: ask one relevant question, with no generated proposal.

Fact text is copied from the computed saved-record context. This is model-selected evidence presentation, not model-authored factual explanation or unrestricted conversational reasoning. Selected facts appear first; all remaining supplied evidence stays visible. Generated clarification text now reaches the same formatter used by the app and evaluation tool. Legacy trial output is still reviewable. Duplicate IDs in a supplied context now throw a recoverable error instead of trapping.

Whitespace is bounded to an optional space at each grammar boundary. An initial revised trial exposed repeated tab/newline generation until the token budget was exhausted; that failed attempt is retained separately. The final protocol did not truncate any of the 20 development/transfer requests.

## Observed evidence

All inference here used the Mac host CPU and synthetic records, not an iPhone or personal data. Sampling settings, model weights, input facts and questions were unchanged for the 12-case before/after comparison. Policy and grammar changed. Both versions were checked using the current Swift validator; the baseline was not remeasured with its old UI formatter.

| Check | Observed result |
| --- | --- |
| Production core/fixture exporter build | Passed with Swift 6.3.3 |
| Portable validator/presentation cases | 19/19 passed, including fact-only answers, visible questions, invalid modes, duplicate input IDs and legacy replies |
| Native C++ bridge checks | Passed with real CPU inference, framing, cancellation, reasoning filtering, context overflow and response-kind structure |
| Baseline development requests | 12 generated, 9 accepted by current contract |
| Final revised development requests | 12 generated without truncation, 11 accepted by contract |
| Additional transfer requests | 8 generated without truncation, 7 accepted by contract |
| XCTest suite | Could not run: installed Command Line Tools lack the XCTest module |
| SwiftUI app/device verification | Not performed: Xcode/iOS SDK and a connected test device are unavailable |

The empty-workout and perfect-reading examples now select the saved workout limitation and the two-of-seven reading count, respectively, without substituting activity advice. Additional histories produced the expected saved four-of-seven journaling count, seventeen against a hundred goal target, one in-window workout of seventeen minutes, twelve recorded protein grams, and unchanged goal progress despite a malicious goal title.

Output review still found material failures. The trend question did not select the missing-baseline limitation for the primary answer (it remains in the other supplied evidence). Focus advice was generic. One rest-day response suggested reviewing a nutrition log; another proposed a numeric warm-up duration in generated text. Both rest-day responses were rejected by existing action validation. Spanish practice advice remained broad and introduced an unprovided work task. These failures must remain visible in quality evaluation.

These are development regressions and follow-up transfer checks designed during this implementation, not an independent held-out quality score. They do not replace the earlier 60-case findings. Passing JSON/contract checks does not establish relevant or appropriate coaching.

## Reproduce

With the verified runtime/model already available as described in the README:

```sh
swift build --product critique-coach-fixtures
.build/debug/critique-coach-fixtures --verify-protocol Tests/CoachProtocolCases.json
mkdir -p build/verification
.build/debug/critique-coach-fixtures --contract --question-answering > build/verification/questions.json
.build/debug/critique-coach-fixtures --contract --answer-transfer > build/verification/transfer.json
python3 scripts/build_evaluation_runtime.py host
python3 scripts/run_model_evaluation.py unique-record-answer-trial \
  --model LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf \
  --cases build/verification/questions.json \
  --policy Resources/CoachPolicy.txt --contract
python3 scripts/review_contract_trial.py unique-record-answer-trial
cmake --build build/runtime-host --target critique-bridge-tests -j 2
build/runtime-host/bin/critique-bridge-tests local/models/LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf
```

Trial names must be new. The evaluation runner supports paired `--binary` and `--runtime-source` arguments to preserve and evaluate an earlier runtime with exact source provenance. Review reports include the actual checked display text, not only a structural acceptance count. Review each answer against its question and expectation.

The iOS XCFramework must be rebuilt before this grammar change can run in the native app. Core/CLI success does not prove that the native UI compiles or that model loading, memory, responsiveness, heat or battery behavior is acceptable on an iPhone 13.

## Remaining work

Priorities are the missing-baseline selection failure, practical plan quality, evidence omissions and maximum combined-context fit, independently curated relevance tests, and physical iPhone 13 acceptance. Conversation history is saved for reference but is not included in subsequent inference; the UI now states this limitation. No cloud provider, API billing or server fallback has been added.

