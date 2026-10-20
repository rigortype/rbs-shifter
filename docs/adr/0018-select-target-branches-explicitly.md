# Select target Ruby branches explicitly

Consumers explicitly select a Ruby branch, such as `3.3`, and receive the signatures for that branch's recorded, validated Target Ruby. Selection does not depend on the Ruby running the type checker. A missing target is an error rather than a reason to select a nearby version.
