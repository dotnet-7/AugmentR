@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@minLength(1)
@description('String representing the ID of the logged-in user. Get this using ')
param myUserId string

var tags = {
  'azd-env-name': environmentName
}

// resource token for naming each resource randomly, reliably
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

//create the openai resources
module openAi './core/ai/cognitiveservices.bicep' = {
  name: 'openai'
  params: {
    name: 'openai-${resourceToken}'
    location: location
    tags: tags
    deployments:[
      {
        name: 'gpt${resourceToken}'
        sku: {
          name: 'Standard'
          capacity: 2
        }
        model: {
          format: 'OpenAI'
          name: 'gpt-35-turbo'
          version: '0301'
        }
      }
      {
        name: 'text${resourceToken}'
        sku: {
          name: 'Standard'
          capacity: 1
        }
        model: {
          format: 'OpenAI'
          name: 'text-embedding-ada-002'
          version: '2'
        }
      }
    ]
  }
}

module storage './core/storage/storage-account.bicep' = {
  name: 'storage'
  params: {
    name: 'strg${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: 'Standard_RAGRS'
    }
    kind: 'StorageV2'
    allowBlobPublicAccess: false
  }
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id${resourceToken}'
  location: location
  tags: tags
}

// system role for setting up acr pull access
var strgBlbRole = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var strgQueRole = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'

var principalId = identity.properties.principalId

// storage role for blobs
module blobRoleAssignment './core/security/role.bicep' = {
  name: guid(resourceId(subscription().subscriptionId,resourceGroup().name,'Microsoft.Storage/storageAccounts','strg${resourceToken}'), identity.id, strgBlbRole)
  params: {
    roleDefinitionId: strgBlbRole
    principalType: 'ServicePrincipal'
    principalId: principalId
  }
  dependsOn:[
    storage
  ]
}

module blobRoleAssignmentForMe './core/security/role.bicep' = {
  name: guid(resourceId(subscription().subscriptionId,resourceGroup().name,'Microsoft.Storage/storageAccounts','strg${resourceToken}'), myUserId, strgBlbRole)
  params: {
    roleDefinitionId: strgBlbRole
    principalType: 'User'
    principalId: myUserId
  }
  dependsOn:[
    storage
  ]
}

// storage role for queues
module queueRoleAssignment './core/security/role.bicep' = {
  name: guid(resourceId(subscription().subscriptionId,resourceGroup().name,'Microsoft.Storage/storageAccounts','strg${resourceToken}'), identity.id, strgQueRole)
  params: {
    roleDefinitionId: strgQueRole
    principalType: 'ServicePrincipal'
    principalId: principalId
  }
  dependsOn:[
    storage
  ]
}

module queueRoleAssignmentForMe './core/security/role.bicep' = {
  name: guid(resourceId(subscription().subscriptionId,resourceGroup().name,'Microsoft.Storage/storageAccounts','strg${resourceToken}'), myUserId, strgQueRole)
  params: {
    roleDefinitionId: strgQueRole
    principalType: 'User'
    principalId: myUserId
  }
  dependsOn:[
    storage
  ]
}

// output environment variables
output principalId string = principalId
output AZUREOPENAI_ENDPOINT string = openAi.outputs.endpoint
output AI_GPT_DEPLOYMENT_NAME string = 'gpt${resourceToken}'
output AI_TEXT_DEPLOYMENT_NAME string = 'text${resourceToken}'
output AZURE_CLIENT_ID string = identity.properties.clientId
output AZURE_BLOB_ENDPOINT string = 'https://${storage.outputs.name}.blob.core.windows.net/'
output AZURE_QUEUE_ENDPOINT string = 'https://${storage.outputs.name}.queue.core.windows.net/'
output AZURE_OPENAI_KEY string = openAi.outputs.key
