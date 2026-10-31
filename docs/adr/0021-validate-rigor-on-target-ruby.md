# Validate Rigor on Target Ruby

Superseded by ADR-27: Rigor runs only on Ruby 4.0, so it cannot run on an older Target Ruby.

The first release guarantees Rigor integration when Rigor runs on the exact validated Target Ruby. Consumers still select the target branch explicitly. Full analysis from a different Ruby version is outside the initial guarantee, because the inspected Rigor 0.4.2 version guards use the analyzer's runtime version rather than its configured target.

This narrows the integration scope in ADR-11 without changing explicit signature selection in ADR-18. Broader cross-version analysis requires further Rigor support and validation.
