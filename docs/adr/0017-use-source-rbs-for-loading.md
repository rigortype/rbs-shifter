# Use Source RBS to load generated signatures

The first release guarantees loading and validation with the same RBS version used as Source RBS. It does not translate RBS language syntax for older parsers. Rigor integration must be verified under this version constraint, separating Ruby API compatibility from RBS parser compatibility.
