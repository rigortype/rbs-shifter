# Require validation before publication

Publication requires parseable signatures with valid type references, regression tests for every changed API on Target Ruby, and type-checking examples that accept valid usage and reject APIs unavailable on that target. The same source, target, and rules must also produce the same signature content. These checks provide evidence for publication without claiming that finite tests prove every possible runtime behavior.
