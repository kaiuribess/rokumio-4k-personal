"""Verify the compiled Roku ZIP without installing it or accessing the device."""
import hashlib
import json
import re
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = ROOT / "dist" / "rokumio-4k-personal.zip"

def verify():
    with zipfile.ZipFile(PACKAGE) as archive:
        names = archive.namelist()
        assert archive.testzip() is None, "Corrupt ZIP member"
        assert len(names) == len(set(names)), "Duplicate ZIP paths"
        assert all(not name.startswith(("/", "\\")) and ".." not in Path(name).parts for name in names), "Unsafe ZIP path"
        for required in ("manifest", "LICENSE", "NOTICE.txt", "components/MainScene.xml", "source/main.brs"):
            assert required in names, "Missing " + required
        excluded = ("tests/", "node_modules/", ".git/", "scripts/", "verification/")
        assert not any(name.startswith(excluded) or name.endswith((".bs", ".log", ".map")) for name in names), "Development files in install ZIP"
        manifest = dict(line.split("=", 1) for line in archive.read("manifest").decode().splitlines() if "=" in line and not line.startswith("#"))
        assert manifest["ui_resolutions"] == "fhd", "Unexpected UI canvas"
        assert manifest["requires_mkv"] == "1", "MKV support not requested"
        assert manifest["supports_voice_roinput"] == "1", "Voice routing flag missing"
        assert all(re.fullmatch(r"\d+", manifest[key]) for key in ("major_version", "minor_version", "build_version")), "Invalid version"
        components = {}
        scripts = 0
        for name in names:
            if not name.endswith(".xml"): continue
            document = ET.fromstring(archive.read(name))
            component = document.get("name")
            assert component and component.lower() not in components, "Duplicate or missing component name"
            components[component.lower()] = name
            for item in document.iter():
                uri = item.get("uri", "")
                if uri.startswith("pkg:/"):
                    assert uri[5:] in names, f"Missing packaged reference from {name}: {uri}"
                    if item.tag == "script": scripts += 1
        # Node is also a native SceneGraph base; the source-list coordinator
        # owns fields/tasks without needing a visible Group.
        native = {"node", "scene", "group", "task", "contentnode", "dialog", "standarddialog", "standardkeyboarddialog", "keyboarddialog"}
        for name in components.values():
            parent = ET.fromstring(archive.read(name)).get("extends", "").lower()
            assert parent in native or parent in components, f"Unknown base component in {name}: {parent}"
        return {"package": "dist/rokumio-4k-personal.zip", "version": ".".join(manifest[key] for key in ("major_version", "minor_version", "build_version")),
                "sizeBytes": PACKAGE.stat().st_size, "sha256": hashlib.sha256(PACKAGE.read_bytes()).hexdigest(),
                "zipMembers": len(names), "xmlComponents": len(components), "resolvedScriptReferences": scripts,
                "zipIntegrity": "PASS", "manifest": "PASS", "xmlAndReferences": "PASS", "developmentFilesExcluded": "PASS",
                "scope": "Compiled package structure only; no installation, SceneGraph rendering or hardware decoding."}

if __name__ == "__main__":
    result = verify()
    destination = ROOT / "verification" / "package-check.json"
    destination.parent.mkdir(exist_ok=True)
    destination.write_text(json.dumps(result, indent=2), encoding="utf8")
    print(json.dumps(result, indent=2))
