# Keel

**Create, understand, and maintain iOS projects from the terminal.**

Keel generates new iOS projects and analyses existing ones. Everything it
reports is derived from your project by static analysis. No AI is required, and
none is ever invoked unless you choose it.

> **Status:** early development. `keel new` is being built; the analysis
> commands are declared but not implemented yet.

## Install

```bash
git clone https://github.com/GRimAce11/Keel.git
cd Keel
swift build -c release
cp .build/release/keel /usr/local/bin/
```

Requires macOS 13+.

## Commands

| Command | What it does |
|---|---|
| `keel new` | Create a new iOS project |
| `keel document` | Generate `PROJECT.md` from an existing project |
| `keel inspect` | Report targets, schemes, dependencies |
| `keel check` | Validate a project against its architecture rules |
| `keel doctor` | Diagnose the toolchain and project |
| `keel ai` | Inspect and choose which local AI agent Keel may use |

## Principles

**AI is optional.** Keel works with no AI agent installed, no account, no API
key, and no network. Every core command is deterministic.

**AI is never silent.** Keel may detect installed agents, but it never invokes
one because it happens to exist. Selection is always explicit, and the default
is always Keel alone.

**Facts come from Keel.** Deployment targets, schemes, dependencies and source
structure are determined by static analysis. An AI layer may interpret those
facts; it may never override them.

**No unnecessary dependencies.** Neither in Keel nor in what it generates.

## Development

```bash
swift build
swift test
```

## License

MIT.
