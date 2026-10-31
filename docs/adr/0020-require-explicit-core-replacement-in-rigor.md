# Require explicit core replacement in Rigor

The first release requires a Rigor interface that replaces its core signature directory. RBS Shifter supplies the signatures and the directory selected for the target; Rigor explicitly loads that directory instead of its default core. We do not use runtime monkey patches or additive signature loading as a replacement mechanism.

Source inspection on 2026-10-21 found that installed Rigor 0.4.2 constructs its default RBS environment loader without selecting a core directory. RBS 4.2.0 exposes `RBS::EnvironmentLoader`'s `core_root:` argument, but the inspected Rigor loader does not pass it through. This is required consumer work, not an existing integration guarantee.

Rigor's `master` gained a `core_root:` configuration key on 2026-10-31 (rigortype/rigor#2518). It passes the directory to `RBS::EnvironmentLoader` in place of the default core and fails rather than falling back when the directory is unusable. That key is not in a released Rigor yet.
