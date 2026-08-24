# Developer handbook

This handbook explains how `rspec-better-formatter` works and how to change it safely. The [README](../README.md) is curated user documentation: its claims and examples define public commitments without listing every behavior. The handbook records the detailed behavior and implementation knowledge that contributors need.

## Contents

- [Architecture and flow](architecture.md)
- [Capture and stream lifecycle](capture-and-streams.md)
- [Rendering and attribution](rendering-and-attribution.md)
- [Color support](color-support.md)
- [Sanitization and encoding](sanitization-and-encoding.md)
- [RSpec integration and output](rspec-integration.md)
- [User-facing documentation](user-facing-documentation.md)
- [Testing and contribution](testing-and-contribution.md)

## Reading order

Start with the architecture document. Read the capture and sanitization documents before changing stream behavior. Read the RSpec integration document before changing notification handlers. Read the user-facing documentation guide before changing the README. Use the testing document when adding a behavior or checking compatibility with another RSpec version.
