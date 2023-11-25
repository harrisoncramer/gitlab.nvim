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

BUSTED_VERSION="2.2.0-1"
BUSTED_LOCATION="lua_modules/lib/luarocks/rocks-5.1/busted/$BUSTED_VERSION/bin/busted" 
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

if ! [[ -f "$BUSTED_LOCATION" ]]; then
    echo "Installing busted."
    luarocks init
    luarocks config --scope project lua_version 5.1
    luarocks install busted "$BUSTED_VERSION"
fi

for plugin in "${PLUGINS[@]}"; do
    plugin_name=${plugin##*/}
    plugin_folder="$PLUGINS_FOLDER/$plugin_name"

    # Check if plugin was already downloaded
    if [[ -d "$plugin_folder/.git" ]]; then
        # We could also try to pull here but I am not sure if that wouldn't slow down tests too much.
        continue
    fi

    git clone "$plugin" "$plugin_folder"

done

nvim -u NONE  -U NONE -N -i NONE -S tests/init.lua -l "$BUSTED_LOCATION" "$@"
