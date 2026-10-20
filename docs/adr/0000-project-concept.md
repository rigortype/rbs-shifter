# ADR-0: Shift RBS signatures to supported older Ruby versions

RBS Shifter adapts signatures from upstream RBS releases to match the actual APIs of older Ruby versions that are still supported according to Ruby Maintenance Branches. The goal is to keep useful upstream signature improvements while correcting differences in the APIs of each target Ruby version. A shift changes what the signatures describe, rather than only making their syntax parse.

Upstream RBS distinguishes the Ruby version described by its standard library signatures from the Ruby versions that can run its library code. Its README says that the signatures target the latest Ruby release, while the library code targets non-EOL Ruby versions.

ADR-1 through ADR-26 record the agreed support policy, signature scope, distribution model, transformation rules, consumer integration requirements, and validation requirements. These records describe the intended design; implementation and release validation are still required.

## Sources

Checked on 2026-10-21:

- [RBS target version policy](https://github.com/ruby/rbs#the-target-version)
- [Ruby Maintenance Branches](https://www.ruby-lang.org/en/downloads/branches/)
