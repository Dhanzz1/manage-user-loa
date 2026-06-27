# Copy these values into the $Script:Config hashtable inside
# src\Manage-UserLOA\Manage-UserLOA.psm1 for your own lab or environment.

$exampleConfig = @{
    LOAOUDistinguishedName      = 'OU=Users on Temporary Leave,OU=Corporate,DC=yourdomain,DC=com'
    DomainController            = 'YOURDC.yourdomain.com'
    # Confirm this attribute is free in your environment before using it.
    OUStashAttribute            = 'extensionAttribute10'
    OOOSchedulingThreshold      = 24

    GoogleEnabled               = $false
    GoogleServiceAccountToken   = ''
    GoogleDomain                = 'yourdomain.com'

    GenericSaaSEnabled          = $false
    GenericSaaSBaseUrl          = 'https://yourdomain.com'
    GenericSaaSApiToken         = ''
    GenericSaaSDeactivateEndpoint = '/api/users/{userPrincipalName}/deactivate'
    GenericSaaSReactivateEndpoint = '/api/users/{userPrincipalName}/reactivate'
    GenericSaaSMethod           = 'POST'
}

$exampleConfig
