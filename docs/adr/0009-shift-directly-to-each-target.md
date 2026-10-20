# Shift directly from Source RBS to each Target Ruby

Generate each target's signatures directly from the pinned Source RBS using the rules for that Target Ruby. Rules may be shared across targets, but generation does not depend on another target's generated signatures. This avoids making one target's output and failures part of another target's transformation path.
