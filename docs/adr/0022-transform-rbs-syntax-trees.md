# Transform RBS syntax trees

Apply shift rules to parsed RBS syntax trees rather than text patches. Match the declaration's class, method, original type, and other relevant structure before changing it. This makes the intended transformation explicit and avoids relying on formatting or nearby text to identify an API.
