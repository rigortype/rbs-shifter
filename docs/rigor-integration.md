# Proposed Rigor adapter contract

This is a **proposed contract**, not an existing Rigor API or a verified Rigor integration. ADR-20 records that inspected Rigor 0.4.2 does not expose the required core-directory replacement. Consumer changes and integration validation remain required.

An explicit branch selects the exact Target Ruby recorded in the packaged manifest:

```ruby
catalog = RBS::Shifter::Catalog.new(root: "/path/to/packaged/signatures")
catalog.targets # Available branches, sorted
core = catalog.core_root(target: "3.3") # Pathname
metadata = catalog.metadata(target: "3.3") # Frozen target metadata
options = catalog.rigor_options(target: "3.3")
# => { core_root: core, target_ruby: "3.3.12" }
```

The example version must be replaced by the package's recorded Target Ruby. A missing branch fails; the catalog never guesses a branch from the running Ruby and never downloads signatures.

`core_root` validates the manifest format, Source RBS version against the loaded `RBS::VERSION`, target metadata, root confinement including symlinks, the exact recursive `.rbs` file set, and every recorded SHA-256 checksum. Invalid or incomplete packages raise `RBS::Shifter::Error`. Returned metadata is immutable. A package must remain unchanged while the consumer loads it.

`rigor_options` additionally requires CRuby running on the exact recorded Target Ruby on Linux x86_64. Other runtimes and platforms fail explicitly. Plain `core_root` selection has no runtime or platform restriction, allowing inspection and development on other hosts; this does not extend the integration guarantee.

The proposed consumer adapter must pass `core_root` into its RBS environment-loader construction so the selected directory fully replaces the default RBS core. It must retain the recorded `target_ruby` as the analysis target, use Source RBS, and propagate selection failures. Adding the selected directory alongside default core definitions is not replacement. Runtime monkey patches are not part of this contract.

Before claiming Rigor support, validate this consumer change on every packaged Target Ruby under Linux x86_64, including an assertion that default core definitions are absent and shifted signatures are actually used. Catalog unit tests verify selection and refusal behavior only; they do not establish full Rigor analysis compatibility.
