#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 Mike Wilson
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: install.sh
# Author: Mike Wilson <mike@mikewilsonstl.com>
# Created: 2025-12-18T11:32:53-05:00
# Description: Adds current directory to PATH

set -euo pipefail
shopt -s extglob

main() {
    echo "Original PATH: ${PATH}"
    export PATH=$PATH:$(pwd) >> ~/.bashrc
    echo "Scripts installed."
    echo "Current PATH: ${PATH}"
}

main "$@"


