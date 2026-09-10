<!--
Thanks for contributing. Please read CONTRIBUTING.md first — it lists a few
things Keel will not accept, so nothing gets built that was never going to land.
-->

## What this changes

<!-- One or two sentences. -->

## Why

<!-- What problem this solves. If there is an issue, link it: Fixes #123 -->

## How it was verified

- [ ] `swift build` passes
- [ ] `swift test` passes
- [ ] `./Scripts/verify-generated.sh` passes — **required for any template change**
- [ ] Tests added or updated

<!-- For a template change, paste the flags you generated with:
     keel new MyApp --yes --no-networking
-->

## Checklist

- [ ] No third-party dependency added, to Keel or to generated projects
- [ ] No core command now needs AI, an account, an API key, or a network
- [ ] Every component is still independently selectable
- [ ] One logical change — no unrelated refactoring
- [ ] No dead code, and no TODO standing in for an implementation
