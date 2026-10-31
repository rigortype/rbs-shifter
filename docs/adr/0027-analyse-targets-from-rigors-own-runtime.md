# Analyse targets from Rigor's own runtime

Rigor runs only on Ruby 4.0 (its gemspec requires `>= 4.0.0, < 4.1`), so the guarantee in ADR-21, which requires Rigor to run on the exact Target Ruby, can never hold. Instead, Rigor runs on its own supported Ruby and the target is selected through configuration. `core_root:` names the packaged core for the branch, and `target_ruby:` names the recorded Target Ruby. `rigor_options` therefore no longer checks the running Ruby or platform. Runtime behaviour on each target is still checked by the native probes, which run on that exact Target Ruby on Linux x86_64 (ADR-10, ADR-24).

The guarantee covers core signature selection only. Rigor evaluates `RUBY_VERSION` comparisons against its own runtime version, not against `target_ruby:`. It also loads its own core overlays on top of the selected core. A code path behind a version check, and an API declared only by an overlay, are therefore not reported for the target. These are Rigor-side gaps outside this guarantee.

This supersedes ADR-21 and keeps explicit branch selection (ADR-18).
