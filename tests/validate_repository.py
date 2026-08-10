#!/usr/bin/env python3
"""Dependency-free release checks for this Codex plugin repository."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKILL_DIR = ROOT / "skills" / "vscode-remote-codex-proxy"
REQUIRED = [
    ".codex-plugin/plugin.json",
    "README.md",
    "LICENSE",
    ".gitignore",
    ".gitattributes",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "skills/vscode-remote-codex-proxy/SKILL.md",
    "skills/vscode-remote-codex-proxy/agents/openai.yaml",
    "skills/vscode-remote-codex-proxy/references/control-loop.md",
    "skills/vscode-remote-codex-proxy/references/failure-modes.md",
    "skills/vscode-remote-codex-proxy/scripts/Inspect-CodexProxy.ps1",
    "skills/vscode-remote-codex-proxy/scripts/inspect_remote_codex.sh",
    "skills/vscode-remote-codex-proxy/scripts/repair_codex_proxy_wrapper.sh",
    "skills/vscode-remote-codex-proxy/evals/evals.json",
    ".github/workflows/validate.yml",
]

TEXT_SUFFIXES = {".md", ".json", ".yaml", ".yml", ".py", ".ps1", ".sh"}


def fail(message: str) -> None:
    print(f"FAIL | {message}", file=sys.stderr)
    raise SystemExit(1)


def read_utf8(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        fail(f"not UTF-8: {path.relative_to(ROOT)} ({exc})")


for relative in REQUIRED:
    if not (ROOT / relative).is_file():
        fail(f"required file missing: {relative}")

manifest = json.loads(read_utf8(ROOT / ".codex-plugin/plugin.json"))
for key in ("name", "version", "description", "skills"):
    if not manifest.get(key):
        fail(f"plugin manifest missing: {key}")
if manifest["name"] != "vscode-remote-codex-proxy":
    fail("plugin name is not stable")
if manifest["skills"] != "./skills/":
    fail("plugin skills path must be ./skills/")

skill_text = read_utf8(SKILL_DIR / "SKILL.md")
frontmatter = re.match(r"\A---\n(.*?)\n---\n", skill_text, re.DOTALL)
if not frontmatter:
    fail("SKILL.md YAML frontmatter is missing or malformed")

metadata_lines = [line for line in frontmatter.group(1).splitlines() if line.strip()]
metadata = {}
for line in metadata_lines:
    if ":" not in line:
        fail(f"invalid SKILL.md frontmatter line: {line}")
    key, value = line.split(":", 1)
    metadata[key.strip()] = value.strip()

if set(metadata) != {"name", "description"}:
    fail("SKILL.md frontmatter must contain only name and description")
if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", metadata["name"]):
    fail("skill name must be lowercase hyphen-case")
if len(metadata["name"]) > 64:
    fail("skill name exceeds 64 characters")
if not metadata["description"]:
    fail("skill description is empty")
if len(skill_text.splitlines()) > 500:
    fail("SKILL.md exceeds 500 lines")

if metadata["name"] != manifest["name"]:
    fail("plugin and skill names differ")

evals = json.loads(read_utf8(SKILL_DIR / "evals/evals.json"))
if evals.get("skill_name") != metadata["name"]:
    fail("evals skill_name does not match SKILL.md")
if not isinstance(evals.get("evals"), list) or not evals["evals"]:
    fail("evals/evals.json has no evaluation cases")
eval_ids = set()
for case in evals["evals"]:
    if not isinstance(case, dict):
        fail("eval case must be an object")
    for field in ("id", "prompt", "expected_output", "expectations", "files"):
        if field not in case:
            fail(f"eval case missing {field}: {case.get('id', '?')}")
    if case["id"] in eval_ids:
        fail(f"duplicate eval id: {case['id']}")
    eval_ids.add(case["id"])
    if not isinstance(case["expectations"], list) or len(case["expectations"]) < 3:
        fail(f"eval case needs at least three expectations: {case['id']}")
    if not all(isinstance(item, str) and item.strip() for item in case["expectations"]):
        fail(f"eval case contains an empty expectation: {case['id']}")

openai_yaml = read_utf8(SKILL_DIR / "agents/openai.yaml")
for required_fragment in (
    "interface:",
    'display_name: "',
    'short_description: "',
    f"$%s" % metadata["name"],
    "allow_implicit_invocation: false",
):
    if required_fragment not in openai_yaml:
        fail(f"agents/openai.yaml missing: {required_fragment}")

for relative in REQUIRED:
    path = ROOT / relative
    if path.suffix.lower() in TEXT_SUFFIXES or path.name in {"LICENSE", ".gitignore", ".gitattributes"}:
        read_utf8(path)

markdown_files = [ROOT / "README.md", SKILL_DIR / "SKILL.md", ROOT / "CONTRIBUTING.md", ROOT / "SECURITY.md"]
markdown_files.extend((SKILL_DIR / "references").glob("*.md"))
for markdown in markdown_files:
    text = read_utf8(markdown)
    for link in re.findall(r"\[[^\]]+\]\(([^)]+)\)", text):
        if "://" in link or link.startswith("#"):
            continue
        target = (markdown.parent / link.split("#", 1)[0]).resolve()
        if not target.exists():
            fail(f"broken local link in {markdown.relative_to(ROOT)}: {link}")

for shell_script in (SKILL_DIR / "scripts").glob("*.sh"):
    if b"\r\n" in shell_script.read_bytes():
        fail(f"Bash script must use LF line endings: {shell_script.name}")

readme = read_utf8(ROOT / "README.md")
for forbidden in ("<REPOSITORY_URL>", "git clone <", "$HOME\\.codex\\skills\\vscode-remote-codex-proxy"):
    if forbidden in readme:
        fail(f"README contains unreleased placeholder or stale install path: {forbidden}")

index = subprocess.run(
    ["git", "ls-files", "--stage"], cwd=ROOT, check=True, text=True, capture_output=True
).stdout
for relative in (
    "skills/vscode-remote-codex-proxy/scripts/inspect_remote_codex.sh",
    "skills/vscode-remote-codex-proxy/scripts/repair_codex_proxy_wrapper.sh",
    "tests/inspect-remote-fixture.sh",
    "tests/repair-wrapper-fixture.sh",
):
    if not re.search(rf"^100755 [0-9a-f]+ 0\t{re.escape(relative)}$", index, re.MULTILINE):
        fail(f"Git executable bit missing: {relative}")

print(
    f"PASS | plugin repository | plugin={manifest['name']} "
    f"version={manifest['version']} evals={len(evals['evals'])}"
)
