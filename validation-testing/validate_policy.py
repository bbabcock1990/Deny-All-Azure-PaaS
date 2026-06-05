"""
Validate the Deny-PublicPaaSEndpoints initiative end-to-end.

For each of the 62 services in the initiative, write a minimal ARM template
that attempts to create the resource with public network access ENABLED,
then run `az deployment group validate` and parse the result.

A PASS for a given service means the policy fired
`RequestDisallowedByPolicy` with the expected reference id, and the
non-compliance message you configured at assignment time was returned.

Required environment variables
------------------------------
  VAL_SUB_ID            Subscription that owns the target resource group.
  VAL_TENANT_ID         AAD tenant (used in templates that need it, e.g. Key Vault, Managed HSM).
  VAL_RG                Resource group used to evaluate templates (must exist).
  VAL_LOC               Region for most templates (default: centralus).
  VAL_FALLBACK_LOC      Region used for services not available in VAL_LOC (default: eastus).
                        Currently: Purview, all Healthcare APIs / Health Data Services,
                        and Digital Twins.
  VAL_EXPECTED_MSG      Custom non-compliance message you set on the assignment
                        (default: "Private Endpoints Must Be Enabled - No Public Access").

The target RG must already exist, must be in a subscription that inherits the
assignment, and the caller must have at least "Reader" + "Microsoft.Resources/
deployments/validate/action" on the RG.

Output
------
  - Console: one line per service with PASS / AUDIT_ONLY / FAIL.
  - validation_results.json: structured per-service result.

Audit-only services
-------------------
Two services in the initiative cannot be set to "Deny" because their
upstream ALZ definition's effect parameter excludes Deny from
allowedValues. These are expected to validate as ALLOWED with no policy
deny:
  - API Management (ApiManPublicIpDenyEffect: AuditIfNotExists/Disabled)
  - Managed Disks  (managedDiskPublicNetworkAccess: Audit/Disabled)
"""
import json
import os
import random
import re
import string
import subprocess
import sys
import tempfile
import time


def _required(name):
    v = os.environ.get(name)
    if not v:
        sys.stderr.write(f"ERROR: required env var {name} is not set.\n")
        sys.stderr.write("       See module docstring for the full list.\n")
        sys.exit(2)
    return v


SUB_ID = _required("VAL_SUB_ID")
TENANT_ID = _required("VAL_TENANT_ID")
RG = _required("VAL_RG")
LOC = os.environ.get("VAL_LOC", "centralus")
FALLBACK_LOC = os.environ.get("VAL_FALLBACK_LOC", "eastus")
EXPECTED_MSG = os.environ.get(
    "VAL_EXPECTED_MSG",
    "Private Endpoints Must Be Enabled - No Public Access",
)


def rname(prefix, length=8):
    return prefix + "".join(random.choices(string.ascii_lowercase + string.digits, k=length))


def tmpl(resources):
    return {
        "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
        "contentVersion": "1.0.0.0",
        "resources": resources,
    }


# (display_name, expected_ref_id, template_dict)
SPECS = []


def res(rtype, api, name_prefix, properties, location=None, **kwargs):
    if location is None:
        location = LOC
    r = {"type": rtype, "apiVersion": api, "name": rname(name_prefix), "location": location, "properties": properties}
    r.update(kwargs)
    return r


def add(display, ref, rtype, api, name_prefix, properties, **kwargs):
    SPECS.append((display, ref, tmpl([res(rtype, api, name_prefix, properties, **kwargs)])))


# ----- 62 service specs -----

# 1. Cosmos DB
add("Cosmos DB", "CosmosDenyPaasPublicIP",
    "Microsoft.DocumentDB/databaseAccounts", "2023-04-15", "cosval",
    {
        "publicNetworkAccess": "Enabled",
        "databaseAccountOfferType": "Standard",
        "locations": [{"locationName": LOC, "failoverPriority": 0}],
    })

# 2. Key Vault
add("Key Vault", "KeyVaultDenyPaasPublicIP",
    "Microsoft.KeyVault/vaults", "2023-07-01", "kvval",
    {
        "publicNetworkAccess": "Enabled",
        "tenantId": TENANT_ID,
        "sku": {"family": "A", "name": "standard"},
        "accessPolicies": [],
    })

# 3. SQL Server
add("SQL Server", "SqlServerDenyPaasPublicIP",
    "Microsoft.Sql/servers", "2023-05-01-preview", "sqlval",
    {
        "publicNetworkAccess": "Enabled",
        "administratorLogin": "sqladmin",
        "administratorLoginPassword": "P@ssw0rd!Validate123",
        "version": "12.0",
    })

# 4. Storage Account
add("Storage Account", "StorageDenyPaasPublicIP",
    "Microsoft.Storage/storageAccounts", "2023-01-01", "stval",
    {"publicNetworkAccess": "Enabled", "minimumTlsVersion": "TLS1_2"},
    sku={"name": "Standard_LRS"}, kind="StorageV2")

# 5. AKS
add("AKS (Private Cluster)", "AKSDenyPaasPublicIP",
    "Microsoft.ContainerService/managedClusters", "2023-10-01", "aksval",
    {
        "dnsPrefix": "aksval",
        "agentPoolProfiles": [{
            "name": "agentpool",
            "count": 1,
            "vmSize": "Standard_DS2_v2",
            "osType": "Linux",
            "mode": "System",
        }],
        "apiServerAccessProfile": {"enablePrivateCluster": False},
    },
    identity={"type": "SystemAssigned"})

# 6. ACR
add("Container Registry", "ACRDenyPaasPublicIP",
    "Microsoft.ContainerRegistry/registries", "2023-07-01", "acrval",
    {"publicNetworkAccess": "Enabled"},
    sku={"name": "Premium"})

# 7. Azure File Sync
add("Storage Sync Service", "AFSDenyPaasPublicIP",
    "Microsoft.StorageSync/storageSyncServices", "2022-09-01", "afsval",
    {"incomingTrafficPolicy": "AllowAllTraffic"})

# 8. PostgreSQL Flexible Server
add("PostgreSQL Flexible Server", "PostgreSQLFlexDenyPublicIP",
    "Microsoft.DBforPostgreSQL/flexibleServers", "2023-06-01-preview", "pgflex",
    {
        "administratorLogin": "pgadmin",
        "administratorLoginPassword": "P@ssw0rd!Validate123",
        "network": {"publicNetworkAccess": "Enabled"},
        "version": "15",
        "storage": {"storageSizeGB": 32},
    },
    sku={"name": "Standard_B1ms", "tier": "Burstable"})

# 9. PostgreSQL Single Server
add("PostgreSQL Single Server", "Deny-PostgreSql-Public-Network-Access",
    "Microsoft.DBforPostgreSQL/servers", "2017-12-01", "pgsing",
    {
        "version": "11",
        "administratorLogin": "pgadmin",
        "administratorLoginPassword": "P@ssw0rd!Validate123",
        "publicNetworkAccess": "Enabled",
        "sslEnforcement": "Enabled",
    },
    sku={"name": "B_Gen5_1", "tier": "Basic", "family": "Gen5", "capacity": 1})

# 10. MySQL Flexible Server
add("MySQL Flexible Server", "MySQLFlexDenyPublicIP",
    "Microsoft.DBforMySQL/flexibleServers", "2023-06-30", "myflex",
    {
        "administratorLogin": "myadmin",
        "administratorLoginPassword": "P@ssw0rd!Validate123",
        "network": {"publicNetworkAccess": "Enabled"},
        "version": "8.0.21",
        "storage": {"storageSizeGB": 20},
    },
    sku={"name": "Standard_B1s", "tier": "Burstable"})

# 11. Batch Account
add("Batch Account", "BatchDenyPublicIP",
    "Microsoft.Batch/batchAccounts", "2023-05-01", "batval",
    {"publicNetworkAccess": "Enabled", "poolAllocationMode": "BatchService"})

# 12. MariaDB
add("MariaDB Single Server", "MariaDbDenyPublicIP",
    "Microsoft.DBforMariaDB/servers", "2018-06-01", "mariaval",
    {
        "version": "10.3",
        "administratorLogin": "mariaadmin",
        "administratorLoginPassword": "P@ssw0rd!Validate123",
        "publicNetworkAccess": "Enabled",
        "sslEnforcement": "Enabled",
    },
    sku={"name": "B_Gen5_1", "tier": "Basic", "family": "Gen5", "capacity": 1})

# 13. Machine Learning Workspace
add("ML Workspace", "MlDenyPublicIP",
    "Microsoft.MachineLearningServices/workspaces", "2023-10-01", "mlval",
    {
        "publicNetworkAccess": "Enabled",
        "friendlyName": "ml-val",
        "storageAccount": f"/subscriptions/{SUB_ID}/resourceGroups/{RG}/providers/Microsoft.Storage/storageAccounts/mlvalstg",
        "keyVault": f"/subscriptions/{SUB_ID}/resourceGroups/{RG}/providers/Microsoft.KeyVault/vaults/mlvalkv",
        "applicationInsights": f"/subscriptions/{SUB_ID}/resourceGroups/{RG}/providers/Microsoft.Insights/components/mlvalai",
    },
    identity={"type": "SystemAssigned"})

# 14. Redis
add("Redis Cache", "RedisCacheDenyPublicIP",
    "Microsoft.Cache/Redis", "2023-08-01", "redval",
    {
        "publicNetworkAccess": "Enabled",
        "sku": {"name": "Basic", "family": "C", "capacity": 0},
    })

# 15. Bot Service
add("Bot Service", "BotServiceDenyPublicIP",
    "Microsoft.BotService/botServices", "2022-09-15", "botval",
    {
        "publicNetworkAccess": "Enabled",
        "displayName": "botval",
        "msaAppId": "00000000-0000-0000-0000-000000000001",
    },
    sku={"name": "F0"}, kind="bot", location="global")

# 16. Automation Account
add("Automation Account", "AutomationDenyPublicIP",
    "Microsoft.Automation/automationAccounts", "2022-08-08", "autoval",
    {"publicNetworkAccess": True, "sku": {"name": "Basic"}})

# 17. App Configuration
add("App Configuration", "AppConfigDenyPublicIP",
    "Microsoft.AppConfiguration/configurationStores", "2023-03-01", "appcval",
    {"publicNetworkAccess": "Enabled"},
    sku={"name": "Standard"})

# 18. Function App
add("Function App", "FunctionDenyPublicIP",
    "Microsoft.Web/sites", "2022-09-01", "funcval",
    {
        "publicNetworkAccess": "Enabled",
        "serverFarmId": f"/subscriptions/{SUB_ID}/resourceGroups/{RG}/providers/Microsoft.Web/serverfarms/funcval-plan",
    },
    kind="functionapp")

# 19. Function App Slot
fa_parent_name = rname("fapar")
SPECS.append((
    "Function App Slot", "FunctionAppSlotsDenyPublicIP",
    tmpl([{
        "type": "Microsoft.Web/sites/slots",
        "apiVersion": "2022-09-01",
        "name": f"{fa_parent_name}/slot1",
        "location": LOC,
        "kind": "functionapp",
        "properties": {
            "publicNetworkAccess": "Enabled",
            "serverFarmId": f"/subscriptions/{SUB_ID}/resourceGroups/{RG}/providers/Microsoft.Web/serverfarms/{fa_parent_name}-plan",
        },
    }])
))

# 20. App Service Environment v3
add("App Service Environment v3", "AseDenyPublicIP",
    "Microsoft.Web/hostingEnvironments", "2022-09-01", "aseval",
    {
        "internalLoadBalancingMode": "None",
        "virtualNetwork": {
            "id": f"/subscriptions/{SUB_ID}/resourceGroups/{RG}/providers/Microsoft.Network/virtualNetworks/asevnet/subnets/asesubnet",
        },
    },
    kind="ASEV3")

# 21. App Service (Web App)
add("App Service (Web App)", "AsDenyPublicIP",
    "Microsoft.Web/sites", "2022-09-01", "appsval",
    {
        "publicNetworkAccess": "Enabled",
        "serverFarmId": f"/subscriptions/{SUB_ID}/resourceGroups/{RG}/providers/Microsoft.Web/serverfarms/appsval-plan",
    },
    kind="app")

# 22. API Management (AUDIT-ONLY by upstream design)
add("API Management", "ApiManDenyPublicIP",
    "Microsoft.ApiManagement/service", "2023-05-01-preview", "apimval",
    {
        "publisherEmail": "admin@example.com",
        "publisherName": "Validator",
        "publicNetworkAccess": "Enabled",
    },
    sku={"name": "Developer", "capacity": 1})

# 23. Container Apps Environment
add("Container Apps Environment", "ContainerAppsEnvironmentDenyPublicIP",
    "Microsoft.App/managedEnvironments", "2023-05-01", "caeval",
    {
        "vnetConfiguration": {"internal": False},
        "publicNetworkAccess": "Enabled",
    })

# 24. Container App
add("Container App", "Deny-ContainerApps-Public-Network-Access",
    "Microsoft.App/containerApps", "2023-05-01", "caval",
    {
        "managedEnvironmentId": f"/subscriptions/{SUB_ID}/resourceGroups/{RG}/providers/Microsoft.App/managedEnvironments/caval-env",
        "configuration": {"ingress": {"external": True, "targetPort": 80}},
        "template": {"containers": [{"image": "nginx", "name": "nginx"}]},
    })

# 25. ASR (Recovery Services Vault)
add("Recovery Services Vault", "AsrVaultDenyPublicIP",
    "Microsoft.RecoveryServices/vaults", "2023-06-01", "rsvval",
    {"publicNetworkAccess": "Enabled"},
    sku={"name": "Standard"})

# 26. Logic App Standard (Microsoft.Web/sites with kind=workflowapp).
# NOTE: The custom ALZ policy targets Logic Apps *Standard* (which is App
# Service under the hood). Consumption Logic Apps (Microsoft.Logic/workflows)
# do not have a publicNetworkAccess field and are not covered.
add("Logic App (Standard)", "Deny-LogicApp-Public-Network-Access",
    "Microsoft.Web/sites", "2022-09-01", "logicstd",
    {
        "publicNetworkAccess": "Enabled",
        "serverFarmId": f"/subscriptions/{SUB_ID}/resourceGroups/{RG}/providers/Microsoft.Web/serverfarms/logicstd-plan",
    },
    kind="functionapp,workflowapp")

# 27. App Service Slot
as_parent_name = rname("appspar")
SPECS.append((
    "App Service Slot", "Deny-AppSlots-Public",
    tmpl([{
        "type": "Microsoft.Web/sites/slots",
        "apiVersion": "2022-09-01",
        "name": f"{as_parent_name}/slot1",
        "location": LOC,
        "kind": "app",
        "properties": {
            "publicNetworkAccess": "Enabled",
            "serverFarmId": f"/subscriptions/{SUB_ID}/resourceGroups/{RG}/providers/Microsoft.Web/serverfarms/{as_parent_name}-plan",
        },
    }])
))

# 28. Cognitive Search
add("Cognitive Search", "Deny-CognitiveSearch-PublicEndpoint",
    "Microsoft.Search/searchServices", "2023-11-01", "srchval",
    {"publicNetworkAccess": "enabled"},
    sku={"name": "basic"})

# 29. Managed Disk (AUDIT-ONLY by upstream design).
# The policy checks both networkAccessPolicy and publicNetworkAccess.
add("Managed Disk", "Deny-ManagedDisk-Public-Network-Access",
    "Microsoft.Compute/disks", "2023-10-02", "diskval",
    {
        "networkAccessPolicy": "AllowAll",
        "publicNetworkAccess": "Enabled",
        "diskSizeGB": 32,
        "creationData": {"createOption": "Empty"},
    },
    sku={"name": "Standard_LRS"})

# 30. Azure Data Explorer (Kusto)
add("Data Explorer (Kusto)", "Deny-ADX-Public-Network-Access",
    "Microsoft.Kusto/Clusters", "2023-08-15", "adxval",
    {"publicNetworkAccess": "Enabled"},
    sku={"name": "Dev(No SLA)_Standard_E2a_v4", "tier": "Basic", "capacity": 1})

# 31. Data Factory
add("Data Factory", "Deny-Adf-Public-Network-Access",
    "Microsoft.DataFactory/factories", "2018-06-01", "adfval",
    {"publicNetworkAccess": "Enabled"})

# 32. Event Grid Domain
add("Event Grid Domain", "Deny-EventGrid-Public-Network-Access",
    "Microsoft.EventGrid/domains", "2023-12-15-preview", "egdval",
    {"publicNetworkAccess": "Enabled"})

# 33. Event Grid Topic
add("Event Grid Topic", "Deny-EventGrid-Topic-Public-Network-Access",
    "Microsoft.EventGrid/topics", "2023-12-15-preview", "egtval",
    {"publicNetworkAccess": "Enabled"})

# 34. Event Hub Namespace
add("Event Hub Namespace", "Deny-EH-Public-Network-Access",
    "Microsoft.EventHub/namespaces", "2024-01-01", "ehval",
    {"publicNetworkAccess": "Enabled"},
    sku={"name": "Standard", "tier": "Standard"})

# 35. Managed HSM
add("Managed HSM", "Deny-KV-Hms-PublicNetwork",
    "Microsoft.KeyVault/managedHSMs", "2023-07-01", "hsmval",
    {
        "publicNetworkAccess": "Enabled",
        "tenantId": TENANT_ID,
        "initialAdminObjectIds": ["00000000-0000-0000-0000-000000000001"],
    },
    sku={"family": "B", "name": "Standard_B1"})

# 36. MySQL Single Server
add("MySQL Single Server", "Deny-MySql-Public-Network-Access",
    "Microsoft.DBforMySQL/servers", "2017-12-01", "myssing",
    {
        "version": "8.0",
        "administratorLogin": "myadmin",
        "administratorLoginPassword": "P@ssw0rd!Validate123",
        "publicNetworkAccess": "Enabled",
        "sslEnforcement": "Enabled",
    },
    sku={"name": "B_Gen5_1", "tier": "Basic", "family": "Gen5", "capacity": 1})

# 37. Cognitive Services (publicNetworkAccess)
add("Cognitive Services (publicNetworkAccess)", "Deny-Cognitive-Services-Public-Network-Access",
    "Microsoft.CognitiveServices/accounts", "2023-10-01-preview", "csval",
    {"publicNetworkAccess": "Enabled"},
    sku={"name": "S0"}, kind="TextAnalytics")

# 38. Cognitive Services (networkAcls defaultAction)
add("Cognitive Services (networkAcls)", "Deny-Cognitive-Services-Network-Access",
    "Microsoft.CognitiveServices/accounts", "2023-10-01-preview", "cs2val",
    {"networkAcls": {"defaultAction": "Allow"}},
    sku={"name": "S0"}, kind="TextAnalytics")

# 39. Service Bus
add("Service Bus Namespace", "Deny-Sb-PublicEndpoint",
    "Microsoft.ServiceBus/namespaces", "2022-10-01-preview", "sbval",
    {"publicNetworkAccess": "Enabled"},
    sku={"name": "Premium", "tier": "Premium", "capacity": 1})

# 40. SQL Managed Instance
add("SQL Managed Instance", "Deny-Sql-Managed-Public-Endpoint",
    "Microsoft.Sql/managedInstances", "2023-05-01-preview", "smival",
    {
        "publicDataEndpointEnabled": True,
        "administratorLogin": "smiadmin",
        "administratorLoginPassword": "P@ssw0rd!Validate123",
        "subnetId": f"/subscriptions/{SUB_ID}/resourceGroups/{RG}/providers/Microsoft.Network/virtualNetworks/smivnet/subnets/smisubnet",
        "storageSizeInGB": 32,
        "vCores": 8,
        "licenseType": "LicenseIncluded",
    },
    sku={"name": "GP_Gen5", "tier": "GeneralPurpose"})

# 41. Storage (Blob public access)
add("Storage Account (Blob public access)", "Deny-Storage-Public-Access",
    "Microsoft.Storage/storageAccounts", "2023-01-01", "stbval",
    {"allowBlobPublicAccess": True, "minimumTlsVersion": "TLS1_2"},
    sku={"name": "Standard_LRS"}, kind="StorageV2")

# 42. Synapse
add("Synapse Workspace", "Deny-Synapse-Public-Network-Access",
    "Microsoft.Synapse/workspaces", "2021-06-01", "synval",
    {
        "publicNetworkAccess": "Enabled",
        "defaultDataLakeStorage": {
            "accountUrl": "https://synvaldls.dfs.core.windows.net",
            "filesystem": "default",
        },
        "sqlAdministratorLogin": "synadmin",
        "sqlAdministratorLoginPassword": "P@ssw0rd!Validate123",
    })

# 43. Log Analytics Workspace (built-in id)
add("Log Analytics Workspace (built-in)", "Deny-Workspace-PublicNetworkAccess",
    "Microsoft.OperationalInsights/workspaces", "2022-10-01", "lawval",
    {
        "publicNetworkAccessForIngestion": "Enabled",
        "publicNetworkAccessForQuery": "Enabled",
        "sku": {"name": "PerGB2018"},
    })

# 44. AVD Host Pool
add("AVD Host Pool", "Deny-Hostpool-PublicNetworkAccess",
    "Microsoft.DesktopVirtualization/hostPools", "2023-09-05", "hpval",
    {
        "publicNetworkAccess": "Enabled",
        "hostPoolType": "Pooled",
        "loadBalancerType": "BreadthFirst",
        "preferredAppGroupType": "Desktop",
    })

# 45. Azure Managed Grafana
add("Azure Managed Grafana", "Deny-Grafana-PublicNetworkAccess",
    "Microsoft.Dashboard/grafana", "2023-09-01", "grafval",
    {"publicNetworkAccess": "Enabled"},
    sku={"name": "Standard"})

# 46. SignalR
add("SignalR", "Deny-SignalR-Public-Network-Access",
    "Microsoft.SignalRService/SignalR", "2023-02-01", "sgval",
    {"publicNetworkAccess": "Enabled"},
    sku={"name": "Standard_S1", "tier": "Standard", "capacity": 1})

# 47. Web PubSub
add("Web PubSub", "Deny-WebPubSub-Public-Network-Access",
    "Microsoft.SignalRService/webPubSub", "2023-02-01", "wpsval",
    {"publicNetworkAccess": "Enabled"},
    sku={"name": "Standard_S1", "tier": "Standard", "capacity": 1})

# 48. IoT Hub
add("IoT Hub", "Deny-IoTHub-Public-Network-Access",
    "Microsoft.Devices/IotHubs", "2023-06-30", "iothval",
    {"publicNetworkAccess": "Enabled"},
    sku={"name": "S1", "capacity": 1})

# 49. IoT DPS
add("IoT Device Provisioning Service", "Deny-IoTDps-Public-Network-Access",
    "Microsoft.Devices/provisioningServices", "2023-03-01-preview", "dpsval",
    {"publicNetworkAccess": "Enabled"},
    sku={"name": "S1", "capacity": 1})

# 50. Purview (uses FALLBACK_LOC — not available in centralus)
add("Purview Account", "Deny-Purview-Public-Network-Access",
    "Microsoft.Purview/accounts", "2021-12-01", "pvval",
    {"publicNetworkAccess": "Enabled"},
    location=FALLBACK_LOC,
    sku={"name": "Standard", "capacity": 1},
    identity={"type": "SystemAssigned"})

# 51. Healthcare APIs (Services) — uses FALLBACK_LOC
add("Healthcare APIs (Services)", "Deny-HealthcareApis-Services-Public-Network-Access",
    "Microsoft.HealthcareApis/services", "2024-03-31", "hcaval",
    {"publicNetworkAccess": "Enabled", "accessPolicies": []},
    location=FALLBACK_LOC, kind="fhir-R4")

# 52. Health Data Services Workspace — uses FALLBACK_LOC
add("Health Data Services Workspace", "Deny-HealthDataServices-Workspace-Public-Network-Access",
    "Microsoft.HealthcareApis/workspaces", "2024-03-31", "hdswks",
    {"publicNetworkAccess": "Enabled"},
    location=FALLBACK_LOC)

# 53. HDS FHIR — uses FALLBACK_LOC
hds_ws = rname("hdsws")
SPECS.append((
    "Health Data Services FHIR", "Deny-HealthDataServices-FHIR-Public-Network-Access",
    tmpl([{
        "type": "Microsoft.HealthcareApis/workspaces/fhirservices",
        "apiVersion": "2024-03-31",
        "name": f"{hds_ws}/fhirval",
        "location": FALLBACK_LOC,
        "kind": "fhir-R4",
        "properties": {
            "publicNetworkAccess": "Enabled",
            "authenticationConfiguration": {
                "audience": f"https://{hds_ws}-fhirval.fhir.azurehealthcareapis.com"
            },
        },
    }])
))

# 54. HDS DICOM — uses FALLBACK_LOC
hds_ws2 = rname("hdsws")
SPECS.append((
    "Health Data Services DICOM", "Deny-HealthDataServices-DICOM-Public-Network-Access",
    tmpl([{
        "type": "Microsoft.HealthcareApis/workspaces/dicomservices",
        "apiVersion": "2024-03-31",
        "name": f"{hds_ws2}/dicomval",
        "location": FALLBACK_LOC,
        "properties": {"publicNetworkAccess": "Enabled"},
    }])
))

# 55. Static Web Apps
add("Static Web App", "Deny-StaticWebApps-Public-Network-Access",
    "Microsoft.Web/staticSites", "2022-09-01", "swaval",
    {"publicNetworkAccess": "Enabled"},
    sku={"name": "Standard", "tier": "Standard"})

# 56. Relay
add("Relay Namespace", "Deny-Relay-Public-Network-Access",
    "Microsoft.Relay/namespaces", "2021-11-01", "rlyval",
    {"publicNetworkAccess": "Enabled"},
    sku={"name": "Standard", "tier": "Standard"})

# 57. HDInsight
add("HDInsight Cluster", "Deny-HDInsight-Public-Network-Access",
    "Microsoft.HDInsight/clusters", "2023-04-15-preview", "hdival",
    {
        "clusterVersion": "5.0",
        "osType": "Linux",
        "tier": "Standard",
        "clusterDefinition": {
            "kind": "HADOOP",
            "configurations": {
                "gateway": {
                    "restAuthCredential.isEnabled": "true",
                    "restAuthCredential.username": "admin",
                    "restAuthCredential.password": "P@ssw0rd!Validate123",
                }
            },
        },
        "computeProfile": {"roles": []},
        "networkProperties": {
            "resourceProviderConnection": "Outbound",
            "publicNetworkAccess": "PublicLoadBalancer",
        },
    })

# 58. Communication Services
add("Communication Services", "Deny-CommunicationServices-Public-Network-Access",
    "Microsoft.Communication/communicationServices", "2023-04-01", "cmsval",
    {"publicNetworkAccess": "Enabled", "dataLocation": "United States"},
    location="global")

# 59. Digital Twins — uses FALLBACK_LOC
add("Digital Twins Instance", "Deny-DigitalTwins-Public-Network-Access",
    "Microsoft.DigitalTwins/digitalTwinsInstances", "2023-01-31", "dtval",
    {"publicNetworkAccess": "Enabled"},
    location=FALLBACK_LOC)

# 60. Video Indexer
add("Video Indexer Account", "Deny-VideoIndexer-Public-Network-Access",
    "Microsoft.VideoIndexer/accounts", "2024-01-01", "viaval",
    {
        "publicNetworkAccess": "Enabled",
        "storageServices": {
            "resourceId": f"/subscriptions/{SUB_ID}/resourceGroups/{RG}/providers/Microsoft.Storage/storageAccounts/viastg",
        },
        "accountName": rname("vi"),
    },
    identity={"type": "SystemAssigned"})

# 61. Log Analytics Workspace (supplemental id)
add("Log Analytics Workspace (supplemental)", "Deny-LogAnalytics-Public-Network-Access",
    "Microsoft.OperationalInsights/workspaces", "2022-10-01", "lawsval",
    {
        "publicNetworkAccessForIngestion": "Enabled",
        "publicNetworkAccessForQuery": "Enabled",
        "sku": {"name": "PerGB2018"},
    })

# 62. Application Insights
add("Application Insights", "Deny-AppInsights-Public-Network-Access",
    "Microsoft.Insights/components", "2020-02-02", "aival",
    {
        "Application_Type": "web",
        "publicNetworkAccessForIngestion": "Enabled",
        "publicNetworkAccessForQuery": "Enabled",
        "WorkspaceResourceId": f"/subscriptions/{SUB_ID}/resourceGroups/{RG}/providers/Microsoft.OperationalInsights/workspaces/aivalwks",
    },
    kind="web")


# Two services in the upstream ALZ initiative cannot be set to Deny:
# their allowedValues exclude "Deny". We mark these so the report shows
# them as expected-audit-only rather than a regression.
AUDIT_ONLY_REFS = {
    "ApiManDenyPublicIP",
    "Deny-ManagedDisk-Public-Network-Access",
}


# ----- Runner -----

def run_validate(template_dict, timeout=120):
    fd, path = tempfile.mkstemp(suffix=".json", prefix="polval_")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(template_dict, f)
        proc = subprocess.run(
            ["az", "deployment", "group", "validate",
             "--resource-group", RG,
             "--template-file", path,
             "--output", "json"],
            capture_output=True, text=True, timeout=timeout, shell=True,
        )
        return proc.stdout, proc.stderr, proc.returncode
    except subprocess.TimeoutExpired:
        return "", "TIMEOUT", -1
    finally:
        try:
            os.unlink(path)
        except Exception:
            pass


def classify(out, err, expected_ref):
    full = (out or "") + "\n" + (err or "")
    if "RequestDisallowedByPolicy" in full:
        msg_present = EXPECTED_MSG in full
        refs = re.findall(r'"policyDefinitionReferenceId":\s*"([^"]+)"', full)
        if expected_ref in refs:
            return ("DENIED", refs, msg_present)
        return ("DENIED_BY_OVERLAP", refs, msg_present)
    if "TIMEOUT" in (err or ""):
        return ("TIMEOUT", [], False)
    m = re.search(r'"code":\s*"([^"]+)".*?"message":\s*"([^"]{0,200})', full, re.DOTALL)
    if m and m.group(1) != "DeploymentValidationSucceeded":
        return (f"OTHER_ERROR:{m.group(1)}", [], False)
    if '"validationLevel"' in (out or "") or '"properties"' in (out or ""):
        return ("ALLOWED", [], False)
    return ("UNKNOWN", [], False)


def verdict_flag(ref, verdict):
    if ref in AUDIT_ONLY_REFS:
        return "[AUDIT]" if verdict == "ALLOWED" else "[!!!!]"
    if verdict == "DENIED":
        return "[PASS]"
    if verdict == "DENIED_BY_OVERLAP":
        return "[PASS*]"
    return "[FAIL]"


def main():
    print(f"Validating {len(SPECS)} services against the Deny-PublicPaaSEndpoints initiative...")
    print(f"  Target RG     : {RG}")
    print(f"  Subscription  : {SUB_ID}")
    print(f"  Default region: {LOC}")
    print(f"  Fallback      : {FALLBACK_LOC}")
    print(f"  Expected msg  : {EXPECTED_MSG!r}\n")

    results = []
    for i, (display, ref, t) in enumerate(SPECS, 1):
        t0 = time.time()
        out, err, rc = run_validate(t)
        verdict, fired_refs, msg_present = classify(out, err, ref)
        elapsed = time.time() - t0
        flag = verdict_flag(ref, verdict)
        results.append({
            "n": i,
            "service": display,
            "expected_ref": ref,
            "verdict": verdict,
            "fired_refs": fired_refs,
            "custom_message_present": msg_present,
            "elapsed_s": round(elapsed, 1),
            "audit_only_by_design": ref in AUDIT_ONLY_REFS,
        })
        print(
            f"{flag:7} [{i:2}/{len(SPECS):2}] {display:42} -> {verdict:22} "
            f"(fired: {','.join(fired_refs) if fired_refs else '-'}) [{elapsed:.1f}s]",
            flush=True,
        )

    # Tallies
    n_pass     = sum(1 for r in results if r["verdict"] == "DENIED")
    n_overlap  = sum(1 for r in results if r["verdict"] == "DENIED_BY_OVERLAP")
    n_audit    = sum(1 for r in results if r["audit_only_by_design"] and r["verdict"] == "ALLOWED")
    n_audit_un = sum(1 for r in results if r["audit_only_by_design"] and r["verdict"] != "ALLOWED")
    n_allowed  = sum(1 for r in results if (not r["audit_only_by_design"]) and r["verdict"] == "ALLOWED")
    n_other    = len(results) - n_pass - n_overlap - n_audit - n_audit_un - n_allowed
    msg_count  = sum(1 for r in results if r["custom_message_present"])

    print("\n" + "=" * 100)
    print("SUMMARY")
    print("=" * 100)
    print(f"[PASS]  Denied at deploy time, expected ref fired:    {n_pass:2}")
    print(f"[PASS*] Denied at deploy time, by overlapping ref:    {n_overlap:2}")
    print(f"[AUDIT] Audit-only by upstream ALZ design (ok):       {n_audit:2}")
    print(f"[FAIL]  Other errors / unknown:                       {n_other:2}")
    print(f"[!!!!]  Unexpected allow (regression!):               {n_allowed:2}")
    print(f"[MSG]   Custom non-compliance message visible in:     {msg_count}/{len(results)}")

    out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "validation_results.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    print(f"\nFull JSON results written to: {out_path}")

    # Non-zero exit when there are regressions
    if n_allowed > 0 or n_other > 0 or n_audit_un > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
