# Workspace TDE complexity maintenance — r81 plan94

Direct owner-selected bounded maintenance after closed plan93. Same Worksession/solewriter, protected base25002017b15ae4efef01fa85cb4b569df07d2f88; branchcodex/workspace-tde-complexity. One PATCH operationL4-TDE-COMPLEXITY-V1-20261010 selects2.8.14. No credential, producer, policy, TDEsource or operational changes.

## Cause and correction

ExactmainTDE38016502274 had complexity39 and policyFAIL. Extract existing schema-value checks, project catalogue checks, committed member ordering, Mission catalogue/receipt/packet validation, and draft save preconditions into named helpers. All predicates and their error/state order remain unchanged; async epoch fencing stays at both helper return and caller commit. Swift explicit AdvisoryConnection constructor preserves behavior while correcting lizard1.23 shorthand-init symbol misparsing.

TDE blocks scores at30 (inclusive), unlike lizard standalone threshold reporting. The intermediate maximum30 still failed; the final source maximum28 passes with unchanged warning threshold15. Existing authorisation, corrupted schema/snapshot, stale async response, restart recovery and draft-race tests exercise the extracted paths. No weaker validation or omitted production.

## Actual local evidence

Published TDE1.1.1/defaultpolicy1.4.0, lizard1.23.0 and exactcloc2.10 sha256bf59272455172108072a0a106379f7509fd4349bdcfd85203bac038ccd286d83. Actual standardassessment policyPASS_WITH_WARNINGS, complete valid evidence; repositoryqualificationQUALIFIED/assessmentDecisionPASS_WITH_WARNINGS. Productmaximum28, warning15; warnings retained rather than labelled unconditionalPASS. Initial39/30FAIL and missingclocPATH qualificationBLOCKED attempts preserved. Priorplan93 policyFAIL remains historical and is not rewritten.

Initial whole160native+1isolated/allowninggates passed before the final draft-precondition extraction; final frozen-source wholevalidation runs again. Independent complete Quality/Security, ordinary requiredCI/protectedmerge and NEWactualfinalmainTDEpolicy/qualification/readback required before claiming deliverycomplete. No user GUI changes or new model/approval/admission; no new Forge fullmatrix qualification needed for pure behavior-preserving native refactoring.
