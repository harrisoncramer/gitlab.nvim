#!/usr/bin/env bash
#
# Process generated luacov stats file into coverage report for gitlab.nvim.
# 
set -e

if ! [[ -f luacov.stats.out ]]; then
    echo "You need to first run \`./lua-test.sh --coverage\`"
    exit 1
fi

eval "$(luarocks path)"
luacov "$@"
