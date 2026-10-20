# Limit API compatibility guarantees to core

The first release guarantees target API compatibility only for the shifted core signatures. Applications may use standard libraries, but matching their signatures to the installed library versions is outside this guarantee. Rigor integration tests must distinguish core coverage from standard library coverage so successful integration does not imply that every signature in an application matches Target Ruby.
