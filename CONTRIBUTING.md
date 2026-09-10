# Contributing to Keel

Thanks for taking the time. This document covers what Keel will and will not
accept, so nobody spends a weekend on a change that was never going to land.

## Before you open a pull request

Open an issue first for anything beyond a bug fix or a typo. Keel has a
[phase plan](https://github.com/GRimAce11/Keel#-roadmap) and a narrow scope; a
change that fights either is more useful as a conversation than as a diff.

## What Keel will not accept

These are not negotiable, and a PR that crosses one will be closed with a
pointer back here.

**No third-party dependencies in generated projects.** No Alamofire, no
Firebase, no DI framework, no SnapKit. Every dependency a generated project
does not have is one that thousands of apps never have to migrate.
`URLSession`, `async/await`, `Observation` and Swift Testing cover what it
needs.

Keel itself may take a dependency where the alternative is worse: it uses
swift-syntax, because regex cannot reliably tell a conformance from the same
words in a comment. That bar is high — argue the case in an issue first.

**No AI requirement in a core command.** `keel new`, `inspect`, `document`,
`check` and `doctor` must all work with no agent installed, no account, no API
key and no network. AI is an optional interpretation layer, never a
foundation.

**No silent AI invocation.** Keel may detect installed agents. It may never
run one because it happens to exist. Selection is explicit, every time.

**Nothing invented in generated documentation.** `keel document` reports what
static analysis actually found. If a fact cannot be derived from the project,
it does not go in the output.

**No dead code or TODO-as-implementation.** A stub that returns nothing and a
comment promising more is worse than an honest "not implemented" that exits
non-zero.

## Changing templates

Templates live in `Sources/KeelKit/Resources/Templates/`: one directory per
component, plus `Base` for what every project gets.

- Files carry a `.tpl` suffix, which is stripped on generation. That also stops
  SwiftPM from trying to compile a template as source.
- Tokens are `__PROJECT_NAME__`, `__BUNDLE_ID__`, `__DEPLOYMENT_TARGET__`,
  `__PROJECT_SLUG__`, `__KEEL_VERSION__`, `__YEAR__`, `__DATE__`. They are
  substituted in file contents *and* in path components.
- A template for a dotfile is named `__DOT__gitignore.tpl`. The file walker
  skips hidden files so it does not sweep up `.DS_Store`.
- Blocks can be made conditional:

  ```swift
  // keel:if networking
  let client = APIClient()
  // keel:else
  let client = PreviewClient()
  // keel:end
  ```

  `// keel:if !networking` negates. Any comment marker works — `//`, `#`,
  `<!--`, `/*` — because the same syntax has to work in Swift, in an XML
  scheme, and in a `.pbxproj`, which is an old-style plist and rejects `//`.

**The rule that matters most:** every component must be independently
selectable. A module that only compiles when a sibling happens to be enabled
is the single easiest way to break Keel, and it is what the full matrix exists
to catch.

## Running the checks

```bash
swift build
swift test                      # Keel's own tests
./Scripts/verify-generated.sh   # generates and builds every combination
```

The last one takes several minutes and needs Xcode with an iOS simulator. Run
it before any template change — unit tests prove the right files were written,
but only a real build proves the result opens in Xcode.

## Commits

One logical change per commit, with its tests, building clean. Explain **why**
in the body, not what — the diff already says what. No unrelated refactoring
mixed in.

## What is especially welcome

- Bugs in generated projects, with the `keel new` flags that produced them
- Template fixes for new Xcode or Swift releases
- Better diagnostics when generation fails
- Tests for combinations the matrix does not cover

## License

Contributions are licensed under the MIT License, the same as the project.
