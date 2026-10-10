# Native pinned-producer JSON canonicalization repair

Same r81-plan96 assignment, sole writer and Forge2.12.1/9875333. Specific decision6101549357 authorizes cumulative round5; consumed5/max5/remaining0. PR147/148 stay closed. Repair starts at a905771; canonical PATCH2.8.16 to2.8.17 under the separately retained round5 version operation.

## Exact contract matrix

| Native caller | Pinned producer contract | Encoding |
| --- | --- | --- |
| Advice request/context/output/history; Mission definition/catalog/package/resolve | forge.advisory_contract.digest | ASCII escaped |
| Candidate proposal/registration/current candidate; decision/lifecycle/planning receipts | forge.advisory_contract.digest | ASCII escaped |
| Mission candidate subject_revision and mission_spec_digest | forge.models.criterion_observation.canonical_digest | UTF-8 |
| Workset package/release key | forge.advisory_contract.digest | ASCII escaped |
| Workset definition/membership revision; worklist projection and control request | existing canonical workset/worklist contract | UTF-8 |

Both use recursive Unicode scalar lexical key order and unchanged arrays, with compact JSON and preserved strings, boolean/integer/null meaning. They remain separate contracts, not digest fallback candidates. The serializer rejects unsupported floating values and nonstring object keys. NSDictionary is retained during serialization so Unicode-equivalent key spellings are not collapsed by Swift dictionary conversion.

## Reproduction and vectors

The retained real recovery capability from exact final-main2.8.16 returns HTTP200 and passes pinned schema/scope. Its dependency graph contains candidate-22f… and candidate-8d… keys. Foundation sortedKeys reverses the required lexical order. Old native context digest41436f… differs from producer34abf4… for the same semantic object. Existing genuine response is reused without generating new Missions, model turns or successful canonical decisions.

Committed six byte/digest vectors were generated with the actual pinned noneditable Forge2.12.1 advisory digest and criterion_observation UTF-8 digest. Cases cover numeric/prefix/case keys, nested objects/arrays, integer/boolean/null, Unicode-equivalent key spellings, supplementary Unicode and escaping, plus that preserved genuine context/capability. Native tests compare both exact canonical byte strings and SHA256s, insertion order independence, meaningful array order, preserved capability acceptance and changed/scope-foreign rejection. Unsupported type tests remain fail closed.

Original new regression was red on unchanged a905 source: five digest mismatches, including genuine response. Four expanded native tests pass on the current repair. Initial test compilation error and all red logs retained. New CanonicalJSON.swift is added to the unchanged strict >80.2% perfile coverage gate.

## Actual repair validation

Four focused tests PASS; independent byte/caller matrix PASS on matching production SHA256s. Fault reintroduction with the original sorting route fails the genuine preserved graph case. Full owning validate PASS196native+1isolated, new CanonicalJSON100% executable-line coverage and all gated files strictly>80.2%. Standard TDE PASS/zero triggered rules and repositoryQUALIFIED under unchanged policy/runtime. All failed setup/test logs remain preserved.

## Delivery boundary

Independent small vector/caller review, full validation/coverage, independent whole-delta Quality/Security, required CI, protected repair merge, nonempty reviewed finalization and NEW exact-final-main installed/GUI/recovery acceptance remain mandatory. Earlier2.8.16 proofs retain their original identity. No producer upgrade, live EP, paid model, signing, credentials, old roots/grants or operational budgets changed.
