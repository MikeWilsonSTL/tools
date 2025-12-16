#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 Mike Wilson
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: keygen.sh
# Author: Mike Wilson <mike@mikewilsonstl.com>
# Created: 2025-12-16T16:48:56+00:00
# Description: This script generates ed25519 keys and
#              displays the key to the user for approval.
#              This allows the user to rapidly regenerate
#              keys until they find one they like.

set -euo pipefail
shopt -s extglob

KEYNAME=""
KEYPATH=""
COMMENT=""
PASSPHRASE=""
ACCEPTED=false
GENERATED=false

cleanup() {
    if ! $ACCEPTED && $GENERATED; then
        rm -f "$KEYPATH" "$KEYPATH.pub"
    fi
}

trap cleanup EXIT INT TERM

main() {
    read -r -p "Enter key name [id_ed25519]: " KEYNAME
    KEYNAME="${KEYNAME:-id_ed25519}"
    KEYPATH="$HOME/.ssh/$KEYNAME"

    if [[ -e "$KEYPATH" || -e "$KEYPATH.pub" ]]; then
        read -r -p "Key already exists. Overwrite? [y/N]: " reply
        reply="${reply,,}"
        [[ "$reply" == "y" || "$reply" == "yes" ]] || {
            echo "Aborted."
            exit 1
        }
        rm -f "$KEYPATH" "$KEYPATH.pub"
    fi

    read -r -p "Enter comment: " COMMENT
    read -r -s -p "Enter passphrase: " PASSPHRASE
    echo
    while ! $ACCEPTED; do
	clear
        ssh-keygen -t ed25519 \
            -f "$KEYPATH" \
            -C "$COMMENT" \
            -N "$PASSPHRASE"
        GENERATED=true
        echo
        cat "$KEYPATH.pub"
        echo
        echo "Enter 'y' to accept key. Hit 'Enter' to generate another key."
        read -r -p "" reply
        reply="${reply,,}"

        if [[ "$reply" == "y" || "$reply" == "yes" ]]; then
            ACCEPTED=true
        else
            rm -f "$KEYPATH" "$KEYPATH.pub"
            GENERATED=false
        fi
    done
    echo
    echo "Keys created:"
    echo "    $KEYPATH"
    echo "    $KEYPATH.pub"
}

main "$@"
