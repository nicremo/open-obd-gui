# Security policy

Open OBD GUI talks to vehicle control modules. Its most important guarantee is that it only reads.

## Reporting a vulnerability

Please report security issues privately through [GitHub private vulnerability reporting](https://github.com/nicremo/open-obd-gui/security/advisories/new), not in a public issue.

Especially relevant:

- any way to send a vehicle service or adapter command that the read-only policy should reject
- any path that bypasses `ReadOnlyPolicy`, `CommandPolicy` or `SafeLink`
- access to the local bridge socket by another user

## Supported versions

Only the latest release receives fixes.
