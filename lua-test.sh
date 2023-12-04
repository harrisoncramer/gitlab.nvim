#!/usr/bin/env bash
#
# Setup and run tests for lua part of gitlab.nvim.
# 
# In order to run tests you need to have `luarocks` and `git` installed. This script will check if
# environment is already setup, if not it will initialize current directory with `luarocks`,
# install `busted` framework and download plugin dependencies.
# 
#
set -e

LUA_VERSION="5.1"
PLUGINS_FOLDER="tests/plugins"
PLUGINS=(
    "https://github.com/MunifTanjim/nui.nvim"
    "https://github.com/nvim-lua/plenary.nvim"
    "https://github.com/sindrets/diffview.nvim"
)

if ! command -v luarocks > /dev/null 2>&1; then
    echo "You need to have luarocks installed in order to run tests."
    exit 1
fi

if ! command -v git > /dev/null 2>&1; then
    echo "You need to have git installed in order to run tests."
    exit 1
fi

if ! luarocks --lua-version=$LUA_VERSION which busted > /dev/null 2>&1; then
    echo "Installing busted."
    luarocks init
    luarocks config --scope project lua_version "$LUA_VERSION"
    luarocks install --lua-version="$LUA_VERSION" busted
fi

for arg in "$@"; do
if [[ $arg =~ "--coverage" ]] && ! luarocks --lua-version=$LUA_VERSION which luacov > /dev/null 2>&1; then
    luarocks install --lua-version="$LUA_VERSION" luacov
    # lcov reporter for luacov - lcov format is supported by `nvim-coverage`
    luarocks install --lua-version="$LUA_VERSION" luacov-reporter-lcov
fi
done

for plugin in "${PLUGINS[@]}"; do
    plugin_name=${plugin##*/}
    plugin_folder="$PLUGINS_FOLDER/$plugin_name"

    # Check if plugin was already downloaded
    if [[ -d "$plugin_folder/.git" ]]; then
        # We could also try to pull here but I am not sure if that wouldn't slow down tests too much.
        continue
    fi

    git clone --depth 1 "$plugin" "$plugin_folder"

done

nvim -u NONE  -U NONE -N -i NONE -l tests/init.lua "$@"
