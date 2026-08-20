This is the codebase for the rspec-better-formatter gem: keeps test progress readable when examples write logs to stdout or stderr. Streams logs as they happen, labels their source, and prints the complete RSpec nesting path before each example. Output is append-only: it does not use carriage-return progress, cursor movement, or other terminal rewriting, so the same report works in a terminal and in CI logs.

# General principles

- Source of truth: treat @./README.md as the public behavior contract.
- Prioritize Windows compatibility, append-only output, and one human-readable formatter per stream.
- Documentation/comments writing style:
  - Use sentence case for all headings and subheadings, not title case
  - Use ASD-STE100 Simplified Technical English

# Testing

- Test with `bundle exec rspec`
- Test specific RSpec version compatibility with `BUNDLE_GEMFILE=gemfiles/rspec_*.gemfile bundle exec rspec`
- The native `cmd.exe` quoting test is intentionally skipped off Windows; do not treat a Linux pass as Windows verification

# Implementation constraints

- Requiring `lib/rspec/better_formatter.rb` immediately installs inactive process-global stream proxies. Activation is lease/generation based; `stop` and `close` must idempotently restore globals while retained proxies become passthrough streams.
- Route formatter-owned writes through `CaptureManager#bypass` and synchronize capture/renderer state with its reentrant monitor; otherwise output can capture itself or interleave.
- Preserve `StreamProxy` clone/reopen raw mode: RSpec's ordinary and `*_from_any_process` output matchers must receive unprefixed bytes without duplicate report output.
- Sanitization is incremental across writes and encodings. Keep split multibyte characters, CRLF, partial escape sequences, binary bytes, and destination-encoding fallback covered.
- Read formatter configuration at render time so settings loaded by spec files after formatter construction still apply.
- Do not register `dump_failures` or `dump_pending`; failures and pending details are inline. Keep the RSpec 3.12 `pending_failure_output` shim narrowly version-gated.
- Prefer fresh-process integration tests using `Open3` argument arrays for global-IO lifecycle, RSpec event order, matcher reopen behavior, and packaging; unit tests alone cannot validate these contracts.
