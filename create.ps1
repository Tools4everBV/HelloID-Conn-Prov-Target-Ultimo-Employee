#################################################
# HelloID-Conn-Prov-Target-Ultimo-Employee-Create
#
# Version: 1.0.0
#################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = [PSCustomObject]@{
    Context        = 1
    DataProvider   = ''
    Description    = ''
    EmailAddress   = $p.Contact.Business.Email
    ExternalId     = $p.ExternalId
    ExternalStatus = ''
    Function       = $p.PrimaryContract.Title.Name
    PhoneInternal  = $p.Contact.Business.Phone.Fixed
    MiddleName     = ''
    MobilePhone    = ''
    Status         = 0
    #CostCenter     = $p.PrimaryContract.Department.DisplayName
    #Department     = $p.PrimaryContract.Department.DisplayName
    #Gender         = '' # either '0001 or 0002'
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
function Resolve-Ultimo-EmployeeError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }

        try {
            if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
                $convertedError = $ErrorObject.ErrorDetails.Message | ConvertFrom-Json
                $httpErrorObj.ErrorDetails = "Message: $($convertedError.message), code: $($convertedError.code)"
                $httpErrorObj.FriendlyMessage = $($convertedError.message)
            }
        } catch {
            $httpErrorObj.FriendlyMessage = "Received an unexpected response. The JSON could not be converted, error: [$($_.Exception.Message)]. Original error from web service: [$($ErrorObject.Exception.Message)]"
        }
        Write-Output $httpErrorObj
    }
}
#endregion

# Begin
try {
    # Verify if [account.ExternalId] has a value
    if ([string]::IsNullOrEmpty($($account.ExternalId))) {
        throw 'Mandatory attribute [account.ExternalId] is empty. Please make sure it is correctly mapped'
    }

    # Set authentication headers
    $splatParams = @{
        Headers = @{
            APIKey = $($config.APIKey)
        }
    }

    # Verify if a user must be either [created and correlated], [updated and correlated] or just [correlated]
    try {
        Write-Verbose "Verifying if Ultimo-Employee account for [$($p.DisplayName)] must be created or correlated"
        $splatParams['Uri'] = "$($config.BaseUrl)/api/v1/object/Employee('$($account.ExternalId)')"
        $splatParams['Method'] = 'GET'
        $responseUser = Invoke-RestMethod @splatParams -Verbose:$false
    }
    catch {
        $ex = $PSItem
        $errorObj = Resolve-Ultimo-EmployeeError -ErrorObject $ex
        Write-Verbose $errorObj.ErrorDetails
        if ($ex.Exception.Response.StatusCode -eq 'NotFound') {
            $responseUser = $null
        }
        else {
            throw
        }
    }

    if ($null -eq $responseUser){
        $action = 'Create-Correlate'
    } elseif ($($config.UpdatePersonOnCorrelate) -eq $true) {
        $action = 'Update-Correlate'
    } else {
        $action = 'Correlate'
    }

    # Add a warning message showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $action Ultimo-Employee account for: [$($p.DisplayName)], will be executed during enforcement"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Create-Correlate' {
                Write-Verbose 'Creating and correlating Ultimo-Employee account'
                $body = $account | ConvertTo-Json
                $splatParams['Uri'] = "$($config.BaseUrl)/api/v1/object/Employee('$($account.ExternalId)')"
                $splatParams['Body'] = [System.Text.Encoding]::UTF8.GetBytes($body)
                $splatParams['Method'] = 'PUT'
                $splatParams['ContentType'] = 'application/json'
                $response = Invoke-RestMethod @splatParams -Verbose:$false
                $accountReference = $response.Id
                break
            }

            'Update-Correlate' {
                Write-Verbose 'Updating and correlating Ultimo-Employee account'
                $body = $account | ConvertTo-Json
                $splatParams['Uri'] = "$($config.BaseUrl)/api/v1/object/Employee('$($account.ExternalId)')"
                $splatParams['Body'] = [System.Text.Encoding]::UTF8.GetBytes($body)
                $splatParams['Method'] = 'PUT'
                $splatParams['ContentType'] = 'application/json'
                $null = Invoke-RestMethod @splatParams -Verbose:$false
                $accountReference = $responseUser.Id
                break
            }

            'Correlate' {
                Write-Verbose 'Correlating Ultimo-Employee account'
                $accountReference = $responseUser.Id
                break
            }
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Message = "$action account was successful. AccountReference is: [$accountReference]"
                IsError = $false
            })
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException')) {
        $errorObj = Resolve-Ultimo-EmployeeError -ErrorObject $ex
        $auditMessage = "Could not $action Ultimo-Employee account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not $action Ultimo-Employee account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
# End
} finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
