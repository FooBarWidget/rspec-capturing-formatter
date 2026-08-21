# RSpec integration and output

The formatter registers only the notifications it needs. The registration is
at the end of `lib/rspec/better_formatter.rb`.

## Registered notifications

The formatter handles:

- `start`;
- `example_group_started` and `example_group_finished`;
- `example_started`;
- `example_passed`, `example_failed`, and `example_pending`;
- `message`;
- `stop`;
- `dump_profile` and `dump_summary`;
- `seed`;
- `close`.

`start` records the planned example count and load time when available. It does
not reset output. Messages, seed notifications, and captured output can arrive
before it.

The formatter does not register `dump_failures` or `dump_pending`. Failure and
expected-pending details are inline. Registering those events would duplicate
them. It also does not replace RSpec's deprecation formatter.

## Notification order and ownership

RSpec sends `stop` after `after(:suite)`. The formatter deactivates capture at
that point so late threads and `at_exit` code pass through normally. RSpec can
then send summary, profile, seed, and close events. The formatter retains its
state for those events and uses the renderer's bypass path for its own writes.

`message` is RSpec-owned content, not application output. Outside an active
example, it becomes an `rspec |` report entry. Inside an example, each message
line is indented under the existing entry and later captured output continues
with its normal source label. This keeps errors and filter announcements
separate from stdout and stderr attribution.

## Pending and skipped examples

`example_pending` reads the execution result's pending message and exception.
It renders the status, reason, and rerun location immediately. A skip has no
pending exception and receives the skipped status.

Expected failures can include the failure presenter output. The effective
`pending_failure_output` setting controls it:

- `:full` keeps the complete configured details;
- `:no_backtrace` removes backtrace lines;
- `:skip` omits expected-failure details.

RSpec 3.12 does not provide this setting. Requiring the formatter adds a
narrow shim to `RSpec::Core::Configuration` with the same three values. It does
not replace RSpec's presenters or change unrelated RSpec behavior.

## Failures and reruns

For a failed example, the formatter renders the result, inline rerun command,
and presenter lines during `example_failed`. It asks RSpec for
`fully_formatted_lines` when available and supplies a formatter-owned
colorizer. This preserves RSpec's source extraction, aggregate failure
numbering, shared-example traces, filtered backtraces, and extra failure lines.

Rerun targets use the example location when unique. If multiple examples share
that location, the example id disambiguates them. POSIX arguments use
`Shellwords.escape`. Windows arguments use the dedicated command-line helper,
which protects cmd.exe metacharacters and adds the batch-launcher parsing
layer.

## Summary, profile, and seed

The summary notification supplies authoritative counts and timing. The
formatter prints errors outside examples separately when the count is nonzero;
those errors do not increase the example total, but RSpec still makes the run
unsuccessful.

Profile output includes slow-example totals, percentages, locations, group
totals, counts, and averages when RSpec supplies them. A profile request with
no selected examples still prints a visible `No examples profiled` line.

The formatter stores the seed notification and prints the seed only when RSpec
reports that random ordering was used. It prints the seed after the summary.

## Multiple formatters and output files

Use the better formatter as the only human-readable formatter on a stream. A
machine formatter can write to another file:

```sh
bundle exec rspec \
  --format RSpec::BetterFormatter \
  --format json --out tmp/rspec.json
```

When the better formatter receives RSpec's `--out` destination, captured
stdout and stderr are part of that report. A JSON formatter on its own file
remains machine-readable and does not receive the human report prefixes.
