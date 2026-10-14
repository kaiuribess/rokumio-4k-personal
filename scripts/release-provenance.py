"""Describe the exact validated build; publication must promote these bytes."""
import hashlib
import json
import os
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
package = root / "dist" / "rokumio-4k-personal.zip"
checks = json.loads((root / "verification" / "package-check.json").read_text(encoding="utf8"))
digest = hashlib.sha256(package.read_bytes()).hexdigest()
assert digest == checks["sha256"], "ZIP changed after package validation"
assert checks["version"] == json.loads((root / "package.json").read_text(encoding="utf8"))["version"], "Package/source version mismatch"
commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
expected = os.environ.get("GITHUB_SHA")
assert not expected or expected == commit, "Build is not the checked-out CI commit"
filename = "rokumio-4k-personal-" + checks["version"] + ".zip"
record = {"version": checks["version"], "commit": commit, "sha256": digest,
          "sizeBytes": package.stat().st_size, "releaseFilename": filename,
          "ciRunId": os.environ.get("GITHUB_RUN_ID"), "ciRunAttempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
          "publicationPolicy": "Promote the exact ZIP from this tested CI artifact; do not rebuild for Releases.",
          "hardwareValidation": "Not performed; software tests and package checks only."}
destination = root / "verification"
(destination / (filename + ".sha256")).write_text(digest + "  " + filename + "\n", encoding="utf8")
(destination / "artifact-provenance.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf8")
print(json.dumps(record, indent=2))
