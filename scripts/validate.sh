#!/usr/bin/env bash
set -euo pipefail

required=(README.md BOOTSTRAP.md AGENTS.md ENGINEERING_METHOD.md SECURITY.md WORKSPACE_PROVENANCE.md ROADMAP.md BACKLOG.md docs/ARCHITECTURE.md docs/REPOSITORY_ONBOARDING.md)
for file in "${required[@]}"; do
  test -s "$file"
done

python3 docs/ai-development/validate_projection.py \
  --profile workspace \
  --source-commit ec070e399ff4dbd92e760370002995fe4f4d52d6 \
  --extension-identity WORKSPACE_DEVELOPMENT_EXTENSION

grep -q 'peer of' README.md
grep -q 'NO_IMPLEMENTATION_HISTORY_EXISTS' WORKSPACE_PROVENANCE.md
grep -q 'does not become the Workspace source' WORKSPACE_PROVENANCE.md
grep -q 'Engineering Platform' docs/ARCHITECTURE.md
grep -q 'TDE' docs/ARCHITECTURE.md
grep -q 'Workspace Server owns shared, server-authoritative' docs/ARCHITECTURE.md
grep -q 'Local Project Agent API contract are EP-owned' docs/ARCHITECTURE.md
grep -q 'Status: proposed' docs/REPOSITORY_ONBOARDING.md
grep -q '.engineering-platform/repository.json' docs/REPOSITORY_ONBOARDING.md
test -s docs/governance/AI_DEVELOPMENT_CONTRACT_SEMANTIC_EQUIVALENCE_RECEIPT.md

echo 'Workspace foundation validation passed.'
