# Match the target Ruby API

A shift must account for API differences, not only remove methods introduced in newer Ruby versions. It includes changes to arguments, return types, and inheritance, as well as restoring APIs that exist only in the older target. Deletion alone can reject valid code on the target Ruby, so the project accepts the maintenance cost of these broader corrections.
