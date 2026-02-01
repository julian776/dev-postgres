# Changelog

## [1.1.0] - 2025-02-01

### Added
- Per-connection `require_confirmation` override
- `install.sh` setup script
- Test suites for pg-validate.sh and pg-hook.sh
- CLAUDE.md development guide
- README.md project documentation
- CONTRIBUTING.md contribution guidelines
- `.claude-plugin/marketplace.json` for plugin distribution
- `.gitignore`
- Trigger phrases and recommended workflow in SKILL.md

## [1.0.1] - 2025-01-31

### Fixed
- Suppress SET output in psql with `-q` flag
- Fix BSD sed compatibility for multi-line comment removal

## [1.0.0] - 2025-01-31

### Added
- Initial release
- Secure PostgreSQL access with named connections
- Read/write mode enforcement (5-layer defense-in-depth)
- Schema inspection helpers
- Query validation and auto-LIMIT injection
- PreToolUse hook blocking direct CLI access
- Query logging
- Output formats: aligned, CSV, JSON
