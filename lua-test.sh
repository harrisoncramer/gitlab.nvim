#!/usr/bin/env bash
#
# Setup and run tests for lua part of gitlab.nvim.
# Requires `luarocks`, `git`, and `nvim` installed.
#

set -euo pipefail

PLUGINS_FOLDER="tests/plugins"
PLUGINS=(
  "https://github.com/MunifTanjim/nui.nvim"
  "https://github.com/nvim-lua/plenary.nvim"
  "https://github.com/sindrets/diffview.nvim"
)

if ! command -v luarocks >/dev/null 2>&1; then
  echo "Error: luarocks not found. Please install LuaRocks." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git not found. Please install Git." >&2
  exit 1
fi

if ! command -v nvim >/dev/null 2>&1; then
  echo "Error: nvim not found. Please install Neovim." >&2
  exit 1
fi

# Clone test plugin dependencies
mkdir -p "$PLUGINS_FOLDER"
for plugin in "${PLUGINS[@]}"; do
  plugin_name="${plugin##*/}"
  plugin_folder="$PLUGINS_FOLDER/$plugin_name"
  if [[ ! -d "$plugin_folder/.git" ]]; then
    echo "Cloning $plugin..."
    git clone --depth 1 "$plugin" "$plugin_folder"
  fi
done

# Run tests
echo "Running tests with Neovim..."
LC_TIME=en_US.UTF-8 nvim -u NONE -U NONE -N -i NONE -l tests/init.lua "$@"
