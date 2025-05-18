#!/usr/bin/env bash

# install determinate nix
set -oue pipefail
curl -fsSL https://install.determinate.systems/nix | sh -s -- install --determinate --no-confirm
