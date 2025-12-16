#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 Mike Wilson
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: [how to run the script, e.g., ./script_name.sh <arguments>]
# Author: Mike Wilson <mike@mikewilsonstl.com>
# Created: 2025-12-15T22:50:02-05:00
# Description: [brief purpose of the script]

set -euo pipefail
shopt -s extglob

main() {
    sudo apt install \
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
    	gettext
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    git clone https://github.com/newsboat/newsboat.git
    cd newsboat
    make
    sudo make install
    cd ..
    rm -rf newsboat
}

main "$@"
