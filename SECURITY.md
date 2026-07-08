# Security policy

## Reporting

Report vulnerabilities privately via GitHub Security Advisories:
**Security → Report a vulnerability** on this repository. Please don't
open public issues for security reports.

## Scope

PlusPlus has **no server**: training data lives on-device (SwiftData) and,
when sync ships, in a GitHub repo the user owns. The interesting surfaces
are therefore:

- the interchange codec/validator (`PlusPlusKit`) parsing untrusted JSON
  (imports, share links),
- share-link handling (`plusplus.fit/r#…` fragments and the `plusplus://`
  URL scheme),
- the CLI's `propose_program_change` MCP tool (fenced git writes),
- the GitHub Actions recipes users copy into their own repos.

Reports about any of those parsing/handling paths are especially welcome.
