#################################################
# HelloID-Conn-Prov-Target-Ultimo-Employee-Create
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

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
            } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
                $rawErrorObject = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                $convertedError = $rawErrorObject | ConvertFrom-Json
            }
            $httpErrorObj.ErrorDetails = "Message: $($convertedError.message), code: $($convertedError.code)"
            $httpErrorObj.FriendlyMessage = $($convertedError.message)
        } catch {
            $httpErrorObj.FriendlyMessage = "Received an unexpected response. The JSON could not be converted, error: [$($_.Exception.Message)]. Original error from web service: [$($ErrorObject.Exception.Message)]"
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    # Set authentication headers
    $splatParams = @{
        Headers = @{
            APIKey = $($actionContext.Configuration.APIKey)
        }
    }

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.accountField
        $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }
    }

    try {
        Write-Information "Verifying if Ultimo-Employee account for [$($personContext.Person.DisplayName)] must be created or correlated"
        $splatParams['Uri'] = "$($actionContext.Configuration.BaseUrl)/api/v1/object/Employee('$correlationValue')"
        $splatParams['Method'] = 'GET'
        $correlatedAccount = Invoke-RestMethod @splatParams -Verbose:$false
    }
    catch {
        $ex = $PSItem
        $errorObj = Resolve-Ultimo-EmployeeError -ErrorObject $ex
        Write-Information $errorObj.ErrorDetails
        if ($ex.Exception.Response.StatusCode -eq 'NotFound') {
            $correlatedAccount = $null
        }
        else {
            throw
        }
    }

    if ($null -ne $correlatedAccount) {
        $action = 'CorrelateAccount'
    } else {
        $action = 'CreateAccount'
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $action Ultimo-Employee account for: [$($personContext.Person.DisplayName)], will be executed during enforcement"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'CreateAccount' {
                Write-Information 'Creating and correlating Ultimo-Employee account'
                $body = $actionContext.Data | ConvertTo-Json
                $splatParams['Uri'] = "$($actionContext.Configuration.BaseUrl)/api/v1/object/Employee('$correlationValue')"
                $splatParams['Body'] = [System.Text.Encoding]::UTF8.GetBytes($body)
                $splatParams['Method'] = 'PUT'
                $splatParams['ContentType'] = 'application/json'
                $createdAccount = Invoke-RestMethod @splatParams -Verbose:$false
                $outputContext.Data = $createdAccount
                $outputContext.AccountReference = $createdAccount.Id
                $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)"
                break
            }

            'CorrelateAccount' {
                Write-Information 'Correlating Ultimo-Employee account'
                $outputContext.Data = $correlatedAccount
                $outputContext.AccountReference = $correlatedAccount.Id
                $outputContext.AccountCorrelated = $true
                $auditLogMessage = "Correlated account: [$($correlatedAccount.ExternalId)] on field: [$($correlationField)] with value: [$($correlationValue)]"
                break
            }
        }

        $outputContext.success = $true
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = $action
                Message = $auditLogMessage
                IsError = $false
            })
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Ultimo-EmployeeError -ErrorObject $ex
        $auditMessage = "Could not create or correlate Ultimo-Employee account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create or correlate Ultimo-Employee account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
