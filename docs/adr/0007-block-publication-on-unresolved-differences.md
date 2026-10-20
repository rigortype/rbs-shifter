# Block publication when an API difference is unresolved

If we cannot establish the correct signature for a target Ruby API difference, we stop publication of the new artifact for that target and investigate. We do not guess or replace the unresolved type with `untyped` to pass validation. The previous validated artifact remains available, trading update speed for confidence in the published signatures.
