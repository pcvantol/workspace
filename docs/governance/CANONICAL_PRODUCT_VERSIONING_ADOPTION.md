# Canonical product versioning adoption

Workspace adopts Forge Platform's [canonical product versioning policy](https://github.com/pcvantol/forge-platform/blob/main/docs/architecture/CANONICAL_PRODUCT_VERSIONING.md), policy v1.

`product-version.json` is Workspace's only product-release version source. It
does not alter Workspace architecture, future EP adapter contracts or external
protocols. `scripts/advance_product_version.py` and the scoped `Canonical
product versioning` workflow are the only automatic mutators.
