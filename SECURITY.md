# Security policy

Blockpulse is maintained by Arterion Consultancy B.V. We take security reports seriously and appreciate responsible disclosure.

## Supported versions

Security fixes go into the latest release on the App Store and into the `main` branch. Older versions are not patched; update to the latest version first.

| Version | Supported |
| ------- | --------- |
| Latest App Store / TestFlight release | Yes |
| `main` branch | Yes |
| Anything older | No |

## Reporting a vulnerability

Please do not report security issues in public GitHub issues, discussions or pull requests.

Report privately in one of these ways:

- GitHub: [Report a vulnerability](https://github.com/WhenLambo2/blockpulse/security/advisories/new) (private security advisory)
- Email: [info@blockpul.se](mailto:info@blockpul.se) with "Security" in the subject

Please include:

- What the issue is and what an attacker could do with it
- The affected component (app, widgets, `BitcoinKit` package, build scripts) and version
- Steps to reproduce, a proof of concept, or the relevant code
- Your name or handle if you want credit

Reports in English or Dutch are welcome.

## What to expect

- We confirm receipt within 3 business days.
- We send a first assessment within 10 business days.
- We keep you updated until the issue is fixed and agree a disclosure date with you. We aim to release a fix within 90 days; we tell you if it takes longer and why.
- With your permission, we credit you in the release notes or the published advisory.

There is no bug bounty.

## Scope

In scope:

- The Blockpulse iOS app and its widgets
- The `BitcoinKit` package in `Packages/BitcoinKit`
- Build and release scripts in this repository

Out of scope:

- mempool.space and other mempool instances the app reads from; report those to their operators
- The blockpul.se website (report it by email, but it is not covered by this repository)
- Issues that need a jailbroken or already compromised device
- Denial of service, spam, social engineering and physical attacks
- Reports from automated scanners without a demonstrated impact

## Safe harbour

We will not take legal action against you for research that follows this policy: you report privately, give us reasonable time to fix the issue before any disclosure, only test against your own devices and accounts, and do not access, change or delete data that is not yours or disrupt services for others.
