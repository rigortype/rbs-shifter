# RBS Shifter

RBS Shifter adapts upstream RBS signatures to the APIs of supported older Ruby versions.

## Language

**Upstream signatures**:
The type signatures supplied by the ruby/rbs project.

**Target Ruby**:
The exact CRuby version whose APIs the shifted signatures describe.

**Source RBS**:
The exact stable RBS release that supplies the upstream signatures for a shift.

**Shift**:
An adaptation of upstream signatures to match the APIs of a target Ruby.
This includes semantic differences, not only signature syntax.
