# Version compatibility changes explicitly

Removing a supported Ruby target or making an incompatible change to the consumer interface requires a major version increase from 1.0 onward, or a minor version increase during 0.x. New targets and features use a minor version increase.

Corrections that make signatures match the actual API may use a patch release even when they cause new type errors in existing code. Release notes must identify such corrections. This lets us fix incorrect types without requiring a major release each time; consumers should pin versions and review updates.
