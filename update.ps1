#################################################
# HelloID-Conn-Prov-Target-Ultimo-Employee-Update
#
# Version: 1.0.0
#################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = [PSCustomObject]@{
    DataProvider   = ''
    Description    = ''
    EmailAddress   = $p.Contact.Business.Email
    ExternalId     = $p.ExternalId
    ExternalStatus = ''
    Function       = $p.PrimaryContract.Title.Name
    PhoneInternal  = $p.Contact.Business.Phone.Fixed
    MiddleName     = ''
    MobilePhone    = ''
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
        $currentAccount = Invoke-RestMethod @splatParams -Verbose:$false
    }
    catch {
        $ex = $PSItem
        $errorObj = Resolve-Ultimo-EmployeeError -ErrorObject $ex
        Write-Verbose $errorObj.ErrorDetails
        if ($ex.Exception.Response.StatusCode -eq 'NotFound') {
            $currentAccount = $null
        }
        else {
            throw
        }
    }

    # Always compare the account against the current account in target system
    if ($null -ne $currentAccount) {
        $splatCompareProperties = @{
            ReferenceObject  = @($currentAccount.PSObject.Properties)
            DifferenceObject = @($account.PSObject.Properties)
        }
        $propertiesChanged = (Compare-Object @splatCompareProperties -PassThru).Where({$_.SideIndicator -eq '=>'})
        if ($($propertiesChanged.count -ne 0)) {
            $action = 'Update'
            $dryRunMessage = "Account property(s) required to update: [$($propertiesChanged.name -join ",")]"

            $changedPropertiesObject = @{}
            foreach ($property in $propertiesChanged) {
                $propertyName = $property.Name
                $propertyValue = $account.$propertyName

                $changedPropertiesObject.$propertyName = $propertyValue
            }

        } elseif (-not($propertiesChanged)) {
            $action = 'NoChanges'
            $dryRunMessage = 'No changes will be made to the account during enforcement'
        }
    } elseif ($null -eq $currentAccount) {
        $action = 'NotFound'
        $dryRunMessage = "Ultimo-Employee account for: [$($p.DisplayName)] not found. Possibly deleted"
    }
    Write-Verbose $dryRunMessage

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Update' {
                Write-Verbose "Updating Ultimo-Employee account with accountReference: [$aRef]"
                $body = $changedPropertiesObject | ConvertTo-Json
                $splatParams['Uri'] = "$($config.BaseUrl)/api/v1/object/Employee('$aRef')"
                $splatParams['Body'] = [System.Text.Encoding]::UTF8.GetBytes($body)
                $splatParams['Method'] = 'PATCH'
                $splatParams['ContentType'] = 'application/json'
                $null = Invoke-RestMethod @splatParams -Verbose:$false

                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                    Message = 'Update account was successful'
                    IsError = $false
                })
                break
            }

            'NoChanges' {
                Write-Verbose "No changes to Ultimo-Employee account with accountReference: [$aRef]"

                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                    Message = 'No changes will be made to the account during enforcement'
                    IsError = $false
                })
                break
            }

            'NotFound' {
                $success = $false
                $auditLogs.Add([PSCustomObject]@{
                    Message = "Ultimo-Employee account for: [$($p.DisplayName)] not found. Possibly deleted"
                    IsError = $true
                })
                break
            }
        }
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException')) {
        $errorObj = Resolve-Ultimo-EmployeeError -ErrorObject $ex
        $auditMessage = "Could not update Ultimo-Employee account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not update Ultimo-Employee account. Error: $($ex.Exception.Message)"
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
        Account   = $account
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
