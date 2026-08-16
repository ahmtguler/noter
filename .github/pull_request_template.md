<!--
Title must follow Conventional Commits: <type>(<scope>): <subject>
  types:  feat fix chore docs refactor test style perf ci build revert
  scopes: editor noter prefs window store switcher palette onboarding
  lowercase subject, header <= 100 characters
-->

## What and why

<!-- What changes, and what problem it solves. Link the issue: Closes #123 -->

## How

<!-- Approach taken, and any alternative you rejected and why. Skip for trivial changes. -->

## Testing

<!-- How you verified this. Name the tests you added, or say why none were needed. -->

- [ ] Added or updated automated tests
- [ ] Ran `make ci` locally and it passed
- [ ] Verified manually in the running app

## Checklist

- [ ] Branch is named `<type>/<kebab-case-description>`
- [ ] Commits follow Conventional Commits
- [ ] Rebuilt `editor.bundle.js` if any `.ts` file changed
- [ ] Ran `make generate` if `project.yml` or a new source directory changed
- [ ] Updated `README.md` / `CLAUDE.md` if behaviour or architecture changed

## Screenshots

<!-- For UI changes. Delete this section otherwise. -->
