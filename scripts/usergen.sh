#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 Mike Wilson
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: usergen.sh
# Author: Mike Wilson <mike@mikewilsonstl.com>
# Created: 2025-12-14T14:54:17-05:00
# Description: Generates lines of random strings

set -euo pipefail
shopt -s extglob

length=30    # characters per line
lines=10     # number of lines
charset='abcdefghijklmnopqrstuvwxyz0123456789'

# total characters needed
total=$((length * lines))

main() {
    # read from /dev/urandom, map bytes to charset, and split into lines
    tr -dc "$charset" </dev/urandom | head -c "$total" | fold -w "$length"
}

main "$@"
