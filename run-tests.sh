#!/bin/sh
# Runs the pinned-world suite.
cd "$(dirname "$0")" || exit 1
exec nix eval '.#lib.caisson-compat.tests.summary'
