# Publish only when all included targets pass

A new gem release requires successful generation and validation for every included target. If one target fails, publication of the whole gem stops; we do not mix previous target artifacts with newly generated ones. This refines ADR-7 for the single-gem distribution chosen in ADR-12, keeping one release consistent while earlier published releases remain available.
