# Contributing

## Developer handbook

Please read [developer handbook](devdocs/README.md) to learn how the codebase works.

## Testing

- Test with `bundle exec rake spec`
- Test specific RSpec version compatibility: `bundle exec rake spec BUNDLE_GEMFILE=gemfiles/rspec_<VERSION>.gemfile`
- This codebase uses Standard Ruby. Check for conformance: `bundle exec standardrb`
- If you're not on Windows, then it's recommended that you install wine and winegcc (Debian/Ubuntu: `apt install wine libwine-dev`). This allows running certain Windows quoting tests on non-Windows.

## Notes about AI usage

[AGENTS.md](AGENTS.md) is only tested on GPT 5.6 (Sol, Terra, Luna). Especially the documentation writing instructions are confirmed to produce good results on these models. I've heard that Claude writes in a particularly annoying LLM-ish way and that it resists following writing style instructions, so use a non-Claude model if you find that documentation output is bad.
