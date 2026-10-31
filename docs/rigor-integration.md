# Rigor integration

Rigor replaces its default core signatures with a directory named by the `core_root:` key in `.rigor.yml` (ADR-20). The key is on Rigor's `master` (rigortype/rigor#2518) and not yet in a released Rigor. Rigor runs on its own supported Ruby, 4.0, and analyses an older target from there (ADR-27).

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

`rigor_options` returns the same selection with the recorded Target Ruby, whatever Ruby or platform runs it. Write both values into `.rigor.yml`:

```yaml
target_ruby: "3.3.12"
core_root: /path/printed/by/rbs-shifter/path
```

`rbs-shifter path --target 3.3` prints the directory after validating it. Rigor itself reads the directory without the catalog's checksum validation, so select it through `path` or `rigor-options` rather than by hand. The path points into the installed gem and changes with the gem version and Ruby installation. The directory must not be inside the project's signature paths; Rigor rejects an overlap.

Before claiming Rigor support, validate the integration on every packaged Target Ruby, including an assertion that default core definitions are absent and shifted signatures are actually used. Catalog unit tests verify selection and refusal behavior only; they do not establish full Rigor analysis compatibility. The guarantee covers core signature selection; ADR-27 lists the Rigor-side gaps outside it.
