#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 Mike Wilson
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: sc-im-install.sh
# Author: Mike Wilson <mike@mikewilsonstl.com>
# Created: 2025-12-15T19:12:51+00:00
# Description: Installs sc-im with xlsx support
#              and dependencies. 

set -euo pipefail
shopt -s extglob

main() {
    sudo apt update
    sudo apt install pkg-config \
        bison \
	build-essential \
	git \
	libncursesw5-dev \
	libncurses5-dev \
	libxml2-dev \
	libzip-dev \
	libxlsxwriter-dev -y
    git clone https://github.com/jmcnamara/libxlsxwriter.git
    cd ./libxlsxwriter/
    make
    sudo make install
    sudo ldconfig
    cd ..
    rm -rf libxlsxwriter
    git clone https://github.com/andmarti1424/sc-im.git
    cd ./sc-im/src/
    make
    sudo make install
    cd ..
    rm -rf sc-im
}

main "$@"
