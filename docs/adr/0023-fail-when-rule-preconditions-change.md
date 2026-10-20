# Fail when shift rule preconditions change

Fail generation when a rule's expected declaration is missing, has changed, or matches ambiguously. A human must review the upstream change and update or retire the rule before publication. Silently skipping the rule or applying it to an approximate match could publish signatures that no longer describe Target Ruby.
