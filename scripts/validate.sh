#!/usr/bin/env bash
set -euo pipefail

required=(README.md BOOTSTRAP.md AGENTS.md ENGINEERING_METHOD.md SECURITY.md WORKSPACE_PROVENANCE.md ROADMAP.md BACKLOG.md docs/ARCHITECTURE.md)
for file in "${required[@]}"; do
  test -s "$file"
done

grep -q 'first-class peer' README.md
grep -q 'No prior implementation history' WORKSPACE_PROVENANCE.md
grep -q 'does not own Workspace' WORKSPACE_PROVENANCE.md
grep -q 'Engineering Platform' docs/ARCHITECTURE.md
grep -q 'TDE' docs/ARCHITECTURE.md

echo 'Workspace foundation validation passed.'
