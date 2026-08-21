# Developer handbook

This handbook explains how `rspec-better-formatter` works and how to change it
safely. The [README](../README.md) defines the public behavior. The handbook
explains the implementation behind that behavior.

## Contents

- [Architecture and flow](architecture.md)
- [Capture and stream lifecycle](capture-and-streams.md)
- [Rendering and attribution](rendering-and-attribution.md)
- [Sanitization and encoding](sanitization-and-encoding.md)
- [RSpec integration and output](rspec-integration.md)
- [Testing and contribution](testing-and-contribution.md)

## Reading order

Start with the architecture document. Read the capture and sanitization
documents before changing stream behavior. Read the RSpec integration document
before changing notification handlers. Use the testing document when adding a
behavior or checking compatibility with another RSpec version.
