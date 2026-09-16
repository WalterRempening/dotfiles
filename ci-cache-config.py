#!/usr/bin/env python3
"""Point a gitlab-runner block at the MinIO shared cache.

Usage: ci-cache-config.py <config.toml> <bridge_ip> <access_key> <secret_key>

`gitlab-runner register` already writes an empty [runners.cache] table with
.s3/.gcs/.azure sub-tables. Appending a second one is a fatal TOML error --
"Key 'runners.cache' has already been defined" -- which crash-loops the service
and takes every runner on the host offline. So the existing table is swallowed
and replaced rather than added to.

Deliberately line-based rather than a TOML round-trip: config.toml carries
comments documenting the volume contract, and every Python TOML writer drops
them.
"""
import re
import sys

RUNNER_NAME = "t14-docker"


def main() -> int:
    cfg, bridge, user, pw = sys.argv[1:5]
    lines = open(cfg).read().splitlines(keepends=True)

    block = (
        "  [runners.cache]\n"
        '    Type = "s3"\n'
        "    Shared = true\n"
        "    [runners.cache.s3]\n"
        f'      ServerAddress = "{bridge}:9000"\n'
        f'      AccessKey = "{user}"\n'
        f'      SecretKey = "{pw}"\n'
        '      BucketName = "runner-cache"\n'
        '      BucketLocation = "us-east-1"\n'
        "      Insecure = true\n"
    )

    out, in_target, replaced, skipping = [], False, False, False
    for line in lines:
        stripped = line.strip()

        if stripped.startswith("[[runners]]"):
            in_target, skipping = False, False
        if re.match(r'\s*name = ".*%s.*"' % re.escape(RUNNER_NAME), line):
            in_target = True

        # Swallow the existing [runners.cache] table and everything beneath it,
        # stopping at the next sibling table (typically [runners.docker]).
        if skipping:
            if stripped.startswith("[") and not stripped.startswith("[runners.cache"):
                skipping = False
            else:
                continue

        if in_target and not replaced and stripped == "[runners.cache]":
            out.append(block)
            replaced, skipping = True, True
            continue

        out.append(line)

    if not replaced:
        sys.stderr.write(
            "no [runners.cache] table found in the %s block\n" % RUNNER_NAME
        )
        return 1

    open(cfg, "w").write("".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
