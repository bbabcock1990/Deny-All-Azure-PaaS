# Validation Testing

End-to-end validation harness that confirms the deployed
`Deny-PublicPaaSEndpoints` initiative actually denies each of the 62 PaaS
services it claims to cover, **and** that your custom non-compliance message
is returned to the caller.

The harness is **read-only / safe to re-run**: it submits each minimal
ARM template through `az deployment group validate`, which runs the full
Azure Policy evaluation engine **without creating any resources**.

---

## What it does

For every service in the initiative the script:

1. Builds a minimal ARM template that sets the relevant "public network
   access" field to its enabled value.
2. Runs `az deployment group validate --resource-group <RG> --template-file <tmp>`.
3. Parses the result and classifies it as one of:

| Outcome | Meaning |
|---|---|
| `[PASS]`  | Policy denied as expected, the *expected* `policyDefinitionReferenceId` fired. |
| `[PASS*]` | Policy denied at deploy time, but a different (overlapping) policy reference fired first. Functionally equivalent. |
| `[AUDIT]` | API Management and Managed Disks — the upstream ALZ definitions explicitly disallow `Deny` (their `allowedValues` are `Audit`/`AuditIfNotExists`/`Disabled` only). This is **expected** and documented in the project root README. |
| `[FAIL]`  | Template error, region error, or another non-policy failure. Re-check the template. |
| `[!!!!]`  | **Regression.** The service was allowed when it should have been denied (or an audit-only service unexpectedly denied). |

The script exits non-zero if it sees any `[FAIL]` or `[!!!!]` so it can
be wired into CI.

---

## Prerequisites

1. **Python 3.8+** on the machine running the script (Cloud Shell already has it).
2. **Azure CLI** signed in to the right tenant: `az login`.
3. **A target subscription that already inherits the assignment.** The
   initiative is assigned at a management group, so the subscription
   that owns the test RG must be a child of that MG. Verify with:

   ```bash
   az account management-group entities list -o table
   ```

4. **A target resource group** (e.g., `Demo-ParkPlace-Rg`) that exists
   in that subscription. Create one if needed:

   ```bash
   az group create --name Demo-ParkPlace-Rg --location centralus
   ```

5. **Permissions:** the calling identity needs
   `Microsoft.Resources/deployments/validate/action` on the RG (Contributor
   is sufficient). No write permissions are needed — the script only
   *validates*, never deploys.

---

## How to run

### 1. Clone and set environment variables

```bash
git clone https://github.com/bbabcock1990/Deny-All-Azure-PaaS.git
cd Deny-All-Azure-PaaS/validation-testing

# Required
export VAL_SUB_ID="00000000-0000-0000-0000-000000000000"     # subscription that owns the RG
export VAL_TENANT_ID="11111111-1111-1111-1111-111111111111"  # your AAD tenant id
export VAL_RG="Demo-ParkPlace-Rg"                             # an existing RG inheriting the policy

# Optional
export VAL_LOC="centralus"                                    # default region for most templates
export VAL_FALLBACK_LOC="eastus"                              # region for Purview / Healthcare APIs / Digital Twins
export VAL_EXPECTED_MSG="Private Endpoints Must Be Enabled - No Public Access"
```

In **PowerShell / Cloud Shell PowerShell**:

```powershell
$env:VAL_SUB_ID    = "00000000-0000-0000-0000-000000000000"
$env:VAL_TENANT_ID = "11111111-1111-1111-1111-111111111111"
$env:VAL_RG        = "Demo-ParkPlace-Rg"
$env:VAL_LOC       = "centralus"
```

### 2. Run the validator

```bash
python validate_policy.py
```

You'll see one line per service:

```
[PASS]  [ 1/62] Cosmos DB                                   -> DENIED                 (fired: CosmosDenyPaasPublicIP) [3.1s]
[PASS]  [ 2/62] Key Vault                                   -> DENIED                 (fired: KeyVaultDenyPaasPublicIP) [3.1s]
...
[AUDIT] [22/62] API Management                              -> ALLOWED                (fired: -)  [3.3s]
...
[AUDIT] [29/62] Managed Disk                                -> ALLOWED                (fired: -)  [3.5s]
...
[PASS]  [62/62] Application Insights                        -> DENIED                 (fired: Deny-AppInsights-Public-Network-Access) [3.2s]
```

End of run prints a summary table and writes `validation_results.json`
with full per-service detail.

A clean run takes roughly **3–4 minutes** end-to-end (no quota
consumed, no resources created).

---

## Interpreting the result

A **clean validation** is:

```
[PASS]  Denied at deploy time, expected ref fired:    58
[PASS*] Denied at deploy time, by overlapping ref:     2
[AUDIT] Audit-only by upstream ALZ design (ok):        2
[FAIL]  Other errors / unknown:                        0
[!!!!]  Unexpected allow (regression!):                0
[MSG]   Custom non-compliance message visible in:     60/62
```

The 2 `[PASS*]` services are deduplications where two policies in the
initiative cover the same field (e.g., the built-in Storage Public
Access policy fires before the ALZ Storage Deny policy). Either way the
resource is blocked.

The 2 `[AUDIT]` entries are **not** regressions — they're documented
limitations of the upstream ALZ definitions. See the project root README
("Known limitation: audit-only effects") for details.

---

## Adding a new service

When you add a new custom policy under
`policies/custom-definitions/` and wire it into
`policies/policy_set_definition.json`, also add an entry here:

1. Open `validate_policy.py`.
2. Add a new `add(...)` call (or `SPECS.append(...)` for resources with
   parent paths like slots and Health Data Services children) using the
   same pattern as the existing 62. The arguments are:
   - **display name** — friendly label printed in the console.
   - **expected reference id** — must match
     `policyDefinitionReferenceId` in the initiative.
   - **ARM resource type + api version**.
   - **name prefix** — short lowercase prefix the script will randomise.
   - **properties** — set the field your policy checks to its
     non-compliant value.
   - **kwargs** — `sku`, `kind`, `identity`, `location`, etc.
3. Re-run the script. The new line should print `[PASS]`.

If the service isn't available in your default region, set
`location=FALLBACK_LOC` (or any literal string) on the `add(...)` call.

---

## What's in this folder

| File | Purpose |
|---|---|
| `validate_policy.py`       | Main harness — 62 service specs + runner. |
| `validation_results.json`  | (Generated) Full per-service results from the last run. |
| `README.md`                | This file. |

---

## CI integration (optional)

The script returns exit code `0` only when every service is either
denied as expected or in the audit-only allowlist. It exits `1` on any
`[FAIL]` or `[!!!!]`. Wire it into a workflow that runs after every
change to `policies/policy_set_definition.json`:

```yaml
- name: Validate policy enforcement
  shell: bash
  env:
    VAL_SUB_ID:    ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    VAL_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
    VAL_RG:        policy-validate-rg
  run: |
    az login --service-principal -u "$AZ_SP_APP_ID" -p "$AZ_SP_SECRET" --tenant "$VAL_TENANT_ID"
    python validation-testing/validate_policy.py
```
