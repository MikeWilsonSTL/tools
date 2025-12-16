#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 Mike Wilson
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: sc-im-install.sh
# Author: Mike Wilson <mike@mikewilsonstl.com>
# Created: 2025-12-15T19:12:51+00:00
# Description: Installs sc-im with xlsx support
#              and dependencies. 

#!/usr/bin/env bash
set -Eeuo pipefail

LIBXLSXWRITER_VERSION="v1.2.3"
SCIM_VERSION="v0.8.5"

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

    log "Installing build dependencies"
    sudo apt install -y \
        pkg-config \
        bison \
        build-essential \
        git \
        libncursesw5-dev \
        libncurses5-dev \
        libxml2-dev \
        libzip-dev

    log "Building libxlsxwriter $LIBXLSXWRITER_VERSION"
    git clone --branch "$LIBXLSXWRITER_VERSION" --depth 1 \
        https://github.com/jmcnamara/libxlsxwriter.git \
        "$BUILD_DIR/libxlsxwriter"

    make -C "$BUILD_DIR/libxlsxwriter" -j"$(nproc)"
    sudo make -C "$BUILD_DIR/libxlsxwriter" install
    sudo ldconfig

    log "Building sc-im $SCIM_VERSION"
    git clone --branch "$SCIM_VERSION" --depth 1 \
        https://github.com/andmarti1424/sc-im.git \
        "$BUILD_DIR/sc-im"

    make -C "$BUILD_DIR/sc-im/src" -j"$(nproc)"
    sudo make -C "$BUILD_DIR/sc-im/src" install

    log "Verifying installation"
    sc-im --version || true

    log "Installation complete"
}

main "@"

