#!/usr/bin/env bash
set -euo pipefail

required=(README.md BOOTSTRAP.md AGENTS.md ENGINEERING_METHOD.md SECURITY.md WORKSPACE_PROVENANCE.md ROADMAP.md BACKLOG.md docs/ARCHITECTURE.md)
for file in "${required[@]}"; do
  test -s "$file"
done

grep -q 'peer of' README.md
grep -q 'NO_IMPLEMENTATION_HISTORY_EXISTS' WORKSPACE_PROVENANCE.md
grep -q 'does not become the Workspace source' WORKSPACE_PROVENANCE.md
grep -q 'Engineering Platform' docs/ARCHITECTURE.md
grep -q 'TDE' docs/ARCHITECTURE.md

echo 'Workspace foundation validation passed.'
