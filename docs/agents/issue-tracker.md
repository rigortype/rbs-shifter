# Issue tracker: GitHub

Issues and specs live in GitHub Issues for `rigortype/rbs-shifter`.
Use the `gh` CLI from this repo.

## Common actions

- Create: `gh issue create --title "..." --body-file <file>`
- Read: `gh issue view <number> --comments`
- List: `gh issue list --state open`
- Comment: `gh issue comment <number> --body-file <file>`
- Add a label: `gh issue edit <number> --add-label "..."`
- Remove a label: `gh issue edit <number> --remove-label "..."`
- Close: `gh issue close <number>`

Write multi-line text to a file and use `--body-file`.

When a skill says to publish to the issue tracker, create a GitHub issue.
When a skill says to fetch a ticket, read the issue and its comments.

## Pull requests as a triage surface

PRs as a request surface: no.
