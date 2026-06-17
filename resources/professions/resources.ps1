#####################################################
# HelloID-Conn-Prov-Target-Ultimo-Employee-Resource-Profession
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

function Get-UltimoProfessions {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $baseUrl,
        [System.Collections.IDictionary]
        $Headers
    )

    $splatParams = @{
        Uri     = "$baseUrl/api/v1/object/Profession"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-UltimoRestMethod @splatParams
    Write-Information "Retrieved $($responseGet.items.count) professions from Ultimo"
    Write-Output $responseGet.items
}

function New-UltimoProfession {
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
        Uri     = "$BaseUrl/api/v1/object/Profession('$Id')"
        Method  = 'PUT'
        Headers = $Headers
        body    = @{Context = 1
                    Status = 0
                    Description = $Name
                    } | ConvertTo-Json
    }
    
    $responseCreate = Invoke-UltimoRestMethod @splatParams
    Write-Information "Created profession with name [$($name)] and id [$($Id)] in Ultimo"
    Write-Output $responseCreate
}

function Set-UltimoProfession {
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
        Uri     = "$BaseUrl/api/v1/object/Profession('$Id')"
        Method  = 'Patch'
        Headers = $Headers
        body    = @{Context = 1
                    Status = 0
                    Description = $Name
                    } | ConvertTo-Json
    }
    
    $responsePatch = Invoke-UltimoRestMethod @splatParams
    Write-Information "updated profession with id [$($Id)] to name [$($name)] in Ultimo"
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
    
    # Get professions
    $splatParamsProfessions = @{
        Headers = $authHeaders
        BaseUrl = $actionContext.Configuration.BaseUrl
    }
    $UltimoProfessions = Get-UltimoProfessions @splatParamsProfessions

    # Remove items with no Description
    $UltimoProfessions = $UltimoProfessions.Where({ $_.Description -ne "" -and $_.Description -ne $null })
    $rRefSourceData = $resourceContext.SourceData.Where({ $_.Name -ne "" -and $_.Name -ne $null })

    $UltimoProfessionsGrouped = $UltimoProfessions | Group-Object Id -AsHashTable

    # Process
    foreach ($HelloIdTitle in $rRefSourceData) {
        if (-not($UltimoProfessions.Id -eq $HelloIdTitle.Code)) {
            if (-not ($actionContext.DryRun -eq $true)) {
                Write-Information "Creating Ultimo profession with the name [$($HelloIdTitle.Name)] and id [$($HelloIdTitle.Code)] in Ultimo."
                # Create profession
                $splatParamsCreateProfession = @{
                    Headers = $authHeaders
                    BaseUrl = $actionContext.Configuration.BaseUrl
                    Name    = $HelloIdTitle.Name
					Id      = $HelloIdTitle.Code
                }
                
                $newProfession = New-UltimoProfession @splatParamsCreateProfession
                    
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = "CreateResource"    
                        Message = "Created Ultimo profession with the name [$($newProfession.description)] and ID [$($newProfession.id)]"
                        IsError = $false
                    })
            }
            else {
                
                Write-Warning "Preview: Would create Ultimo profession $($HelloIdTitle.Code) with name $($HelloIdTitle.Name)"
            }
        }
        else {
            $UltimoProfession = $UltimoProfessionsGrouped[$HelloIdTitle.Code]
            
            if (-not($UltimoProfession.Description -eq $HelloIdTitle.Name)) {
                if (-not ($actionContext.DryRun -eq $true)) {
                    Write-Information "Renaming Ultimo profession with the name [$($UltimoProfession.Description)] to [$($HelloIdTitle.Name)] in Ultimo."
                    # Rename profession
                    $splatParamsCreateProfession = @{
                        Headers = $authHeaders
                        BaseUrl = $actionContext.Configuration.BaseUrl
                        Name    = $HelloIdTitle.Name
                        Id      = $UltimoProfession.Id
                    }
                    
                    $updatedProfession = Set-UltimoProfession @splatParamsCreateProfession
                        
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = "CreateResource"    
                            Message = "Renamed Ultimo profession with the name [$($UltimoProfession.Description)] to [$($HelloIdTitle.Name)]"
                            IsError = $false
                        })
                }
                else {
                    
                    Write-Warning "Preview: Would rename Ultimo profession [$($UltimoProfession.Description)] to [$($HelloIdTitle.Name)]"
                }
                
            }
            else {
                Write-Information "Not creating profession [$($HelloIdTitle.Code)] as it already exists in Ultimo"
            }
        }
    }
}
catch {
    
    $outputContext.success = $false

    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Ultimo-EmployeeError -ErrorObject $ex
        $auditMessage = "Could not create profession. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create profession. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

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