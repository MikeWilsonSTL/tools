#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 Mike Wilson
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: [how to run the script, e.g., ./script_name.sh <arguments>]
# Author: Mike Wilson <mike@mikewilsonstl.com>
# Created: 2025-12-14T13:07:59-05:00
# Description: [brief purpose of the script]

set -euo pipefail
shopt -s extglob

main() {
    echo "script started"
    # add commands here
    echo "script finished successfully"
}

main "$@"
