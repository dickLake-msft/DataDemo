@description('Location for all resources')
param location string = resourceGroup().location

@description('The name of our application.  It MUST be unique.')
param name string = 'mdc-datasec-${uniqueString(resourceGroup().id)}'

@description('Admin user of the SQL Server')
param sqlAdminLogin string = 'DemoAdmin'

@description('The password of the admin user of the SQL server')
@secure()
param sqlAdminLoginPassword string

var sku = 'Free'
var skuCode = 'F1'
var workerSizeId = 0
var numberOfWorkers = 1
var linuxFxVersion = 'PYTHON|3.11'
var webAppName = 'web-app-${uniqueString(resourceGroup().id)}'
var hostingPlanName = 'asp-${name}'
var sqlServerName = 'server-${name}'
var sqlDatabaseName = 'database-${name}'
var repoUrl = 'https://github.com/dickLake-msft/DataDemo'
var branch = 'main'
var storageAccountBlobOwnerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
var contributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
var storageAccountBlobContribRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roledefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')

//TODO: ENSURE DEFENDER CSPM IS ENABLED

// Storage Account Resources
resource storageAccountForFileUploadAndVA 'Microsoft.Storage/storageAccounts@2021-02-01' = {
  name: 'storage${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties:{
    allowSharedKeyAccess:true
  }
}

resource defenderForStorageSettings 'Microsoft.Security/DefenderForStorageSettings@2022-12-01-preview' = {
  name: 'current'
  scope: storageAccountForFileUploadAndVA
  properties: {
    isEnabled: true
    malwareScanning: {
      onUpload: {
        isEnabled: true
        capGBPerMonth: 5000
      }
    }
    sensitiveDataDiscovery: {
      isEnabled: true
    }
  overrideSubscriptionLevelSettings: true
  }
}

resource storageAccountBlobService 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  name: 'default'
  parent: storageAccountForFileUploadAndVA
}

resource storageAccountBlobServiceContainer_Upload 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: 'uploadfromweb'
  parent: storageAccountBlobService
}

resource storageAccountBlobServiceContainer_VAScans 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: 'vascans'
  parent: storageAccountBlobService
}

// Main Web App Resources
resource mainWebApp 'Microsoft.Web/sites@2022-03-01' = {
  name: webAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      alwaysOn: false
    }
    hostNamesDisabled:false
    hostNameSslStates:[
      {
        hostType:'Repository'
        name:'${webAppName}.scm.azurewebsites.net'
        sslState:'Disabled'
      }
      {
        hostType:'Standard'
        name:'${webAppName}.azurewebsites.net'
      }
    ]
    serverFarmId: mainWebAppHostingPlan.id
    clientAffinityEnabled: false
  }
}

resource linkGitHubtoWebApp 'Microsoft.Web/sites/sourcecontrols@2021-01-01' = {
  parent: mainWebApp
  name: 'web'
  properties:{
    repoUrl:repoUrl
    branch:branch
    isManualIntegration:true
  }
}

resource mainWebAppHostingPlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: hostingPlanName
  location: location
  kind: 'linux'
  properties: {
    targetWorkerCount: numberOfWorkers
    targetWorkerSizeId: workerSizeId
    reserved: true
  }
  sku: {
    tier: sku
    name: skuCode
  }
}

resource webSiteConnectionStrings 'Microsoft.Web/sites/config@2020-12-01' = {
  parent: mainWebApp
  name: 'connectionstrings'
  properties: {
    DefaultConnection: {
      value: 'Driver={ODBC Driver 17 for SQLServer};Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${sqlDatabaseName},Uid=${sqlAdminLogin};Pwd=${sqlAdminLoginPassword};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;'
      type: 'SQLAzure'
    }
  }
}

resource webAppToStorageAccount 'Microsoft.Web/sites/config@2020-12-01' = {
  parent: mainWebApp
  name: 'appsettings'
  properties: {
    storage_url: storageAccountForFileUploadAndVA.properties.primaryEndpoints.blob
    storage_container: storageAccountBlobServiceContainer_Upload.name
  }
}

// Database Resources
resource sqlServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminLoginPassword
    minimalTlsVersion: '1.2'
    version: '12.0'
  }
  identity:{
    type:'SystemAssigned'
  }
}

resource sqlServerDatabase 'Microsoft.Sql/servers/databases@2021-02-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  sku:{
    name:'Basic'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 1073741824
  }
}

// //Need to test in a new environment
// resource enableSQLVA 'Microsoft.Sql/servers/vulnerabilityAssessments@2022-08-01-preview' = {
//   name: 'default'
//   parent: sqlServer
//   properties:{
//     recurringScans:{
//       emailSubscriptionAdmins:false
//       isEnabled:true
//     }
//     storageContainerPath: '${storageAccountForFileUploadAndVA.properties.primaryEndpoints.blob}${storageAccountBlobServiceContainer_VAScans.name}'
//   }
// }

resource sqlStorageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, storageAccountForFileUploadAndVA.name, storageAccountForFileUploadAndVA.id, storageAccountBlobContribRoleDefinitionId)
  properties:{
    principalId: sqlServer.identity.principalId
    roleDefinitionId: storageAccountBlobContribRoleDefinitionId
  }
}

resource allowAllWindowsAzureIps 'Microsoft.Sql/servers/firewallRules@2021-02-01-preview' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    endIpAddress: '0.0.0.0'
    startIpAddress: '0.0.0.0'
  }
}

resource enableDef4SQL 'Microsoft.Sql/servers/databases/advancedThreatProtectionSettings@2022-05-01-preview' = {
  name: 'Default'
  parent: sqlServerDatabase
  properties: {
    state: 'Enabled'
  }
}

// RBAC Resources
// Storage Blob Data Owner
resource grantStorageBlobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, mainWebApp.name, mainWebApp.id, storageAccountBlobOwnerRoleDefinitionId)
  properties: {
    principalId: mainWebApp.identity.principalId
    roleDefinitionId: storageAccountBlobOwnerRoleDefinitionId
  }
}

// Contributor???
resource grantContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name:guid(resourceGroup().id, mainWebApp.name, mainWebApp.id, contributorRoleDefinitionId)
  properties:{
    principalId:mainWebApp.identity.principalId
    roleDefinitionId: contributorRoleDefinitionId
  }
}

output URL_To_Use string = mainWebApp.properties.defaultHostName
output Storage_Account_Name string = storageAccountForFileUploadAndVA.name

