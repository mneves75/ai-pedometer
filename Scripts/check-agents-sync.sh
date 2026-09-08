#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "${1:-${ROOT_DIR}}" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
errors = []
agents_path = root / "AGENTS.md"
claude_path = root / "CLAUDE.md"
if not agents_path.is_file() or not claude_path.is_file():
    sys.exit("AGENTS.md and CLAUDE.md must both exist.")

agents = agents_path.read_text()
if not agents.startswith("# AGENTS.md\n") or not re.search(r"^## .+", agents, re.M):
    errors.append("AGENTS.md must contain its title and a structured contract.")
if len(agents.encode()) > 16000:
    errors.append("AGENTS.md exceeds the 16 KB local instruction budget; disclose task references.")
if claude_path.read_text().strip() != "@AGENTS.md":
    errors.append("CLAUDE.md must import @AGENTS.md without duplicating rules.")

headings = re.findall(r"^## (.+)$", agents, re.M)
if len(headings) != len(set(heading.casefold() for heading in headings)):
    errors.append("AGENTS.md contains duplicate sections.")
if "<skills_system" in agents or "SKILLS_TABLE_START" in agents:
    errors.append("Installed skill catalogs must not be copied into AGENTS.md.")

for link in re.findall(r"\[[^\]]+\]\(([^)]+)\)", agents):
    target = link.split("#", 1)[0]
    if not target or re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", target):
        continue
    resolved = (root / target).resolve()
    if not resolved.is_relative_to(root) or not resolved.is_file():
        errors.append(f"Missing or nonportable instruction reference: {target}")

if errors:
    sys.exit("\n".join(errors))
print("Agent instructions: canonical import, size, sections and local references passed.")
PY
