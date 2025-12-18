#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 Mike Wilson
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: newsboat-install.sh
# Author: Mike Wilson <mike@mikewilsonstl.com>
# Created: 2025-12-15T22:50:02-05:00
# Description: Installs newsboat and all dependencies.

set -Eeuo pipefail
shopt -s extglob

NEWSBOAT_VERSION="r2.41"
BUILD_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

log() {
    printf '\n[%s] %s\n' "$(date +'%H:%M:%S')" "$*"
}

require_command() {
    command -v "$1" >/dev/null 2>&1
}

main() {
    log "Updating package lists"
    sudo apt update

    log "Installing system dependencies"
    sudo apt install -y \
        build-essential \
        libncursesw5-dev \
        libsqlite3-dev \
        libxml2-dev \
        libcurl4-openssl-dev \
        pkg-config \
        git \
        libstfl-dev \
        libjson-c-dev \
        asciidoctor \
        gettext \
        libssl-dev

    if ! require_command cargo; then
        log "Installing Rust (rustup)"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    else
        log "Rust already installed"
    fi

    # shellcheck disable=SC1090
    # source ". $HOME/.cargo/env"


    # ^^^ issue here. 
    # why did the source path not work? running it maunally worked fine. 
    # commenting line 56 for now
    # . "$HOME/.cargo/env"            # For sh/bash/zsh/ash/dash/pdksh
    # source "$HOME/.cargo/env.fish"  # For fish
    # source $"($nu.home-path)/.cargo/env.nu"  # For nushell
    # ./newsboat-install.sh: line 56: . /home/mike/.cargo/env: No such file or directory

    log "Cloning Newsboat $NEWSBOAT_VERSION"
    git clone --branch "$NEWSBOAT_VERSION" --depth 1 \
        https://github.com/newsboat/newsboat.git "$BUILD_DIR/newsboat"

    log "Building Newsboat"
    make -C "$BUILD_DIR/newsboat"

    log "Installing Newsboat"
    sudo make -C "$BUILD_DIR/newsboat" install

    log "Installation complete"
}

main "$@"

