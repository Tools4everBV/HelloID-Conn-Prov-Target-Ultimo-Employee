#################################################
# HelloID-Conn-Prov-Target-Ultimo-Employee-Update
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
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    # Set authentication headers
    $splatParams = @{
        Headers = @{
            APIKey = $($actionContext.Configuration.APIKey)
        }
    }

    Write-Information "Verifying if a Ultimo-Employee account for [$($personContext.Person.DisplayName)] exists"
    try {
        Write-Information "Verifying if a Ultimo-Employee account for [$($personContext.Person.DisplayName)] exists"
        $splatParams['Uri'] = "$($actionContext.Configuration.BaseUrl)/api/v1/object/Employee('$($actionContext.References.Account)')"
        $splatParams['Method'] = 'GET'
        $correlatedAccount = Invoke-RestMethod @splatParams -Verbose:$false
        $outputContext.PreviousData = $correlatedAccount
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

    # Always compare the account against the current account in target system
    if ($null -ne $correlatedAccount) {
        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccount.PSObject.Properties)
            DifferenceObject = @($actionContext.Data.PSObject.Properties)
        }
        $propertiesChanged = (Compare-Object @splatCompareProperties -PassThru).Where({$_.SideIndicator -eq '=>'})
        if ($($propertiesChanged.count -ne 0)) {
            $action = 'UpdateAccount'
            $dryRunMessage = "Account property(s) required to update: [$($propertiesChanged.name -join ",")]"

            $changedPropertiesObject = @{}
            foreach ($property in $propertiesChanged) {
                $propertyName = $property.Name
                $propertyValue = $actionContext.Data.$propertyName

                $changedPropertiesObject.$propertyName = $propertyValue
            }
        } elseif (-not($propertiesChanged)) {
            $action = 'NoChanges'
            $dryRunMessage = 'No changes will be made to the account during enforcement'
        }
    } elseif ($null -eq $currentAccount) {
        $action = 'NotFound'
        $dryRunMessage = "Ultimo-Employee account for: [$($personContext.Person.DisplayName)] not found. Possibly deleted."
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'UpdateAccount' {
                Write-Information "Updating Ultimo-Employee account with accountReference: [$($actionContext.References.Account)]"
                $body = $changedPropertiesObject | ConvertTo-Json
                $splatParams['Uri'] = "$($actionContext.Configuration.BaseUrl)/api/v1/object/Employee('$($actionContext.References.Account)')"
                $splatParams['Body'] = [System.Text.Encoding]::UTF8.GetBytes($body)
                $splatParams['Method'] = 'PATCH'
                $splatParams['ContentType'] = 'application/json'
                $null = Invoke-RestMethod @splatParams -Verbose:$false
                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                    IsError = $false
                })
                break
            }

            'NoChanges' {
                Write-Information "No changes to Ultimo-Employee account with accountReference: [$($actionContext.References.Account)]"
                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'No changes will be made to the account during enforcement'
                    IsError = $false
                })
                break
            }

            'NotFound' {
                $outputContext.Success  = $false
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Ultimo-Employee account with accountReference: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                    IsError = $true
                })
                break
            }
        }
    }
} catch {
    $outputContext.Success  = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Ultimo-EmployeeError -ErrorObject $ex
        $auditMessage = "Could not update Ultimo-Employee account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not update Ultimo-Employee account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
