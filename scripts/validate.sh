#!/usr/bin/env bash
set -euo pipefail

required=(README.md BOOTSTRAP.md AGENTS.md ENGINEERING_METHOD.md SECURITY.md WORKSPACE_PROVENANCE.md ROADMAP.md BACKLOG.md docs/ARCHITECTURE.md docs/REPOSITORY_ONBOARDING.md)
for file in "${required[@]}"; do
  test -s "$file"
done

python3 scripts/advance_product_version.py --check
python3 scripts/test_product_version_operations.py
python3 scripts/test_release_operation.py
python3 scripts/test_release_workflow_contract.py

python3 docs/ai-development/validate_projection.py \
  --profile workspace \
  --source-commit 6ec3b443c3ab3bdf76c626c2046d3778db570eb0 \
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

python3 scripts/test_role_aware_conversations_contract.py
python3 scripts/validate_role_aware_conversations_wc.py
python3 scripts/test_role_aware_conversations_wc.py
python3 scripts/validate_governed_progression_wc.py
python3 scripts/test_governed_progression_wc.py
python3 scripts/validate_policy_automation_wc.py
python3 scripts/test_policy_automation_wc.py
python3 scripts/validate_live_project_roadmap_wc.py
python3 scripts/test_live_project_roadmap_wc.py
python3 scripts/validate_project_bootstrap_w0.py
python3 scripts/test_project_bootstrap_w0.py
python3 scripts/validate_repository_health_wc.py
python3 scripts/test_repository_health_wc.py
python3 scripts/test_four_lane_entry.py
python3 scripts/test_ci_gates.py
python3 scripts/project_postman.py --check
python3 scripts/validate_runtime_coverage.py
python3 scripts/validate_wheel.py

echo 'Workspace validation passed.'
