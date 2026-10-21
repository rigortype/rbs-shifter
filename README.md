# RBS Shifter

RBS Shifter adapts upstream RBS core signatures to maintained older Ruby APIs.
It applies evidence-backed changes to parsed RBS syntax trees and packages one
signature set per explicit target branch.

## Current status

This is a development prerelease, not a validated production release.
The initial 23 rules cover selected Ruby 3.4 and 4.0 API differences. Full core
coverage and real Rigor integration still need review and validation.
`rules/core.json` lists the unresolved work, and `release-check` blocks publication
while any item remains. Passing RBS validation alone does not establish API coverage.

The pinned Source RBS is 4.2.0. The target versions are CRuby 3.3.12 and 3.4.11;
the initial platform guarantee is Linux x86_64. The source API baseline is Ruby
4.0.7. See [ADR-0](docs/adr/0000-project-concept.md) and the later ADRs for the
agreed design.

## Develop

Use Ruby 3.3 or newer with Bundler:

```sh
bundle install
bundle exec rake test
bundle exec rake generate
bundle exec ruby exe/rbs-shifter targets --root build/data
bundle exec ruby exe/rbs-shifter path --root build/data --target 3.3
bundle exec ruby exe/rbs-shifter validate --root build/data
```

Generation always reads the pinned RBS gem's core and generates all configured
targets directly. It records input and output digests, the exact target versions,
and the rule revision. Output is staged until all targets pass RBS validation and
reproducibility checks. An existing output directory is never overwritten; use a
new `--output` directory for another run.

Unknown targets, changed rule preconditions, ambiguous declarations, missing files,
and invalid output references are errors. A rule can add, remove, or replace a
member or declaration, including older APIs and inheritance changes.

Run native API regression checks on each exact target on Linux x86_64:

```sh
ruby script/check-runtime.rb build/data 3.3
ruby script/check-runtime.rb build/data 3.4
```

Each command must run under its selected target Ruby. The driver checks actual
runtime behavior for the bundled rules. It does not prove full core coverage or
Rigor compatibility.

## Build and use a candidate gem

```sh
bundle exec rake build
gem install --local pkg/rbs-shifter-0.1.0.pre.1.gem
rbs-shifter targets
rbs-shifter path --target 3.3
```

The build generates and validates all targets in a temporary staging directory.
The gem includes the generated signatures, manifest, and upstream RBS license
notices. Generated signature files are not tracked in this source repository.
Building this prerelease is not permission to publish it.

For explicit full-core replacement with RBS:

```ruby
require "rbs/shifter"

core = RBS::Shifter.core_root(target: "3.3")
loader = RBS::EnvironmentLoader.new(core_root: core)
environment = RBS::Environment.from_loader(loader).resolve_type_names
```

The loaded RBS version must exactly match Source RBS. Selection checks the full
file set and SHA-256 digests. It never selects a target from the host Ruby or
falls back to another branch. Standard library signature version compatibility
is outside the initial core guarantee.

## Proposed Rigor integration

See [the proposed contract](docs/rigor-integration.md). Rigor needs an explicit
core-directory replacement interface. Adding signatures alongside its default
core is insufficient. `rigor-options` describes the proposed arguments and
requires the exact target CRuby on Linux x86_64; it does not call Rigor or claim
that an unmodified Rigor supports them.

## Detect upstream updates

```sh
bundle exec ruby script/check-updates.rb
```

This read-only check uses RubyGems metadata and the Ruby website's release and
branch data. It reports stable RBS updates, Ruby patch updates, new targets,
maintenance changes, and targets that have reached EOL. Exit status is 0 when
the configuration matches, 2 when changes need review, and 1 for a fetch or data
error. The weekly GitHub Actions job runs the same check. It never edits rules,
creates issues, or publishes artifacts.

## Publication check

```sh
rbs-shifter release-check --root build/data --evidence release-evidence.json
```

After resolving the full coverage review, a human reviewer assembles evidence
for the exact manifest and every target. A report has this shape:

```json
{
  "manifest_sha256": "SHA-256 of the exact manifest.json bytes",
  "approved_by": "reviewer identity",
  "targets": {
    "3.3": {
      "ruby_version": "3.3.12",
      "platform": "x86_64-linux",
      "runtime": true,
      "consumer": true,
      "coverage_review": true
    },
    "3.4": {
      "ruby_version": "3.4.11",
      "platform": "x86_64-linux",
      "runtime": true,
      "consumer": true,
      "coverage_review": true
    }
  }
}
```

This report records a human review, not a cryptographic attestation. The reviewer
must inspect actual runtime, consumer, and coverage evidence before approving.
The check also revalidates the signature files. No command in this project
publishes a gem automatically.

## Licenses

Project code uses the BSD 2-Clause license in `LICENSE`. Generated RBS signatures
retain upstream licensing through `data/RBS-BSDL` and `data/RBS-COPYING` in the
built gem.
