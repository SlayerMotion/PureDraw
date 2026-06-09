# Security Policy

## Reporting a vulnerability

If you believe you have found a security issue in PureDraw, please report it
privately. Do not open a public issue for security problems.

Email **mihaelamj@me.com** with:

- A description of the issue and its impact.
- Steps to reproduce, or a proof of concept.
- The affected version or commit.

You can expect an acknowledgement within a few days. Once the issue is confirmed,
a fix will be prepared and a release cut, after which the issue can be disclosed
publicly with credit to the reporter if desired.

## Supported versions

PureDraw is pre-1.0 and under active development. Security fixes are applied to
the `main` branch. Until a stable release exists, only the latest `main` is
supported.

## Scope

PureDraw is a 2D graphics engine. The package parses paths, manages graphic state, and performs vector rendering to formats like PDF, SVG, and PostScript. Reports about security vulnerabilities in the parsing logic, memory handling, or renderer bounds enforcement are in scope.
