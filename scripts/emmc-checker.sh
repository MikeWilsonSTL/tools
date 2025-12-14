#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 Mike Wilson
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: [how to run the script, e.g., ./script_name.sh <arguments>]
# Author: Mike Wilson <mike@mikewilsonstl.com>
# Created: 2025-12-14T15:09:21-05:00
# Description: [brief purpose of the script]

set -euo pipefail
shopt -s extglob

extract_hex_field() {
    local field="$1"
    local val

    val=$(echo "$EXTCSD" | grep -E "$field" | head -1 | grep -o "0x[0-9a-fA-F]+")
    [[ -n "$val" ]] && { echo "$val"; return; }

    val=$(echo "$EXTCSD" | sed -n "s/.*${field}[^0-9A-Fa-f]*\(0x[0-9A-Fa-f]\+\).*/\1/p")
    [[ -n "$val" ]] && { echo "$val"; return; }

    val=$(echo "$EXTCSD" | awk "/$field/ {for(i=1;i<=NF;i++) if(\$i ~ /^0x/) print \$i; exit}")
    echo "$val"
}

decode_card_type() {
    local hex
    hex=$(echo "$1" | tr 'a-f' 'A-F')
    [[ -z "$hex" ]] && { echo "Unknown"; return; }

    local val=$((hex))
    local modes=()

    (( val & 0x80 )) && modes+=("HS400 (200 MHz DDR)")
    (( val & 0x40 )) && modes+=("HS200 (200 MHz SDR)")
    (( val & 0x20 )) && modes+=("DDR52")
    (( val & 0x10 )) && modes+=("HS52")
    (( val & 0x08 )) && modes+=("HS26")

    ((${#modes[@]} == 0)) && echo "Unknown" || printf "%s " "${modes[@]}"
}

decode_wear() {
    case $1 in
        0x01) echo "1: 0–10% used (Excellent)" ;;
        0x02) echo "2: 10–20% used" ;;
        0x03) echo "3: 20–30% used" ;;
        0x04) echo "4: 30–40% used" ;;
        0x05) echo "5: 40–50% used" ;;
        0x06) echo "6: 50–60% used" ;;
        0x07) echo "7: 60–70% used" ;;
        0x08) echo "8: 70–80% used" ;;
        0x09) echo "9: 80–90% used" ;;
        0x0A) echo "10: 90–100% used (End of Life)" ;;
        *) echo "Unknown" ;;
    esac
}

decode_pre_eol() {
    case $1 in
        0x01) echo "1: Normal" ;;
        0x02) echo "2: Warning" ;;
        0x03) echo "3: Critical" ;;
        *) echo "Unknown" ;;
    esac
}

assess_health() {
    local wear_a=${1#0x}
    local wear_b=${2#0x}
    local pre_eol=${3#0x}
    local bad_blocks="$4"

    local wa=$((16#$wear_a))
    local wb=$((16#$wear_b))
    local pe=$((16#$pre_eol))

    local health="Normal"

    if (( wa >= 8 || wb >= 8 || pe == 2 )); then
        health="Warning"
    fi

    if [[ "$bad_blocks" != "Not supported" ]] && (( bad_blocks > 0 )); then
        health="Warning"
    fi

    if (( wa == 10 || wb == 10 || pe == 3 )); then
        health="Critical"
    fi

    echo "$health"
}

main() {
    # enforce root
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root (use sudo)."
        exit 1
    fi

    # get device from CLI or prompt
    if [[ -n "$1" ]]; then
        DEVICE="$1"
    else
        read -rp "Enter the eMMC device (e.g., /dev/mmcblk0): " DEVICE
    fi

    # check if the device exists
    if [[ ! -b "$DEVICE" ]]; then
        echo "Error: $DEVICE is not a valid block device."
        exit 1
    fi

    if ! EXTCSD=$(sudo mmc extcsd read "$DEVICE" 2>/dev/null); then
        echo "Error: Unable to read EXT_CSD from $DEVICE."
        exit 1
    fi

    # extract device info
    DEV_NAME=$(basename "$DEVICE")
    SYS_PATH="/sys/block/$DEV_NAME/device"

    if [[ -r "$SYS_PATH/cid" ]]; then
        CID_RAW=$(cat "$SYS_PATH/cid")
        CID=${CID_RAW,,}

        MID=${CID_RAW:0:2}

        # --- Serial (PSN) ---
        SERIAL_HEX=${CID_RAW:16:8}
        if [[ $SERIAL_HEX =~ ^[0-9a-fA-F]{8}$ ]]; then
            SERIAL_DEC=$((16#$SERIAL_HEX))
        else
            SERIAL_HEX="Unknown"
            SERIAL_DEC="Unknown"
        fi

        # product name (PNM, 5 ASCII bytes = 10 hex chars)
        PNM_HEX=${CID:6:10}
        _PNM=$(echo "$PNM_HEX" | xxd -r -p 2>/dev/null)

        # MDT = CID byte 14 (2nd to last byte)
        MDT_BYTE_HEX=${CID:28:2}
        MDT_BYTE=$((16#$MDT_BYTE_HEX))

        MDT_YEAR_OFFSET=$(( (MDT_BYTE >> 4) & 0xF ))
        MDT_MONTH=$(( MDT_BYTE & 0xF ))
        MDT_YEAR=$(( 1997 + MDT_YEAR_OFFSET ))

        if (( MDT_MONTH >= 1 && MDT_MONTH <= 12 )); then
            _MDT_HUMAN="$MDT_YEAR-$MDT_MONTH"
        else
            _MDT_HUMAN="Unknown"
        fi
    else
        CID_RAW=""
        MID="Unknown"
        SERIAL_HEX="Unknown"
        SERIAL_DEC="Unknown"
    fi

    if [[ -r "$SYS_PATH/name" ]]; then
        MODEL=$(cat "$SYS_PATH/name")
    else
        MODEL="Unknown"
    fi

    case "$MID" in
        15|0F) MANU="Samsung" ;;
        13|0D) MANU="Micron" ;;
        11|0B) MANU="Toshiba/Kioxia" ;;
        90) MANU="SK Hynix" ;;
        45) MANU="SanDisk / Western Digital" ;;
        *) MANU="Unknown" ;;
    esac

    FW=$(echo "$EXTCSD" | grep -i "Firmware Version" | awk '{print $NF}')

    SEC_COUNT=$(extract_hex_field "SEC_COUNT")
    BYTES=$((SEC_COUNT))
    CAP_GIB=$(printf "%.2f" "$(echo "$BYTES / 2097152" | bc -l)")

    CARD_TYPE_HEX=$(extract_hex_field "CARD_TYPE")
    SUPPORTED_MODES=$(decode_card_type "$CARD_TYPE_HEX")

    ACTIVE_MODE_HEX=$(extract_hex_field "HS_TIMING")
    ACTIVE_MODE_HEX=${ACTIVE_MODE_HEX#0x}

    # detect active bus mode
    ACTIVE_MODE="Unknown"

    if sudo dmesg | grep -iq "mmc0: new .* MMC card"; then
        MODE_LINE=$(sudo dmesg | grep -i "mmc0: new .* MMC card" | tail -1)
        if [[ $MODE_LINE =~ HS400 ]]; then ACTIVE_MODE="HS400"
        elif [[ $MODE_LINE =~ HS200 ]]; then ACTIVE_MODE="HS200"
        elif [[ $MODE_LINE =~ HS52 ]]; then ACTIVE_MODE="HS52"
        elif [[ $MODE_LINE =~ HS26 ]]; then ACTIVE_MODE="HS26"
        fi
    fi

    # fallback to EXT_CSD
    if [[ "$ACTIVE_MODE" == "Unknown" && -n "$ACTIVE_MODE_HEX" ]]; then
        case "$ACTIVE_MODE_HEX" in
            01) ACTIVE_MODE="High-Speed (26 MHz)" ;;
            02) ACTIVE_MODE="High-Speed (52 MHz)" ;;
            03) ACTIVE_MODE="HS200" ;;
            04) ACTIVE_MODE="HS400" ;;
        esac
    fi

    if [[ "$SUPPORTED_MODES" != *"$ACTIVE_MODE"* && "$ACTIVE_MODE" != "Unknown" ]]; then
        SUPPORTED_MODES="$SUPPORTED_MODES $ACTIVE_MODE"
    fi

    WEAR_A=$(extract_hex_field "DEVICE_LIFE_TIME_EST_TYP_A")
    WEAR_B=$(extract_hex_field "DEVICE_LIFE_TIME_EST_TYP_B")
    PRE_EOL=$(extract_hex_field "PRE_EOL_INFO")

    WEAR_A_DESC=$(decode_wear "$WEAR_A")
    WEAR_B_DESC=$(decode_wear "$WEAR_B")
    PRE_EOL_DESC=$(decode_pre_eol "$PRE_EOL")

    POWER_CYCLES=$(extract_hex_field "POWER_CYCLE" | sed 's/0x//')
    [[ -n "$POWER_CYCLES" ]] && POWER_CYCLES=$((16#$POWER_CYCLES)) || POWER_CYCLES="Not supported"

    BAD_BLOCKS=$(echo "$EXTCSD" | grep -i "bad" | grep -o "0x[0-9A-Fa-f]\+" | head -1)
    [[ -n "$BAD_BLOCKS" ]] && BAD_BLOCKS=$((BAD_BLOCKS)) || BAD_BLOCKS="Not supported"

    HEALTH=$(assess_health "$WEAR_A" "$WEAR_B" "$PRE_EOL" "$BAD_BLOCKS")

    # print report
    # PNM removed because $MODEL is untruncated
    # manufacturing Date removed because the dates are optional/unreliable
    cat <<EOF
    ==============================================
    eMMC "SMART" Health Report for $DEVICE
    ==============================================

    Manufacturer:                   $MANU (MID $MID)
    Model:                          $MODEL
    Serial Number (CID):            $SERIAL_DEC ($SERIAL_HEX)
    Firmware Version:               $FW
    Capacity:                       ${CAP_GIB} GiB

    Supported Bus Modes:            $SUPPORTED_MODES
    Active Bus Mode:                ${ACTIVE_MODE:-Unknown}

    Wear Level (A):                 $WEAR_A ($WEAR_A_DESC)
    Wear Level (B):                 $WEAR_B ($WEAR_B_DESC)
    Pre-EOL Status:                 $PRE_EOL ($PRE_EOL_DESC)

    Power Cycle Count:              $POWER_CYCLES
    Bad Block Count:                $BAD_BLOCKS

    Overall Health Assessment:      $HEALTH

    (*) Wear Level A/B:
        1 = 0–10% used              A = internal controller wear
        10 = 90-100% used           B = host write wear

    (*) Pre-EOL Levels:
        1 = Normal, 2 = Warning, 3 = Critical

EOF
}

main "$@"
