# Native pinned-producer JSON canonicalization repair

Same r81-plan96 assignment, sole writer and Forge2.12.1/9875333. Specific decision6101549357 authorizes cumulative round5; consumed5/max5/remaining0. PR147/148 stay closed. Repair starts at a905771; canonical PATCH2.8.16 to2.8.17 under the separately retained round5 version operation.

## Exact contract matrix

| Native caller | Pinned producer contract | Encoding |
| --- | --- | --- |
| Advice request/context/output/history; Mission definition/catalog/package/resolve | forge.advisory_contract.digest | ASCII escaped |
| Candidate proposal/registration/current candidate; decision/planning receipts | forge.advisory_contract.digest | ASCII escaped |
| Lifecycle evidence content_digest | forge.lifecycle.store._dump | UTF-8 |
| Mission candidate subject_revision and mission_spec_digest | forge.models.criterion_observation.canonical_digest | UTF-8 |
| Workset package/release key | forge.advisory_contract.digest | ASCII escaped |
| Workset definition/membership revision; worklist projection and control request | existing canonical workset/worklist contract | UTF-8 |

Both use recursive Unicode scalar lexical key order and unchanged arrays, with compact JSON and preserved strings, boolean/integer/null meaning. They remain separate contracts, not digest fallback candidates. The serializer rejects unsupported floating values and nonstring object keys. NSDictionary is retained during serialization so Unicode-equivalent key spellings are not collapsed by Swift dictionary conversion.

## Reproduction and vectors

The retained real recovery capability from exact final-main2.8.16 returns HTTP200 and passes pinned schema/scope. Its dependency graph contains candidate-22f… and candidate-8d… keys. Foundation sortedKeys reverses the required lexical order. Old native context digest41436f… differs from producer34abf4… for the same semantic object. Existing genuine response is reused without generating new Missions, model turns or successful canonical decisions.

Committed six byte/digest vectors were generated with the actual pinned noneditable Forge2.12.1 advisory digest and criterion_observation UTF-8 digest. Cases cover numeric/prefix/case keys, nested objects/arrays, integer/boolean/null, Unicode-equivalent key spellings, supplementary Unicode and escaping, plus that preserved genuine context/capability. Native tests compare both exact canonical byte strings and SHA256s, insertion order independence, meaningful array order, preserved capability acceptance and changed/scope-foreign rejection. Unsupported type tests remain fail closed.

Original new regression was red on unchanged a905 source: five digest mismatches, including genuine response. Four expanded native tests pass on the current repair. Initial test compilation error and all red logs retained. New CanonicalJSON.swift is added to the unchanged strict >80.2% perfile coverage gate.

## Actual repair validation

Initial four focused tests PASS; final11 linked canonical/Mission/Unicodeplanning tests PASS. Independent byte/caller matrix PASS on final matching production SHA256s, including31 explicit pinned-producer checks for the completed declared Unicode fixture. Fault reintroduction with the original sorting route fails the genuine preserved graph case. Final full owning validate PASS198native+1isolated, new CanonicalJSON100% executable-line coverage and all gated files strictly>80.2%. Standard TDE PASS/zero triggered rules and repositoryQUALIFIED under unchanged policy/runtime. All failed setup/test logs remain preserved.

The small caller review discovered Workset Architecture planning wrongly using UTF8; new declared Unicodeplanning regression was first red2failures and then green using required ASCII. Mission lifecycle receipts now use pinned UTF8. Workset lifecycle receipts already use UTF8. Existing declared Unicodeplanning unit fixture was corrected to the actual pinned algorithm and complete lifecycle references, with old original retained; this is unit data, not a new canonical decision. Earlier196+1/ee63 Quality/Security PASS remains historical and is superseded for source admission by fresh reviews on final bytes. Failed198-test run (old golden contract plus unchanged short timer scheduling) retained; final full198+1 succeeds with no assertion/timeout/coverage weakening.

## Delivery boundary

Independent small vector/caller review, full validation/coverage, independent whole-delta Quality/Security, required CI, protected repair merge, nonempty reviewed finalization and NEW exact-final-main installed/GUI/recovery acceptance remain mandatory. Earlier2.8.16 proofs retain their original identity. No producer upgrade, live EP, paid model, signing, credentials, old roots/grants or operational budgets changed.

## Specific round6 continuation

Direct user authorization after specific cumulative-max6 request, pickup6106126074; consumed6/max6/remaining0 before source edit, original5 and all operation budgets retained. Existing repair PR149/candidate2.8.17 remains, no new allocation or duplicate version bump. Server Architecture planning_digest joins now use existing ASCII digest, aligned with native and exact pinned Forge. The former Python positive Unicode test mirrored incorrect UTF8; it now uses actual ASCII and explicitly rejects incorrect UTF8 and missing proof.

New red INVALID_RESPONSE preserved; full12contracttestsPASS, isolated original-fault reintroduction detected with unchanged productbytes. Independent bounded full consumer/native/producer encoding matrix PASS. Full validate198+1PASS/allrequiredproduction>80.2%, Pythoncontract99.50%; standardTDEPASS0rules/QUALIFIED unchanged. Prior450afa complete SecurityFAIL remains historical. Fresh complete head-bound reviews and all remaining delivery/installed/UX gates remain required; no source-only completion claim.

## Protected repair and documentary finalization

PR149 normally protected match-head squash merged reviewed58df198dfb1780cad46e7a442a54927509d6b5a8 to main88b19e341119c8c65c2bedbc37ddf3c371c44a0b; exact trees equal. Workspace2.8.17 single repairPATCH retained. Full original-delta independent QualityPASS/SecurityPASS, full198native+1isolated/requiredperfile>80.2%, allfiveCI PASS and downloadedexactheadstandardTDEPASS0rules/QUALIFIED under unchangedpolicy1.4.0/runtime1.1.1. Actual corrected ASCIIplanningpositive/incorrectUTF8negative and originalfault detection retained. Prior450afaFAIL and every earlier report/budget/evidence combination remain historical.

Same assignment/r81-plan96/solewriter/session and exactForge2.12.1/9875333. Specific user round6/pickup6106126074 consumed6/max6/remaining0, no automatic7 or operationalextension. PR147/148 stay closed; source/code/test/policy/version/operationbytes are unchanged by this ordinary nonempty documentary NO_BUMP finalization.

This closes source admission only. Separately reviewed finalization/CI/protectedmerge then NEWexact-final-main matching native/noneditableServer/pinnedForge recovery/A→B/final acceptance/quota/idle/future-onlydisarm/denial/fullUX/keyboard/five-language-theme-narrow screenshots and reachable immutable proof remain mandatory and NOT YET QUALIFIED. Existing2.8.16 installed proofs keep their original identity. Old roots/grants are closed, primaryiCloud/usercredentials/oldrecords/budgets preserved; no new operational scope started yet.

## Plan96 specific user-authorized round7 — Mission Server UTF8 joins

Direct user continuation after concrete installed blocker6106404238 authorizes one integrated round7/max7; pickup6106571737 booked consumed7/max7/remaining0 BEFORE edits. Same sole writer/session/r81 assignment and exact Forge2.12.1/9875333. Protected main/base d978fe9; PR147–150 remain closed. Canonical PATCH2.8.17→2.8.18 operation L4-PLAN96-CORRECTION-ROUND7-20261011 preserves earlier artifacts and all operational budgets.

The actual unchanged approved Unicode Mission packet is rejected by old installed Server at Candidate/MissionSpec ASCII joins; independent reproduction retained. Three new meaningful Unicode regressions were red before correction. Candidate subject_revision, MissionSpec digest and lifecycle content now explicitly use pinned UTF8; outer package, registration, canonical decision and planning remain ASCII. New source accepts the preserved actual producer package; this is source regression evidence, not new installed qualification. Correct UTF8 positives and wrong ASCII/changed-meaning negatives pass in30 targeted Mission/workset tests.

Full owning bash scripts/validate.sh PASS:198 native+1 isolated, all required productionfiles strictly>80.2%, changed mission_contract175/180=97.22%. Independent bounded encoding matrix PASS:12 actual pinned vector comparisons plus unchanged real packet/correctUTF8/wrongASCII/changedmeaning/foreignactor checks. Original ASCII faults detected in isolated test process with productbytes unchanged. Standard TDE policy1.4.0 PASS/zero triggered rules, runtime1.1.1/repository QUALIFIED. Initial wrong PythonPATH and missing cloc adapter validation failures preserved; supported-runtime/required-adapter run passed without gate changes. Fresh full exact-head Quality/Security/CI/protectedrepair/finalization/NEWinstalled/fullUX remain pending.

Fresh complete independent exact-head Quality/Security, protected repair/nonempty finalization and NEW matching exact-final-main installed/runtime/recovery/fullUX/keyboard/five-language/screens evidence remain mandatory and pending. Earlier source/installed FAIL/PASS history remains bound to its own revision. No automatic eighth or operational extension, no new scope/grant at source admission.

## Plan96 protected Mission UTF8 repair — ordinary finalization

PR151 normally protected match-head squash merged reviewed53155f85cf84f6ff642f018b34fbca372ee8d570 to main d262cf8e8c6a2e8908edceea8629166845dda730; exact trees equal. Workspace2.8.18 canonical PATCH operation L4-PLAN96-CORRECTION-ROUND7-20261011 retained. Fresh full ORIGINAL-feature QualityPASS/SecurityPASS,198native+1isolated/allrequiredproduction>80.2%/mission_contract97.22%, allfiveCI PASS. Downloaded exactsourceTDE38121016961 standard policy1.4.0 PASS/zero triggeredrules, runtime1.1.1/repositoryQUALIFIED. Three originalASCII faults detected by meaningful Unicode regressions; actual unchanged preserved Forgepacket now accepted by source and independent bounded matrixPASS12vectors.

Same r81-plan96/assignment/session/sole writer and exactForge2.12.1/9875333. User-authorized round7 pickup6106571737 consumed7/max7/remaining0; original rounds/FAIL/PASS/budgets retained, no eighth or operational extension. PR147–151 stay closed. This ordinary nonempty NO_BUMP finalization changes only five owning documents, with product/test/policy/version/operation bytes unchanged.

Source admission is complete; this is not full installed/UX delivery. Finalization reviews/CI/protectedmerge then NEW matching exact-final-main native/noneditableServer/pinnedForge A→B/finalacceptance/quota/idle/future-onlydisarm/recovery/denied/expiry/fullUX/keyboard/five-language/theme/narrow screenshots/immutable reachable proof remain mandatory and NOT YET QUALIFIED. Prior d978 installedFAIL remains bound to its source; old roots/grants stopped and preserved. PrimaryiCloud/usercredentials/operational limits unchanged; no new qualifier scope started during source admission.
