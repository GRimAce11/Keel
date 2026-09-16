<div align="center">

# ⚓ Keel

### Understand an iOS codebase you did not write — from the terminal.

[![CI](https://img.shields.io/github/actions/workflow/status/GRimAce11/Keel/ci.yml?branch=main&style=for-the-badge&labelColor=0D1117&color=2EA043&label=CI)](https://github.com/GRimAce11/Keel/actions)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=for-the-badge&labelColor=0D1117&logo=swift&logoColor=F05138)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-14%2B-0A84FF?style=for-the-badge&labelColor=0D1117&logo=apple&logoColor=white)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-8957E5?style=for-the-badge&labelColor=0D1117)](LICENSE)

<samp>**No dependencies · Works offline · AI optional, never automatic**</samp>

</div>

---

## Install

```bash
brew install GRimAce11/tap/keel
```

## Try it

Point Keel at any iOS project. **It does not need to compile**, and nothing
leaves your machine.

```bash
cd SomeApp

keel explore     # walk through it, without knowing which flag to type
keel inspect     # what it is made of, and the architecture that implies
keel check       # where it breaks its own rules
keel document    # write all of that down as PROJECT.md
```

<div align="center">
  <img src=".github/assets/demo.svg" alt="keel inspect --graph and keel check on a project with a feature cycle" width="840">
</div>

## Why

**Somebody hands you an iOS codebase you have never seen.** Keel reads it and
tells you what it is made of — which features depend on which, where the screens
get their data, which boundaries the project keeps and where it breaks its own
rules — with the file and line behind every claim.

**Every finding says what it rests on.** A type conforming to SwiftUI's `View`
is a view *from the code*; a type called `ArticleRepository` is a repository
*because somebody named it one*. Keel never reports the second as the first, and
where the evidence settles nothing it says `Undetermined` rather than offering
the likeliest guess.

That is the part an assistant cannot do: the same question asked twice gets the
same answer, with the same lines behind it.

It also **creates** projects — `keel new` writes only the components you ask for,
so a project without networking has no `APIClient.swift` to delete. But the
reason to reach for Keel is the codebase you have already got.

## Commands

| Command | What it does |
|---|---|
| `keel explore` | Walk through a project's architecture interactively |
| `keel inspect` | Structure, dependencies, relationships, architecture |
| `keel check` | Validate against the project's real architecture boundaries |
| `keel document` | Write `PROJECT.md`, diagrams included |
| `keel doctor` | Diagnose the toolchain and project |
| `keel new` | Create a new iOS project |
| `keel add feature` | Generate a feature into an existing project |
| `keel ai` | Choose which local AI agent Keel may use |

Each takes a path and defaults to the working directory. `--help` on any of them.

## In CI

```yaml
- run: keel check --strict          # fails on warnings too
- run: keel document --check        # fails when PROJECT.md has drifted
```

Neither touches the network, needs an account, or invokes an agent.

## AI is optional

**Keel works with no agent installed, no account, no API key and no network.**
Every command above is deterministic. If you never read this section, nothing
about Keel changes.

If you do want an agent's reading of the facts, you permit one explicitly — and
what leaves the machine is the analysis, not your code:

```bash
keel ai use claude            # permit one — this does not run it
keel document --show-prompt   # exactly what would be sent, sending nothing
keel document --ai            # add an interpretation to PROJECT.md
```

## Privacy

| | |
|---|---|
| **Network access** | None, ever, except an agent you selected running under `--ai` |
| **Telemetry** | None |
| **Accounts or keys** | None. Keel has no account and reads no API key |
| **Core commands** | `new`, `inspect`, `document`, `check`, `doctor`, `add` are fully offline |

## More

**[REFERENCE.md](REFERENCE.md)** — how each verdict is reached, what `check`
calls an error and what it only suspects, what an agent is allowed to add, and
[what Keel cannot tell you](REFERENCE.md#what-keel-cannot-tell-you).

**[CONTRIBUTING.md](CONTRIBUTING.md)** — including the few things Keel refuses on
principle, so nobody builds something that was never going to land.
[SECURITY.md](SECURITY.md) covers reporting a vulnerability.

> [!NOTE]
> **Early development.** Every command works. The API is not settled — flags and
> output may change, and rules may be added to `keel check`.

## License

MIT — the code Keel generates is yours, with no attribution required.

<div align="center">
<br>
<sub>Built by <a href="https://github.com/GRimAce11">Chethan Nayak</a></sub>
</div>
