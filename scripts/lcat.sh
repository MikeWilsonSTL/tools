#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 Mike Wilson
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: lcat.sh [FILENAME]
# Author: Mike Wilson <mike@mikewilsonstl.com>
# Created: 2025-12-11T19:52:55-05:00
# Description: This command makes reading uncompressed logs easier by
#              replacing the literal two-character sequence \n with
#              an actual newline character and \t with tabs.

set -euo pipefail
shopt -s extglob

main() {
  sed $'s/\\\\n/\\n/g; s/\\\\t/\\t/g' "$@"
}

main "$@"
