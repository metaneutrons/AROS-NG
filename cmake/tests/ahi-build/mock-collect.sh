#!/bin/sh
set -eu

if [ -n "${AHI_FIXTURE_COLLECT_LOG-}" ]; then
    printf '%s\n' "$*" >> "$AHI_FIXTURE_COLLECT_LOG"
fi

if [ "${1-}" != --ld ] || [ -z "${2-}" ]; then
    echo "mock collector requires --ld BACKEND" >&2
    exit 2
fi
backend=$2
shift 2
if [ "${1-}" != -- ]; then
    echo "mock collector requires -- before linker arguments" >&2
    exit 2
fi
shift
exec "$backend" "$@"
