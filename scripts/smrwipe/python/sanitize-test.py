#!/usr/bin/env python3
#
# WARNING: This is a descructive script that will result in data loss.
#
# Usage: ./sanitize-test [drive]
# Author: Mike Wilson <mike@mikewilsonstl.com>
# Created: 2025-12-22T14:21:25-05:00
# Description: An SMR drive sanitization testing utility. Calculates a 
#              hash of the drive data, sends ATA sanitization command, 
#              waits for the sanitize operation to finish, and
#              recalculates the hash from the same part of the drive.
#              Returns the result of the comparison.

import subprocess
import hashlib
import time
import sys
import argparse
import os

# Default block settings for hashing
HASH_BLOCKS = 5     # number of 10MB blocks to hash for testing
BLOCK_SIZE = "10M"

def require_root():
    if os.geteuid() != 0:
        print("This script must be run as root!")
        sys.exit(1)

def run_cmd(cmd):
    """Run a shell command and return stdout."""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Command failed: {cmd}")
        print(e.stderr)
        sys.exit(1)

def check_sanitize_status(drive):
    output = run_cmd(f"hdparm --sanitize-status {drive}")
    print(f"Sanitize status:\n{output}")
    if "Sanitize Idle" not in output:
        print("Drive may be in a sanitize operation already. Exiting.")
        sys.exit(1)

def hash_drive_segment(drive):
    print(f"Hashing first {HASH_BLOCKS} blocks ({BLOCK_SIZE} each) of {drive}...")
    sha256 = hashlib.sha256()
    dd_cmd = f"dd if={drive} bs={BLOCK_SIZE} count={HASH_BLOCKS} status=none"
    proc = subprocess.Popen(dd_cmd, shell=True, stdout=subprocess.PIPE)
    for chunk in iter(lambda: proc.stdout.read(1024*1024), b''):
        sha256.update(chunk)
    proc.wait()
    digest = sha256.hexdigest()
    print(f"Computed hash: {digest}")
    return digest

def run_crypto_scramble(drive):
    print("Issuing crypto-scramble sanitize command...")
    run_cmd(f"hdparm --yes-i-know-what-i-am-doing --verbose --sanitize-crypto-scramble {drive}")

def wait_for_sanitize_completion(drive, poll_interval=5):
    print("Waiting for sanitize operation to complete...")
    while True:
        output = run_cmd(f"hdparm --sanitize-status {drive}")
        if "Sanitize Idle" in output:
            print("Sanitize operation complete.")
            break
        else:
            print("Sanitize in progress, waiting...")
            time.sleep(poll_interval)

def main():
    require_root()

    parser = argparse.ArgumentParser(description="Crypto-scramble testing script")
    parser.add_argument("drive", help="Target drive (e.g., /dev/sdai)")
    args = parser.parse_args()
    drive = args.drive

    print(f"Starting crypto-scramble test for {drive}")
    check_sanitize_status(drive)
    pre_hash = hash_drive_segment(drive)
    run_crypto_scramble(drive)
    wait_for_sanitize_completion(drive)
    post_hash = hash_drive_segment(drive)
    
    print("\n=== DIAGNOSTICS ===")
    print(f"Pre-sanitize hash : {pre_hash}")
    print(f"Post-sanitize hash: {post_hash}")
    if pre_hash == post_hash:
        print("WARNING: Hash did not change — crypto-scramble may not have run successfully!")
    else:
        print("SUCCESS: Hash changed — crypto-scramble appears to have worked.")

if __name__ == "__main__":
    main()

