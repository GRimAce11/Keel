# Security Policy

## Reporting a vulnerability

Report privately through GitHub:
**[Open a security advisory](https://github.com/GRimAce11/Keel/security/advisories/new)**
— or Security → Report a vulnerability on this repository.

Please do not open a public issue for a security problem.

Include what you did, what happened, and the Keel version (`keel --version`).
A project that reproduces it helps; if it is not one you can share, the
smallest thing that triggers it is enough.

You should get an acknowledgement within a week. Keel is maintained by one
person, so a fix may take longer than that — you will be told either way
rather than left waiting.

## Supported versions

The latest release. Keel is a developer tool installed from a tap, and fixes
ship forward rather than being backported.

| Version | Supported |
|---|---|
| Latest release | ✅ |
| Anything older | Upgrade first |

## What Keel does, so you can judge the surface

Worth stating plainly, because most of the security questions about a tool
like this are really questions about what it is allowed to do.

**It reads files and writes files.** `keel new` and `keel add feature` create
files under a directory you name. `keel document` writes `PROJECT.md`. Nothing
else is written.

**It does not build your project.** No `xcodebuild`, no `swift build`, no
scripts from the project are executed. Analysis is parsing, so a malicious
project cannot get code run by being inspected.

**It makes no network requests.** `new`, `inspect`, `explore`, `document`,
`check` and `doctor` work offline, with no account and no telemetry. The only
exception is an agent *you* selected, running under a flag *you* passed.

**It never runs an agent you did not choose.** Detection reads `PATH` and does
not execute anything — not even for a version string. Selecting an agent
permits it; running it is a separate act, and `--no-ai` overrides everything
including project configuration.

**A cloned project cannot grant itself AI access.** `.keel/config.json` in a
repository may *lower* the AI mode and may never raise it. Cloning somebody's
repository must not be enough to get an agent running on your machine, and
this is the rule that guarantees it. If you find a way around it, that is a
vulnerability and is worth reporting.

**No source code is sent to an agent.** What `--ai` sends is the derived
analysis — counts, conformances, folder names, relationships, evidence — the
same facts the document already prints. `keel document --show-prompt` prints
exactly what would be sent without sending it. If you find source contents in
that prompt, that is a vulnerability.

## Out of scope

- Findings that require the attacker to already run code as you.
- An agent you selected behaving badly. Keel validates the *shape* of a reply
  and that every type it names exists; it cannot vouch for an agent's judgement,
  and says so in the document.
- Vulnerabilities in swift-syntax or swift-argument-parser — report those to
  their projects. Tell us too if Keel's use of them makes it worse.
