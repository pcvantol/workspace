# Private signed candidate handoff

The `scripts/preserve_macos_app_candidate.py` command preserves one already
signed, notarized and stapled `Workspace.app` ZIP. It never signs, notarizes,
changes Keychain trust, or publishes a release. Run it only within an
independently authorized L1/L4 resource window, after the signed builder and
`verify_macos_app_candidate.py` have completed for the exact protected source.

Choose a **new** candidate directory beneath an existing owner-owned mode
`0700` directory in the user's home, outside the checkout and outside `/tmp`.
The tool copies the ZIP and its signed candidate manifest to a mode `0700`
staging directory with mode `0600` files, checks both copied SHA-256 digests,
then atomically publishes the directory. A failed staging copy is removed;
an existing destination is never deliberately reused. Preserve the printed
`handoff_sha256` separately as the expected receipt digest.

```sh
python3 scripts/preserve_macos_app_candidate.py preserve \
  --archive /absolute/private/path/Workspace.app.zip \
  --manifest /absolute/private/path/candidate-manifest.json \
  --destination /absolute/private/home/path/new-candidate-directory \
  --source-revision EXACT_PROTECTED_REVISION \
  --source-tree EXACT_PROTECTED_TREE \
  --builder-sha256 EXACT_BUILDER_SHA256 \
  --version 2.8.2 --team-id EXACT_TEAM_ID --leaf-sha1 EXACT_CERTIFICATE_SHA1
```

After a process restart or host restart, run `verify` with the same source,
tree, builder, version, Team ID and leaf SHA-1 arguments, the destination,
and `--handoff-sha256` set to the recorded digest. Reopen verifies private
permissions, exact file set, receipt, ZIP and manifest hashes, protected Git
source/tree/builder, native Developer ID signature and leaf, stapled ticket,
Gatekeeper acceptance, bundle identity and version, CDHash and notary
submission identity. Missing, altered, ad-hoc or mismatched material fails
closed. The receipt contains no signing identity private key, certificate
bytes, notary profile, token or Keychain value.

This handoff only qualifies preservation of signed candidate bytes. Signed
`.v2` Keychain successor/relaunch, native two-Mac HTTPS and scoped Forge read,
CURRENT Forge source, durable client trust and public release require their
own evidence and grants. The ad-hoc 2.8.2 control bundle exercises storage
and failure behavior only; it cannot satisfy `preserve` or `verify`.
