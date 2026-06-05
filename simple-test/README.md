# Simple Test — Deny Public Network Access on Storage Accounts

The smallest possible end-to-end example: **one Bicep file** deploys
**one custom Azure Policy** that blocks creation of Storage Accounts
that allow public network access, and **one Python script** verifies it
works.

This is a self-contained "hello world" version of the main project — no
initiatives, no Terraform, no management groups. Deploy at any
subscription, test, and tear down in under five minutes.

---

## What this deploys

A subscription-scoped custom policy definition + assignment with:

- **Effect:** `Deny` (the assignment parameter also accepts `Audit` and
  `Disabled` for soft rollouts).
- **Custom non-compliance message:**
  > "Private Endpoints Must Be Enabled - No Public Access"

The rule:

```
if  resource.type == "Microsoft.Storage/storageAccounts"
AND resource.properties.publicNetworkAccess != "Disabled"
then deny
```

---

## Prerequisites

1. **Azure CLI** 2.50+ (`az --version`).
2. **Logged in**: `az login`.
3. **Active subscription set**: `az account set --subscription "<sub-name-or-id>"`.
4. **Permissions**: `Owner` or `User Access Administrator` at the
   subscription scope (needed to create the policy assignment).
5. **Python 3.8+** (only if you want to run the scripted `verify.py`).

Bicep CLI is bundled with `az` — nothing else to install.

---

## Step 1 — Deploy the policy

From this folder:

```bash
az deployment sub create \
  --location eastus \
  --template-file deny-storage-public.bicep
```

Outputs:
- A custom policy definition named `deny-storage-public-network-access`.
- A policy assignment named `deny-storage-public` at the subscription scope.

### Optional parameters

| Parameter | Default | Notes |
|---|---|---|
| `policyName` | `deny-storage-public-network-access` | Name of the custom policy definition. |
| `assignmentName` | `deny-storage-public` | Name of the assignment. |
| `policyDisplayName` | `Storage accounts must disable public network access` | Shown in the portal. |
| `nonComplianceMessage` | `Private Endpoints Must Be Enabled - No Public Access` | The custom message returned to anyone who is blocked. |
| `effect` | `Deny` | `Audit` (soft rollout) or `Disabled` (turn off) are also accepted. |

Example with overrides:

```bash
az deployment sub create \
  --location eastus \
  --template-file deny-storage-public.bicep \
  --parameters effect=Audit \
               nonComplianceMessage="Storage public access is forbidden in this subscription."
```

### Want subscription scope vs management-group scope?

This template deploys at **subscription scope**. To deploy at a
management-group scope instead, change the first line of the Bicep file
from `targetScope = 'subscription'` to `targetScope = 'managementGroup'`
and deploy with `az deployment mg create ... --management-group-id <mg>`.

---

## Step 2 — Test it manually (one-liner)

Create a temporary resource group and try to create a Storage Account
with public access enabled — it should be **denied** with your custom
message.

```bash
az group create -n storage-policy-test-rg -l eastus

# Should FAIL with "Private Endpoints Must Be Enabled - No Public Access"
az storage account create \
  -n stpetest$RANDOM \
  -g storage-policy-test-rg \
  -l eastus \
  --sku Standard_LRS \
  --public-network-access Enabled
```

Expected output (excerpt):

```
... (RequestDisallowedByPolicy) ... Resource 'stpetestXXXXX' was disallowed by policy.
Reasons: 'Private Endpoints Must Be Enabled - No Public Access'.
```

Now confirm the same command **with public access disabled** is
allowed:

```bash
az storage account create \
  -n stpetest$RANDOM \
  -g storage-policy-test-rg \
  -l eastus \
  --sku Standard_LRS \
  --public-network-access Disabled
```

This one succeeds and creates a (private-only) storage account.

---

## Step 2 (alternative) — Scripted verification

`verify.py` runs both tests automatically using `az deployment group
validate` (no resources are actually created — fast, no cleanup):

```bash
export VAL_RG=storage-policy-test-rg
export VAL_LOC=eastus
python verify.py
```

PowerShell / Cloud Shell PowerShell:

```powershell
$env:VAL_RG  = "storage-policy-test-rg"
$env:VAL_LOC = "eastus"
python verify.py
```

Expected output:

```
[TEST 1] Storage account with publicNetworkAccess=Enabled (expecting DENY)...
  -> PASS: blocked with the custom non-compliance message.

[TEST 2] Storage account with publicNetworkAccess=Disabled (expecting ALLOW)...
  -> PASS: allowed.

Both tests passed. The Storage public-access deny policy is enforcing as expected.
```

Exit code is `0` on success, `1` on any failure.

---

## Step 3 — Clean up

```bash
# Any test storage account you created
az storage account delete -n <name> -g storage-policy-test-rg --yes

# The test resource group
az group delete -n storage-policy-test-rg --yes --no-wait

# Policy assignment and definition
az policy assignment delete --name deny-storage-public
az policy definition delete --name deny-storage-public-network-access
```

---

## When to use this folder vs the full initiative

| If you want to... | Use |
|---|---|
| Demo the concept, try it on a single sub, or learn how an Azure Policy deny works | This folder (`simple-test/`) |
| Cover all 62 PaaS services across a management group | The full initiative in the project root |
| Validate the full deployed initiative end-to-end | [`validation-testing/`](../validation-testing/) |

---

## Files

| File | Purpose |
|---|---|
| `deny-storage-public.bicep` | Subscription-scoped Bicep — policy definition + assignment. |
| `verify.py` | Scripted validation: enabled (expect DENY) + disabled (expect ALLOW). |
| `README.md` | This file. |
