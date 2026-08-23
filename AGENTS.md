This is the codebase for the rspec-better-formatter gem: keeps test progress readable when examples write logs to stdout or stderr. Streams logs as they happen, labels their source, and prints the complete RSpec nesting path before each example. Output is append-only: it does not use carriage-return progress, cursor movement, or other terminal rewriting, so the same report works in a terminal and in CI logs.

# General principles

- Before starting work, read the table of contents in `./devdocs/README.md` to discover available developer documentation. Read relevant documents as needed for the task.
- Source of truth: treat `./README.md` (public user docs) as the public behavior contract.
- Prioritize Windows compatibility, append-only output, and one human-readable formatter per stream.

## General coding guidelines

- Prefer boring, explicit code over cleverness or premature abstraction. Keep the main code path easy to follow and centered on business logic; move incidental technical or secondary details into helpers when they obscure that flow. Some duplication is fine. Extract shared abstractions only when they clearly improve readability or eliminate substantial duplication, and avoid speculative generalization.
- Proper error handling
  - Shell scripts: use pipefail
  - When ignoring errors, only ignore specific errors, not blanket ignore all errors
- Commenting strategy:
  - Use concise comments to explain non-obvious why: algorithms, invariants, caveats, and local design decisions. Avoid narrating straightforward code.
  - Important classes/modules should briefly state their responsibility when not obvious.
  - Keep comments local and short. Broader architecture, substantial rationale, or complex/cross-cutting caveats belong in the developer handbook; comments may summarize and link to it.

# Escalation policy

Optimize for the underlying goal, not literal compliance. Continuously check whether requests, requirements, contracts, constraints, and assumptions actually make sense. If you discover a medium/high-impact ambiguity, contradiction, bad assumption, or strategic/design problem, do not work around it or silently choose an interpretation: surface it and discuss it with me first. The later you discover the issue, the more important it is to reconsider the plan rather than defend work already done.

Use judgment to handle low-impact problems autonomously and mention noteworthy ones afterward.

# Documents/comments writing style

- Use sentence case for all headings and subheadings, not title case
- Use ASD-STE100 Simplified Technical English
- Documents: don't cap line widths
- User-facing documents: avoid references to internals, focus on public contract and behavior

# Testing

- Test with `RUBYOPT=--enable=frozen-string-literal bundle exec rspec`
- Test specific RSpec version compatibility with `RUBYOPT=--enable=frozen-string-literal BUNDLE_GEMFILE=gemfiles/rspec_*.gemfile bundle exec rspec`
- The native `cmd.exe` quoting test is intentionally skipped off Windows; do not treat a Linux pass as Windows verification

## Testability (not for shell scripts)

- Keep core logic independently unit testable; isolate side effects and external interactions where practical.
- Add tests for significant behavioral changes and bug fixes. Prefer red/green testing.

# Developer handbook maintenance

After material changes, update the developer handbook (`devdocs/`) as part of the same change. Change is material when it affects or invalidates documented architecture, flows, concepts, constraints, design decisions, patterns, or major subsystems.

Purposes of the handbook:

- Teaches a human and AI developer how this codebase works so that they can contribute effectively. For AI, the handbook functions as a series of skills, with an index functioning as a skill router.
- Documents important design decisions, rationale and constraints so they don't get lost or become implicit.

Content coverage:

- Overall architecture and/or flow
- Major concepts and constraints
- Major design patterns where non-obvious
- Major or non-obvious design decisions
- Major subsystems
- `devdocs/README.md` is to be the table of contents file, linking to everything else, with concise & keyword-heavy descriptions. For AI, this functions like a lightweight skill router.
- Minimize/omit:
  - Obvious/trivial information, focus on important things
  - Info already in public user docs. The handbook assumes the reader has adequate user-facing knowledge of the project.
  - Info already in `AGENTS.md` and `CONTRIBUTING.md`

Output requirements:

- One markdown file per major topic. Cross-link where appropriate.
- Must reflect current behavior rather than idealized goal. If they differ, document the divergence.
