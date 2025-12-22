#!/usr/bin/env python3
#
# WARNING: This is a descructive script that will result in data loss.
#
# Usage: ./verify-wipe.py [drive]
# Author: Mike Wilson <mike@mikewilsonstl.com>
# Created: 2025-12-22T14:21:25-05:00
# Description: An SMR drive sanitization testing utility. Calculates a 
#              hash of the drive data, sends ATA sanitization command, 
#              waits for the sanitize operation to finish, and
#              recalculates the hash from the same part of the drive.
#              Returns the result of the comparison.

import os
import re
import sys
import json
import signal
import socket
import subprocess
from tqdm import tqdm
from pathlib import Path
from datetime import datetime
from multiprocessing import Process, Queue, Event

# Copying David's new hash for furture integrtion
_PATTERN_HEX=0xC01DC0FFEECAFE

DEFAULT_PATTERN = b"\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF" # replace this with David's new pattern next iteration
BUF_SIZE = 4 * 1024 * 1024
LOG_PATHS = ["./pattern_scanner.log"]

NTFY_URL = "https://ntfy.sh/nrxbyeUHKUoxAcazJkjkKdphTrq9qFqkVdoYLfryJLLYqgdJ4vHuU3VtjzJv3fuZ"

# logging
def get_log_path():
    for path in LOG_PATHS:
        try:
            with open(path, "a"):
                return path
        except PermissionError:
            continue
    print("WARNING: Could not write to log file. Logging disabled.")
    return None

LOG_FILE = get_log_path()

def log(msg):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    final = f"[{timestamp}] {msg}"
    if LOG_FILE:
        with open(LOG_FILE, "a") as f:
            f.write(final + "\n")
    print(final)

# helper functions
def run_cmd(cmd):
    return subprocess.check_output(cmd, text=True).strip()

def require_root():
    if os.geteuid() != 0:
        print("ERROR: This tool must be run as root.", file=sys.stderr)
        sys.exit(1)

def get_device_size(dev):
    try:
        result = subprocess.run(
            ["blockdev", "--getsize64", dev],
            capture_output=True, text=True, check=True
        )
        return int(result.stdout.strip())
    except Exception:
        return None

# multipath-aware drive enumeration
def list_block_devices():
    """
    Enumerate real physical drives:
      via SAS expanders (/dev/disk/by-path/*sas-exp*)
      excludes partitions
      excludes root device
      excludes multipath backing devices
      returns dicts with path/model/serial/size
    """

    drives = []

    # determine root device
    root_device = None
    try:
        root_mount = run_cmd(["findmnt", "-no", "SOURCE", "/"])
        root_device = re.sub(r"(\d+|p\d+)$", "", root_mount)
    except Exception:
        root_device = None

    # get multipath devices
    multipath_backing = set()
    try:
        mp_ll = run_cmd(["multipath", "-ll"])
        pattern = r"\b((?:sd[a-z]{1,2}|nvme\d+n\d+))\b"
        for line in mp_ll.splitlines():
            for dev_name in re.findall(pattern, line):
                multipath_backing.add(f"/dev/{dev_name}")
    except Exception:
        pass  # multipath not present

    # scan SAS expanders
    by_path = Path("/dev/disk/by-path")
    if by_path.exists():
        for entry in sorted(by_path.iterdir()):
            name = entry.name
            if "sas-exp" in name and not name.endswith("part"):
                dev_path = str(entry.resolve())

                # exclusions
                if dev_path == root_device:
                    continue
                if dev_path in multipath_backing:
                    continue
                if dev_path not in drives:
                    drives.append(dev_path)

    result = []
    for dev in sorted(drives):
        # lookup model/serial/size via lsblk
        try:
            lsblk_out = run_cmd(["lsblk", "-o", "MODEL,SERIAL,SIZE", "-n", dev])
            parts = lsblk_out.split(None, 2)
            model = parts[0] if len(parts) > 0 else "Unknown"
            serial = parts[1] if len(parts) > 1 else "Unknown"
            size = parts[2] if len(parts) > 2 else "Unknown"
        except Exception:
            model = serial = size = "Unknown"

        result.append({
            "path": dev,
            "model": model,
            "serial": serial,
            "size": size
        })

    return result

# drive table formatting
def print_drive_table(devices):
    headers = ["#", "Device", "Model", "Serial", "Size"]
    rows = []

    for i, d in enumerate(devices, 1):
        rows.append([
            str(i),
            d["path"],
            d["model"],
            d["serial"],
            d["size"]
        ])

    col_widths = [max(len(str(row[i])) for row in rows + [headers]) + 2 for i in range(len(headers))]

    def fmt_row(r):
        return "|" + "".join(r[i].ljust(col_widths[i]) for i in range(len(r))) + "|"

    print("+" + "+".join("-" * w for w in col_widths) + "+")
    print(fmt_row(headers))
    print("+" + "+".join("-" * w for w in col_widths) + "+")
    for r in rows:
        print(fmt_row(r))
    print("+" + "+".join("-" * w for w in col_widths) + "+")

# drive selection
def parse_drive_selection(selection_str, max_index):
    selection_str = selection_str.replace(" ", "")
    parts = selection_str.split(",")
    indices = set()

    for part in parts:
        if "-" in part:
            try:
                start, end = map(int, part.split("-"))
                if start > end:
                    start, end = end, start
                for i in range(start, end + 1):
                    if 1 <= i <= max_index:
                        indices.add(i - 1)
            except ValueError:
                pass
        else:
            if part.isdigit():
                i = int(part)
                if 1 <= i <= max_index:
                    indices.add(i - 1)

    return sorted(indices)

def choose_devices(devices):
    print("Available Drives:")
    print_drive_table(devices)

    while True:
        try:
            print("CURRENT VERSION ONLY SUPPORTS 16 DRIVES AT A TIME")
            choices = input("Select drive(s) (supports ranges: 2-5,8,10,13-15): ").strip()
        except KeyboardInterrupt:
            print("\nCTRL+C detected — exiting before scan.")
            sys.exit(1)

        if not choices:
            print("No selection made. Please enter at least one drive.")
            continue

        indices = parse_drive_selection(choices, len(devices))
        if not indices:
            print("No valid drives selected. Please try again.")
            continue

        return [devices[i] for i in indices]

# Pattern input
def get_pattern():
    while True:
        try:
            user_input = input(f"Enter hex pattern (default={DEFAULT_PATTERN.hex().upper()}): ").strip()
        except KeyboardInterrupt:
            print("\nCTRL+C detected — exiting before scan.")
            sys.exit(1)

        if not user_input:
            return DEFAULT_PATTERN

        try:
            pattern_bytes = bytes.fromhex(user_input)
            if len(pattern_bytes) == 0:
                print("Pattern cannot be empty.")
                continue
            return pattern_bytes
        except ValueError:
            print("Invalid hex — try again or press Enter for default.")

# Worker process
cancel_event = Event()

def scan_device_worker(dev_info, pattern, result_queue, progress_queue, cancel_event, position):
    dev = dev_info["path"]
    total_size = get_device_size(dev)
    offset = 0

    try:
        with open(dev, "rb", buffering=0) as f:
            pbar = tqdm(
                total=total_size,
                unit="B",
                unit_scale=True,
                desc=f"Scanning {os.path.basename(dev)}",
                position=position,
                leave=True,
                miniters=1,
            )

            while True:
                if cancel_event.is_set():
                    pbar.close()
                    result_queue.put((dev, "cancelled", None))
                    return

                chunk = f.read(BUF_SIZE)
                if not chunk:
                    pbar.close()
                    result_queue.put((dev, "not_found", None))
                    return

                progress_queue.put(len(chunk))

                idx = chunk.find(pattern)
                if idx != -1:
                    found_offset = offset + idx
                    pbar.close()
                    result_queue.put((dev, "found", found_offset))
                    return

                offset += len(chunk)
                pbar.update(len(chunk))

    except Exception as e:
        result_queue.put((dev, "error", str(e)))

# SIGINT handler
def handle_sigint(signum, frame):
    print("\nCTRL+C detected — stopping all scans...")
    cancel_event.set()

# JSON report + NTFY notification
def write_json_report(results, pattern_hex, start_ts, end_ts):
    report = {
        "pattern": pattern_hex,
        "started": start_ts,
        "completed": end_ts,
        "drives": results,
    }

    with open("./scan_report.json", "w") as f:
        json.dump(report, f, indent=4)

    log("Saved JSON report to scan_report.json")

def send_ntfy(results, pattern_hex):
    hostname = socket.gethostname()

    message = f"Pattern scan complete on {hostname}\n\n"
    for dev, info in results.items():
        status = info["status"]
        message += f"{dev}: {status}"
        if status == "found" and "offset" in info:
            message += f' ("{pattern_hex}" at offset {info["offset"]})'
        else:
            message += f' ("{pattern_hex}")'
        message += "\n"

    try:
        subprocess.run([
            "curl", "-d", message,
            "-H", "Title: Pattern Scan Complete",
            NTFY_URL
        ], check=True)
    except subprocess.CalledProcessError as e:
        log(f"Failed to send ntfy notification: {e}")

def main():
    require_root()

    devices = list_block_devices()
    if not devices:
        print("No drives found.")
        sys.exit(1)

    # disable SIGINT during menu prompts
    signal.signal(signal.SIGINT, signal.SIG_DFL)

    try:
        selected = choose_devices(devices)
        pattern = get_pattern()
    except KeyboardInterrupt:
        print("\nCTRL+C — exiting before scan.")
        sys.exit(1)

    pattern_hex = pattern.hex().upper()
    start_ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    total_bytes = sum(get_device_size(d["path"]) or 0 for d in selected)

    # enable scan-interrupt handler
    signal.signal(signal.SIGINT, handle_sigint)

    result_queue = Queue()
    progress_queue = Queue()
    processes = []

    print("\nStarting parallel scan...\n")

    master_position = len(selected)
    master_pbar = tqdm(
        total=total_bytes,
        unit="B",
        unit_scale=True,
        desc="TOTAL SCAN",
        position=master_position,
        leave=True,
        miniters=1,
    )

    # launch workers
    for index, dev_info in enumerate(selected):
        p = Process(
            target=scan_device_worker,
            args=(dev_info, pattern, result_queue, progress_queue, cancel_event, index)
        )
        p.start()
        processes.append(p)

    # progress aggregation
    active = len(processes)
    while active > 0:
        try:
            while not progress_queue.empty():
                master_pbar.update(progress_queue.get())

            for p in processes[:]:
                if not p.is_alive():
                    processes.remove(p)
                    active -= 1

        except KeyboardInterrupt:
            cancel_event.set()

    master_pbar.close()

    # collect results
    results = {}
    while not result_queue.empty():
        dev, status, info = result_queue.get()
        entry = {"status": status}
        if info is not None:
            entry["offset"] = info
        results[dev] = entry

    end_ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    write_json_report(results, pattern_hex, start_ts, end_ts)
    send_ntfy(results, pattern_hex)

    print("\nScan Results:")
    print("-----------------------------------------------------------")
    for dev, info in results.items():
        print(f"{dev}: {info}")

    sys.exit(0)

if __name__ == "__main__":
    main()

