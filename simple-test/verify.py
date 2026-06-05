"""
Simple verification of the deny-storage-public-network-access policy
deployed by deny-storage-public.bicep.

Runs two ARM validations against the same resource group:

  1. Storage account with publicNetworkAccess = Enabled  -> expected DENY
  2. Storage account with publicNetworkAccess = Disabled -> expected ALLOW

No resources are created (uses `az deployment group validate`).
Exits 0 only if both expectations hold.

Required environment variables
------------------------------
  VAL_RG            An existing RG in a subscription where the policy is assigned.
  VAL_LOC           Region (default: eastus).
  VAL_EXPECTED_MSG  Non-compliance message to look for in the deny
                    (default: "Private Endpoints Must Be Enabled - No Public Access").
"""
import json
import os
import random
import string
import subprocess
import sys
import tempfile


def _required(name):
    v = os.environ.get(name)
    if not v:
        sys.stderr.write(f"ERROR: required env var {name} is not set.\n")
        sys.exit(2)
    return v


RG = _required("VAL_RG")
LOC = os.environ.get("VAL_LOC", "eastus")
EXPECTED_MSG = os.environ.get(
    "VAL_EXPECTED_MSG",
    "Private Endpoints Must Be Enabled - No Public Access",
)


def rname():
    return "stpetest" + "".join(random.choices(string.ascii_lowercase + string.digits, k=8))


def template(public_access):
    return {
        "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
        "contentVersion": "1.0.0.0",
        "resources": [{
            "type": "Microsoft.Storage/storageAccounts",
            "apiVersion": "2023-01-01",
            "name": rname(),
            "location": LOC,
            "sku": {"name": "Standard_LRS"},
            "kind": "StorageV2",
            "properties": {
                "publicNetworkAccess": public_access,
                "minimumTlsVersion": "TLS1_2",
            },
        }],
    }


def run_validate(public_access):
    fd, path = tempfile.mkstemp(suffix=".json", prefix="simpletest_")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(template(public_access), f)
        proc = subprocess.run(
            ["az", "deployment", "group", "validate",
             "--resource-group", RG,
             "--template-file", path,
             "--output", "json"],
            capture_output=True, text=True, shell=True, timeout=90,
        )
        return (proc.stdout or "") + "\n" + (proc.stderr or "")
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass


def main():
    print(f"Resource group : {RG}")
    print(f"Location       : {LOC}")
    print(f"Expected msg   : {EXPECTED_MSG!r}\n")

    print("[TEST 1] Storage account with publicNetworkAccess=Enabled (expecting DENY)...")
    out = run_validate("Enabled")
    if "RequestDisallowedByPolicy" in out and EXPECTED_MSG in out:
        print("  -> PASS: blocked with the custom non-compliance message.\n")
        test1 = True
    elif "RequestDisallowedByPolicy" in out:
        print(f"  -> WARN: blocked, but custom message {EXPECTED_MSG!r} was not found.\n")
        test1 = False
    else:
        print("  -> FAIL: NOT blocked. Raw output:\n")
        print(out[:1500])
        test1 = False

    print("[TEST 2] Storage account with publicNetworkAccess=Disabled (expecting ALLOW)...")
    out = run_validate("Disabled")
    if "RequestDisallowedByPolicy" not in out and ('"validationLevel"' in out or '"properties"' in out):
        print("  -> PASS: allowed.\n")
        test2 = True
    else:
        print("  -> FAIL: unexpectedly blocked. Raw output:\n")
        print(out[:1500])
        test2 = False

    if test1 and test2:
        print("Both tests passed. The Storage public-access deny policy is enforcing as expected.")
        return 0
    print("One or more tests failed.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
