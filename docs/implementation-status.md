# Implementation status

Checked on 2026-10-21.

## Working development baseline

- Strict RBS syntax-tree transformations support adding, removing, and replacing
  members and declarations. Missing, changed, or ambiguous preconditions fail.
- The initial 23 rules adapt selected Ruby 3.4 and 4.0 core API differences.
- Generation produces both targets atomically, checks RBS references and types,
  checks reproducibility, and records source, rule, and output digests.
- The candidate gem contains both generated cores and upstream license notices.
- Explicit selection checks the exact RBS version, file set, checksums, and path
  confinement. Unsupported targets fail rather than selecting a fallback.
- The Rigor adapter exposes full-core replacement options with the recorded
  Target Ruby, independent of the Ruby that runs Rigor (ADR-27).
- Publication checks reject unresolved coverage and incomplete human-reviewed
  runtime or consumer evidence.
- A read-only updater detects changes to stable RBS, target Ruby patches, and
  maintenance status. A weekly CI job reports changes without editing rules.

## Observed verification

- The full suite passed on CRuby 3.3.12 on Linux x86_64: 73 tests and 494 assertions.
- All 23 native API probes passed on CRuby 3.3.12 and 3.4.11 on Linux x86_64.
  On 3.4, the probes also check APIs retained because the 3.3-only rules are inactive.
- The candidate gem built and installed into a temporary local gem home. Both
  packaged target cores loaded through `RBS::EnvironmentLoader` as replacements,
  and the removed `Array#rfind` was absent from both resulting environments.
- CLI help, generation, target listing, path selection, validation, unsupported
  target errors, and publication refusal were exercised directly.
- The updater queried the official sources successfully and found no changes
  needed in the recorded Source RBS, source Ruby, targets, or maintenance states.
- Ruby syntax checks passed. The host LSP could not run because it selected the
  system Ruby 2.6 for an executable installed under Ruby 4.0.6.
- GitHub Actions is configured; remote CI has not been run from this session.

The initial runtime driver incorrectly expected negative Hash capacity to raise
and compared backtrace location object identity. Direct CRuby 3.4.11 probes showed
that negative capacity is accepted and returned location objects can differ in
identity. The driver now checks the constructor result and frame data instead.

## Work required before a production release

The generated manifests remain candidates. The native probes cover the selected
rules; they do not establish full core API compatibility.

Complete the core audit, including Set and Pathname promotion, Ractor changes,
Fiber scheduler hooks, Range and RubyVM differences, and Time core versus stdlib
availability. Add evidence-backed rules and regression tests for every required
correction, including restored APIs and changed inheritance where needed.

Rigor's `core_root:` key replaces the default core and is on Rigor's `master`
(rigortype/rigor#2518), not yet released. On macOS arm64, a Rigor run against the
generated 3.3 and 3.4 cores reported the removed `Array#rfind` and the narrowed `String#strip`,
and reported neither against the default core. Verify positive and negative
type-checking examples on every exact supported target before claiming support.

Resolve the outstanding items in `rules/core.json`, then review runtime,
consumer, and coverage evidence for the exact candidate manifest before approving
publication. Nothing has been pushed or published.
