#####################################################
# HelloID-Conn-Prov-Target-Ultimo-Employee-Import
# PowerShell V2
#####################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

try {
    Write-Information 'Starting target account import'

    $importFields = $($actionContext.ImportFields)
    
    
    # Add mandatory fields for HelloID to query and return
    if ('Id' -notin $importFields) { $importFields += 'Id' }
    if ('Description' -notin $importFields) { $importFields += 'Description' }
    if ('ExternalId' -notin $importFields) { $importFields += 'ExternalId' }
    # Convert to a ',' string
    $fields = $importFields -join ','
    Write-Information "Querying fields [$fields]"

    # Set authentication headers
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("APIKey", "$($actionContext.Configuration.APIKey)")
    

    $existingAccounts = @()
    $uri = "$($actionContext.Configuration.BaseUrl)/api/v1/object/Employee?select=$fields"
    
    do {
        $splatParams = @{
            Uri         = $uri
            Headers     = $headers
            Method      = 'GET'
            ContentType = 'application/json'
        }
    
        $partialResultUsers = Invoke-RestMethod @splatParams
        $existingAccounts += $partialResultUsers.items
        $uri = $partialResultUsers.nextPageLink

        Write-Information "Successfully queried [$($existingAccounts.count)] existing accounts"
    } while ($uri)

    # Map the imported data to the account field mappings
    foreach ($account in $existingAccounts) {
        $userName = $account.ExternalId
        if([string]::IsNullOrEmpty($userName)){
            $userName = $account.Id
        }

        $displayname = $account.Description
        if([string]::IsNullOrEmpty($displayname)){
            $displayname = $account.Id
        }

        # Return the result
        Write-Output @{
            AccountReference = $account.Id
            DisplayName      = $displayname
            UserName         = $userName
            Enabled          = $false
            Data             = $account
        }
    }
    Write-Information 'Target account import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {

        if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
            Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.ErrorDetails.Message)"
            Write-Error "Could not import account entitlements. Error: $($ex.ErrorDetails.Message)"
        }
        else {
            Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            Write-Error "Could not import account entitlements. Error: $($ex.Exception.Message)"
        }
    }
    else {
        Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import account entitlements. Error: $($ex.Exception.Message)"
    }
}