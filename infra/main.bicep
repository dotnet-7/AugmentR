targetScope = 'subscription'

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

@description('Defines if only the dependencies (OpenAI and Storage) are created, or if the container apps are also created.')
param createContainerApps bool = false

@description('Name of the openai key secret in the keyvault')
param secretName string = 'openai-key'

// resource token for naming each resource randomly, reliably
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

// Tags that should be applied to all resources.
var tags = {
  'azd-env-name': environmentName
}

// the openai deployments to create
var openaiDeployment = [
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
      capacity: 5
    }
    model: {
      format: 'OpenAI'
      name: 'text-embedding-ada-002'
      version: '2'
    }
  }
]

// the containing resource group
resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

// create the openai resources
module openAi './core/ai/cognitiveservices.bicep' = {
  name: 'openai'
  scope: rg
  params: {
    name: 'openai-${resourceToken}'
    location: location
    tags: tags
    deployments: openaiDeployment
  }
}

// create the storage resources
module storage './app/storage.bicep' = {
  name: 'app${resourceToken}'
  scope: rg
  params: {
    location: location
    keyvaultName: keyvault.outputs.name
    secretName: secretName
    environmentName: environmentName
    myUserId: myUserId
  }
  dependsOn:[
    openAi
  ]
}

// create a keyvault to store openai secrets
module keyvault './core/security/keyvault.bicep' = {
  name: 'keyvault'
  scope: rg
  params: {
    name: 'kv-${resourceToken}'
    location: location
    tags: tags
    principalId: myUserId
  }
}

// create the container apps environment if requested
module containers './app/containers.bicep' = if(createContainerApps) {
  name: 'aca${resourceToken}'
  scope: rg
  params: {
    location: location
    environmentName: environmentName
    principalId: storage.outputs.principalId
  }
}

// output environment variables
output KEYVAULT_ENDPOINT string = keyvault.outputs.endpoint
output AZURE_CLIENT_ID string = storage.outputs.AZURE_CLIENT_ID
output AZUREOPENAI_SECRET_NAME string = secretName
output AZUREOPENAI_ENDPOINT string = openAi.outputs.endpoint
output AZUREOPENAI_GPT_NAME string = storage.outputs.AI_GPT_DEPLOYMENT_NAME
output AZUREOPENAI_TEXT_EMBEDDING_NAME string = storage.outputs.AI_TEXT_DEPLOYMENT_NAME
output ConnectionStrings__AzureQueues string = storage.outputs.AZURE_QUEUE_ENDPOINT
output ConnectionStrings__AzureBlobs string = storage.outputs.AZURE_BLOB_ENDPOINT
output AZURE_CONTAINER_REGISTRY string = ((createContainerApps) ? containers.outputs.AZURE_CONTAINER_REGISTRY : '')

