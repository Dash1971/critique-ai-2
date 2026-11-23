#!/usr/bin/env python3
"""Run a pinned model on synthetic cases, preserving trial inputs and results.

Generation success is deliberately separate from human-reviewed quality.
This runner never signs, uploads, starts a listener or uses cloud fallback.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(4 * 1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trial", help="Unique lowercase trial label; existing trials are never overwritten")
    parser.add_argument("--model", required=True, help="Filename in the pinned model manifest")
    parser.add_argument("--cases", type=Path, required=True, help="Synthetic corpus JSON")
    parser.add_argument("--policy", type=Path, required=True)
    parser.add_argument("--contract", action="store_true", help="Constrain JSON structure and fact IDs; use 256 output tokens")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,79}", args.trial):
        parser.error("Use a short lowercase trial label")
    manifest = json.loads((ROOT / "Docs/20261123_v0_local_model_candidates.json").read_text())
    model = next((item for item in manifest["candidates"] if item["filename"] == args.model), None)
    if model is None:
        parser.error("Pin the candidate before evaluating it")
    weights = ROOT / "local/models" / args.model
    if weights.stat().st_size != model["bytes"] or digest(weights) != model["sha256_publisher_metadata"]:
        raise RuntimeError("Model verification failed")
    binary = ROOT / "build/runtime-host/bin/critique-coach"
    cases = json.loads(args.cases.read_text())
    ids = [item["id"] for item in cases["cases"]]
    if len(ids) != len(set(ids)):
        raise RuntimeError("Duplicate evaluation case identifiers")
    destination = ROOT / "build/verification/trials" / args.trial
    destination.mkdir(parents=True, exist_ok=False)
    inputs = destination / "inputs"
    inputs.mkdir()
    shutil.copyfile(args.cases, inputs / "cases.json")
    shutil.copyfile(args.policy, inputs / "policy.txt")
    source_hashes = {}
    for path in sorted((ROOT / "Runtime").rglob("*")):
        if path.is_file():
            target = inputs / path.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
            source_hashes[str(path.relative_to(ROOT))] = digest(path)
    result = {"status": "running", "started_at_utc": now(), "model": model,
              "runtime_binary_sha256": digest(binary), "runtime_source_hashes": source_hashes,
              "policy_sha256": digest(inputs / "policy.txt"), "cases_sha256": digest(inputs / "cases.json"),
              "case_ids": ids, "case_count": len(ids), "quality_review": "pending",
              "execution_device": "host CPU, not an iPhone benchmark", "cloud_fallback": False,
              "constrained_json": args.contract, "max_output_tokens": 256 if args.contract else 160}
    report = destination / "trial.json"
    report.write_text(json.dumps(result, indent=2) + "\n")
    with (destination / "answers.jsonl").open("w") as output, (destination / "stderr.log").open("w") as error:
        command = [str(binary), str(weights), "--cases", str(inputs / "cases.json"), "--policy", str(inputs / "policy.txt")]
        if args.contract:
            command.append("--contract")
        run = subprocess.run(command, cwd=ROOT, stdout=output, stderr=error)
    rows = [json.loads(line) for line in (destination / "answers.jsonl").read_text().splitlines() if line.strip()]
    result.update(status="generation_completed" if run.returncode == 0 else "generation_interrupted_or_failed",
                  finished_at_utc=now(), process_exit_code=run.returncode, responses_generated=len(rows),
                  request_errors=sum(row["status"] != 0 for row in rows),
                  outputs_at_limit=sum(row["truncated"] for row in rows))
    report.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"trial": args.trial, "generated": len(rows), "total": len(ids),
                      "request_errors": result["request_errors"], "quality_review": "pending"}))
    raise SystemExit(run.returncode if run.returncode >= 0 else 1)


if __name__ == "__main__":
    main()
