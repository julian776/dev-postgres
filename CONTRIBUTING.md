# Contributing to dev-postgres

Thanks for your interest in contributing.

## Before You Start

Please open an issue before submitting a pull request. This helps:

- Discuss the approach before investing time
- Avoid duplicate efforts
- Get guidance on implementation

## Pull Request Process

1. Open an issue describing the proposed change
2. Get feedback from a maintainer
3. Fork the repo and branch from `main`
4. Make your changes
5. Run tests: `bash skills/dev-postgres/tests/test-validate.sh && bash skills/dev-postgres/tests/test-hook.sh`
6. Syntax-check scripts: `bash -n skills/dev-postgres/scripts/*.sh`
7. Submit a PR referencing the issue

## Guidelines

- All scripts must use `#!/usr/bin/env bash` and `set -euo pipefail`
- Maintain BSD (macOS) compatibility — avoid GNU-only flags
- Add tests for new validation logic
- Keep the security layers independent — each layer should work even if others are bypassed

## Questions?

Open an issue — happy to help.
