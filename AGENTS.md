This is the codebase for the rspec-capturing-formatter gem: keeps test progress readable when examples write logs to stdout or stderr. Streams logs as they happen, labels their source, and prints the complete RSpec nesting path before each example. Output is append-only: it does not use carriage-return progress, cursor movement, or other terminal rewriting, so the same report works in a terminal and in CI logs.

# General principles

- Before starting work, read the table of contents in `./devdocs/README.md` to discover available developer documentation. Read relevant documents as needed for the task.
- Speak in natural, plain English.
- `README.md` is curated user documentation, not an exhaustive specification.
- Prioritize Windows compatibility, append-only output, and one human-readable formatter per stream.
- When picking colors, pick those that are readable in both light and dark themed terminals.

## Escalation policy

Optimize for the underlying goal, not literal compliance. As you work, sanity-check whether requests, requirements, contracts, constraints, and assumptions actually make sense. If you discover a medium/high-impact ambiguity, contradiction, bad assumption, or strategic/design problem, stop and investigate it rather than working around it or silently choosing an interpretation. Make the issue concrete, then surface it and discuss the material decision with me before proceeding with that decision. The later you discover the issue, the more important it is to reconsider the plan rather than defend work already done.

Use judgment to handle low-impact problems autonomously and mention noteworthy ones afterward.

When progress stalls or complexity grows unexpectedly, stop iterating on the current approach and broaden the search space instead of iterating mechanically. Reconsider the approach itself and proactively explore materially different strategies—such as simplifying or reframing the problem, improving reproduction or observability, using existing tools/libraries, or changing assumptions or constraints.

# Testing procedures

- Test with `bundle exec rake spec`
  - Test specific RSpec version compatibility: `bundle exec rake spec BUNDLE_GEMFILE=gemfiles/rspec_*.gemfile`
  - Test specific spec file: `bundle exec rake spec FILE=spec/unit/lease_spec.rb:23`
  - Test specific example: `bundle exec rake spec EXAMPLE=EAGAIN` (passed to `rspec -e`)
  - Run test suite itself with rspec-capturing-formatter: `bundle exec rake spec DOGFOOD=1`
- Test Standard Ruby conformance: `bundle exec standardrb`
- The native `cmd.exe` quoting test is intentionally skipped off Windows; do not treat a Linux pass as Windows verification
