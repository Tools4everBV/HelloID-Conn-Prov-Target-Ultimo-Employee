#################################################
# HelloID-Conn-Prov-Target-Ultimo-Employee-Delete
#
# Version: 1.0.0
#################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

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
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($aRef))) {
        throw 'The account reference could not be found'
    }

    # Set authentication headers
    $splatParams = @{
        Headers = @{
            APIKey = $($config.APIKey)
        }
    }

    try {
        Write-Verbose "Verifying if a Ultimo-Employee account for [$($p.DisplayName)] exists"
        $splatParams['Uri'] = "$($config.BaseUrl)/api/v1/object/Employee('$aRef')"
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

    if ($responseUser){
        $action = 'Found'
        $dryRunMessage = "Delete Ultimo-Employee account for: [$($p.DisplayName)] will be executed during enforcement"
    } elseif($null -eq $responseUser) {
        $action = 'NotFound'
        $dryRunMessage = "Ultimo-Employee account for: [$($p.DisplayName)] not found. Possibly already deleted. Skipping action"
    }
    Write-Verbose $dryRunMessage

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        Write-Verbose "Deleting Ultimo-Employee account with accountReference: [$aRef]"

        switch ($action){
            'Found'{
                $splatParams['Uri'] = "$($config.BaseUrl)/api/v1/object/Employee('$aRef')"
                $splatParams['Body'] = @{Status = -1 } | ConvertTo-Json
                $splatParams['Method'] = 'PATCH'
                $splatParams['ContentType'] = 'application/json'
                $null = Invoke-RestMethod @splatParams -Verbose:$false
                $auditLogs.Add([PSCustomObject]@{
                    Message = 'Delete account was successful'
                    IsError = $false
                })
                break
            }

            'NotFound'{
                $auditLogs.Add([PSCustomObject]@{
                    Message = "Ultimo-Employee account for: [$($p.DisplayName)] not found. Possibly already deleted. Skipping action"
                    IsError = $false
                })
                break
            }
        }

        $success = $true
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException')) {
        $errorObj = Resolve-Ultimo-EmployeeError -ErrorObject $ex
        $auditMessage = "Could not delete Ultimo-Employee account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not delete Ultimo-Employee account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
# End
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
