This is the codebase for the rspec-capturing-formatter gem: keeps test progress readable when examples write logs to stdout or stderr. Streams logs as they happen, labels their source, and prints the complete RSpec nesting path before each example. Output is append-only: it does not use carriage-return progress, cursor movement, or other terminal rewriting, so the same report works in a terminal and in CI logs.

# General principles

- Before starting work, read the table of contents in `./devdocs/README.md` to discover available developer documentation. Read relevant documents as needed for the task.
- `README.md` is curated user documentation, not an exhaustive specification.
- Prioritize Windows compatibility, append-only output, and one human-readable formatter per stream.
- When picking colors, pick those that are readable in both light and dark themed terminals.

## General coding guidelines

- Prefer boring, explicit code over cleverness or premature abstraction. Keep the main code path easy to follow and centered on business logic; move incidental technical or secondary details into helpers when they obscure that flow. Some duplication is fine. Extract shared abstractions only when they clearly improve readability or eliminate substantial duplication, and avoid speculative generalization.
- Proper error handling
  - Shell scripts: use pipefail
  - When ignoring errors, only ignore specific errors, not blanket ignore all errors
- Commenting strategy:
  - Use concise comments to explain non-obvious why: algorithms, invariants, caveats, and local design decisions. Avoid narrating straightforward code.
  - Important classes/modules should briefly state their responsibility when not obvious.
  - Keep comments local and short. Broader architecture, substantial rationale, or complex/cross-cutting caveats belong in the developer handbook; comments may summarize and link to it.
- Ruby:
  - Use Standard Ruby

# Escalation policy

Optimize for the underlying goal, not literal compliance. Continuously check whether requests, requirements, contracts, constraints, and assumptions actually make sense. If you discover a medium/high-impact ambiguity, contradiction, bad assumption, or strategic/design problem, do not work around it or silently choose an interpretation: surface it and discuss it with me first. The later you discover the issue, the more important it is to reconsider the plan rather than defend work already done.

Use judgment to handle low-impact problems autonomously and mention noteworthy ones afterward.

# Documentation style

- Use sentence case for headings. Do not cap line widths.
- Write for a capable developer who is new to this codebase. Explain purpose or constraints before implementation details. Introduce technical terms before using them densely. Prefer concrete subjects and actions. Use examples when they explain behavior more quickly than a list. Include only information that helps a contributor find the correct code, make a decision, or avoid a likely mistake. Leave exhaustive method behavior and minor edge cases to the code and tests. Do not repeat information that an example or an earlier section already makes clear. After drafting, remove every sentence that is merely true but not useful.
- Keep information that helps readers understand a non-obvious design, find where to make a change, make a decision, or avoid a mistake. Remove repetition and details easily recovered from code or tests.
- Keep user documentation focused on public setup, behavior, and limitations. Omit internals and exhaustive behavior.

# Testing

- Test with `bundle exec rake spec`
  - Test specific RSpec version compatibility: `bundle exec rake spec BUNDLE_GEMFILE=gemfiles/rspec_*.gemfile`
  - Test specific spec file: `bundle exec rake spec FILE=spec/unit/lease_spec.rb:23`
  - Test specific example: `bundle exec rake spec EXAMPLE=EAGAIN` (passed to `rspec -e`)
  - Run test suite itself with rspec-capturing-formatter: `bundle exec rake spec DOGFOOD=1`
- Test Standard Ruby conformance: `bundle exec standardrb`
- The native `cmd.exe` quoting test is intentionally skipped off Windows; do not treat a Linux pass as Windows verification

## Testability (not for shell scripts)

- Keep core logic independently unit testable; isolate side effects and external interactions where practical.
- Add tests for significant behavioral changes and bug fixes. Prefer red/green testing.

# Developer handbook

The handbook is a series of Markdown files in `devdocs/`. Purposes of the handbook:

- Teaches a capable human or AI developer, who does not know this codebase, how this codebase works so that they can contribute effectively. For AI, the handbook functions as a series of skills, with an index functioning as a skill router.
- Documents important design decisions, rationale and constraints so they don't get lost or become implicit.

Content coverage:

- Overall architecture and/or flow
- Important concepts and constraints
- Important design patterns where non-obvious
- Important or non-obvious design decisions
- Important subsystems

Writing guidelines (in addition to "Documentation style"):

- Use `devdocs/README.md` as a concise, keyword-rich topic index and skill router.
- Give each major topic one canonical document and each document one primary topic.
  - A topic is major when changing it safely requires a distinct mental model because it has its own concepts, constraints, failure modes, platform behavior, or reasons to change. Code-module boundaries alone do not determine document boundaries.
- When writing an Architecture document, keep it as a map of components, main flows, and system-wide constraints. Summarize and link to canonical topic documents instead of putting subsystem details there.
- At topic boundaries, explain only the local interaction and link to the canonical document. Do not duplicate the complete policy.
- Document important rationale and non-obvious design decisions. Omit trivial information and content already covered by user documentation, `AGENTS.md`, or `CONTRIBUTING.md`.
- Must reflect current behavior rather than idealized goal. If they differ, document the divergence.

Update the handbook in the same change when architecture, flows, major concepts, constraints, patterns, decisions, or subsystems change.
