#####################################################
# HelloID-Conn-Prov-Target-Ultimo-Employee-Resource-Department
# PowerShell V2
#####################################################

# Set to true at start, because only when an error occurs it is set to false
$outputContext.Success = $true

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

#region functions
function Set-AuthorizationHeaders {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $ApiKey
    )
    # Set authentication headers
    $authHeaders = [System.Collections.Generic.Dictionary[string, string]]::new()
    $authHeaders.Add("APIKey", "$ApiKey")

    Write-Output $authHeaders
}

function Invoke-UltimoRestMethod {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $Method,

        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        [object]
        $Body,

        [string]
        $ContentType = 'application/json',

        [System.Collections.IDictionary]
        $Headers
    )
    process {
        try {
            $splatParams = @{
                Uri         = $Uri
                Headers     = $Headers
                Method      = $Method
                ContentType = $ContentType
            }

            if ($Body) {
                $splatParams['Body'] = [Text.Encoding]::UTF8.GetBytes($Body)
            }
            Invoke-RestMethod @splatParams -Verbose:$false
        }
        catch {
            throw $_
        }
    }
}

function Get-UltimoDepartments {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $baseUrl,
        [System.Collections.IDictionary]
        $Headers
    )

    $splatParams = @{
        Uri     = "$baseUrl/api/v1/object/Department"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-UltimoRestMethod @splatParams
    Write-Information "Retrieved $($responseGet.items.count) Departments from Ultimo"
    Write-Output $responseGet.items
}

function New-UltimoDepartment {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,
		
		[ValidateNotNullOrEmpty()]
        [string]
        $Id,

        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers
    )

    $splatParams = @{
        Uri     = "$BaseUrl/api/v1/object/Department('$Id')"
        Method  = 'PUT'
        Headers = $Headers
        body    = @{Context = 1
                    Status = 0
                    Description = $Name
                    } | ConvertTo-Json
    }
    
    $responseCreate = Invoke-UltimoRestMethod @splatParams
    Write-Information "Created Department with name [$($name)] and id [$($Id)] in Ultimo"
    Write-Output $responseCreate
}

function Set-UltimoDepartment {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,
		
		[ValidateNotNullOrEmpty()]
        [string]
        $Id,

        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers
    )

    $splatParams = @{
        Uri     = "$BaseUrl/api/v1/object/Department('$Id')"
        Method  = 'Patch'
        Headers = $Headers
        body    = @{Context = 1
                    Status = 0
                    Description = $Name
                    } | ConvertTo-Json
    }
    
    $responsePatch = Invoke-UltimoRestMethod @splatParams
    Write-Information "updated Department with id [$($Id)] to name [$($name)] in Ultimo"
    Write-Output $responsePatch
}
#endregion functions

#Begin
try {
    # Setup authentication headers    
    $splatParamsAuthorizationHeaders = @{
        ApiKey   = $actionContext.Configuration.APIKey
    }
    $authHeaders = Set-AuthorizationHeaders @splatParamsAuthorizationHeaders
    
    # Get Departments
    $splatParamsDepartments = @{
        Headers = $authHeaders
        BaseUrl = $actionContext.Configuration.BaseUrl
    }
    $UltimoDepartments = Get-UltimoDepartments @splatParamsDepartments

    # Remove items with no Description
    $UltimoDepartments = $UltimoDepartments.Where({ $_.Description -ne "" -and $_.Description -ne $null })
    $rRefSourceData = $resourceContext.SourceData.Where({ $_.DisplayName -ne "" -and $_.DisplayName -ne $null })

    $UltimoDepartmentsGrouped = $UltimoDepartments | Group-Object Id -AsHashTable

    # Process
    foreach ($HelloIdDepartment in $rRefSourceData) {
        if (-not($UltimoDepartments.Id -eq $HelloIdDepartment.ExternalId)) {
            if (-not ($actionContext.DryRun -eq $true)) {
                Write-Information "Creating Ultimo Department with the name [$($HelloIdDepartment.DisplayName)] and id [$($HelloIdDepartment.ExternalId)] in Ultimo."
                # Create Department
                $splatParamsCreateDepartment = @{
                    Headers = $authHeaders
                    BaseUrl = $actionContext.Configuration.BaseUrl
                    Name    = $HelloIdDepartment.DisplayName
					Id      = $HelloIdDepartment.ExternalId
                }
                
                $newDepartment = New-UltimoDepartment @splatParamsCreateDepartment
                    
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = "CreateResource"    
                        Message = "Created Ultimo Department with the name [$($newDepartment.description)] and ID [$($newDepartment.id)]"
                        IsError = $false
                    })
            }
            else {
                
                Write-Warning "Preview: Would create Ultimo Department $($HelloIdDepartment.ExternalId) with name $($HelloIdDepartment.DisplayName)"
            }
        }
        else {
            $UltimoDepartment = $UltimoDepartmentsGrouped[$HelloIdDepartment.ExternalId]
            if (-not($UltimoDepartment.Description -eq $HelloIdDepartment.DisplayName)) {
                if (-not ($actionContext.DryRun -eq $true)) {
                    Write-Information "Renaming Ultimo Department with the name [$($UltimoDepartment.Description)] to [$($HelloIdDepartment.DisplayName)] in Ultimo."
                    # Rename Department
                    $splatParamsCreateDepartment = @{
                        Headers = $authHeaders
                        BaseUrl = $actionContext.Configuration.BaseUrl
                        Name    = $HelloIdDepartment.DisplayName
                        Id      = $UltimoDepartment.Id
                    }
                    
                    $updatedDepartment = Set-UltimoDepartment @splatParamsCreateDepartment
                        
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = "CreateResource"    
                            Message = "Renamed Ultimo Department with the name [$($UltimoDepartment.Description)] to [$($HelloIdDepartment.DisplayName)]"
                            IsError = $false
                        })
                }
                else {
                    
                    Write-Warning "Preview: Would rename Ultimo Department [$($UltimoDepartment.Description)] to [$($HelloIdDepartment.DisplayName)]"
                }
                
            }
            else {
                Write-Information "Not creating Department [$($HelloIdDepartment.ExternalId)] as it already exists in Ultimo"
            }
        }
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Ultimo-EmployeeError -ErrorObject $ex
        $auditMessage = "Could not create department $($HelloIdDepartment.ExternalId). Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create department $($HelloIdDepartment.ExternalId). Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    Write-Warning $auditMessage
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = "CreateResource"    
            Message = $auditMessage
            IsError = $true
        })
}
finally {
    # Check if auditLogs contains errors, if errors are found, set success to false
    if ($outputContext.AuditLogs.IsError -contains $true) {
        $outputContext.Success = $false
    }
}