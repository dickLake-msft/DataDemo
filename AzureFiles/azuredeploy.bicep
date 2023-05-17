@description('Location for all resources')
param location string = resourceGroup().location

@description('The name of our application.  It MUST be unique.')
param name string = 'mdc-datasec-${uniqueString(resourceGroup().id)}'

@description('Admin user of the SQL Server')
param sqlAdminLogin string = 'DemoAdmin'

@description('The password of the admin user of the SQL server')
@secure()
param sqlAdminLoginPassword string

var alwaysOn = false
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

//TODO: ENSURE DEFENDER CSPM IS ENABLED

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-02-01' = {
  name: 'storage${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
}

resource defenderForStorageSettings 'Microsoft.Security/DefenderForStorageSettings@2022-12-01-preview' = {
  name: 'current'
  scope: storageAccount
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
  parent: storageAccount
}

resource storageAccountBlobServiceContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: 'uploadfromweb'
  parent: storageAccountBlobService
}

resource webApp 'Microsoft.Web/sites@2022-03-01' = {
  name: webAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      alwaysOn: alwaysOn
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
    serverFarmId: hostingPlan.id
    clientAffinityEnabled: false
  }
}

resource srcControls 'Microsoft.Web/sites/sourcecontrols@2021-01-01' = {
  parent: webApp
  name: 'web'
  properties:{
    repoUrl:repoUrl
    branch:branch
    isManualIntegration:true
  }
}

resource hostingPlan 'Microsoft.Web/serverfarms@2022-03-01' = {
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

//TODO: Need to figure out VA
resource sqlServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminLoginPassword
    minimalTlsVersion: '1.2'
    version: '12.0'
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

resource webSiteConnectionStrings 'Microsoft.Web/sites/config@2020-12-01' = {
  parent: webApp
  name: 'connectionstrings'
  properties: {
    DefaultConnection: {
      value: 'Data Source=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${sqlDatabaseName};User Id=${sqlAdminLogin}@${sqlServer.properties.fullyQualifiedDomainName};Password=${sqlAdminLoginPassword};'
      type: 'SQLAzure'
    }
  }
}

// Storage Blob Data Owner
resource roleAssignment2 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, webApp.name, webApp.id, storageAccountBlobOwnerRoleDefinitionId)
  properties: {
    principalId: webApp.identity.principalId
    roleDefinitionId: storageAccountBlobOwnerRoleDefinitionId
  }
}

// Contributor???
resource roleAssignment3 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name:guid(resourceGroup().id, webApp.name, webApp.id, contributorRoleDefinitionId)
  properties:{
    principalId:webApp.identity.principalId
    roleDefinitionId: contributorRoleDefinitionId
  }
}

output URL_To_Use string = webApp.properties.defaultHostName
output Storage_Account_Name string = storageAccount.name

