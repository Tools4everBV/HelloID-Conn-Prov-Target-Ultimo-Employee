
# HelloID-Conn-Prov-Target-Ultimo-Employee

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="https://www.ultimo.com/wp-content/themes/ultimo-software-solutions/dist/images/ifs-ultimo-rgb.svg">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Ultimo-Employee](#helloid-conn-prov-target-ultimo-employee)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Connection settings](#connection-settings)
    - [Remarks](#remarks)
        - [Using the `ExternalId` as primary key](#using-the-externalid-as-primary-key)
        - [Using database _auto increment_ as primary key](#using-database-auto-increment-as-primary-key)
          - [Additional lookup needed](#additional-lookup-needed)
        - [Correlation __always__ based on `Id`](#correlation-always-based-on-id)
        - [`Id` max length of `9` chars](#id-max-length-of-9-chars)
      - [UTF8 encoding](#utf8-encoding)
      - [Error handling](#error-handling)
      - [Creation / correlation process](#creation--correlation-process)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Ultimo-Employee_ is a _target_ connector. Ultimo provides a set of REST APIs that enable programmatic interaction with its data. While most of Ultimo's APIs are custom-built for each customer and not standardized, the _employee_ API follows standardized specifications.

The following lifecycle events are available:

| Event  | Description | Notes |
|---	 |---	|---	|
| create.ps1 | Create (or update) and correlate an Account | - |
| update.ps1 | Update the Account | - |
| delete.ps1 | Delete the Account | - |

## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                        | Mandatory   |
| ------------ | -----------                        | ----------- |
| BaseUrl      | The URL to the API                 | Yes         |
| ApiKey       | The ApiKey to connect to the API   | Yes         |

### Remarks

##### Using the `ExternalId` as primary key

The `Id` serves as the primary key for the entity in the database. However, it is also possible to use the `ExternalId` as an alternative primary key in the database.

In version `1.0.0` of the connector, the `ExternalId` is used as the primary key in the database. This is implemented using an `HTTP.PUT` method in the API call, with a parameter, which value holds the value of the `ExternalId`.

```powershell
$splatParams['Uri'] = "$($config.BaseUrl)/api/v1/object/Employee('$($account.ExternalId)')"
$splatParams['Body'] = [System.Text.Encoding]::UTF8.GetBytes($body)
$splatParams['Method'] = 'PUT'
$splatParams['ContentType'] = 'application/json'
$response = Invoke-RestMethod @splatParams -Verbose:$false
$accountReference = $response.Id
```

##### Using database _auto increment_ as primary key

If for some reason, you need to switch to using the `Id` is the primary key in the database you'll have to modify the code using an HTTP post method.
See example below.

```powershell
$splatParams['Uri'] = "$($config.BaseUrl)/api/v1/object/Employee"
$splatParams['Body'] = [System.Text.Encoding]::UTF8.GetBytes($body)
$splatParams['Method'] = 'POST'
$splatParams['ContentType'] = 'application/json'
$response = Invoke-RestMethod @splatParams -Verbose:$false
$accountReference = $response.Id
```

###### Additional lookup needed

This may also imply that an additional lookup is required to find the `ExternalId` for a specific user.

```powershell
$splatParams['Uri'] = "$($config.BaseUrl)/api/v1/object/Employee"
$splatParams['Method'] = 'GET'
$response = Invoke-RestMethod @splatParams -Verbose:$false
$lookup = $response.items | Group-Object -Property ExternalId -AsHashTable -AsString
$lookupUser = $lookup[$account.ExternalId]
```

##### Correlation __always__ based on `Id`

The correlation is always based on the 'Id,' whether it contains the database ID or the `ExternalId`.

##### `Id` max length of `9` chars

The `ExternalId` has a max length of 9 characters.

#### UTF8 encoding

By default, version `1.0.0` handles UTF-8 encoding. This ensures that data is appropriately encoded. Encoding is handled in both the `create` and `update` lifecycle actions using the code block listed below.

```powershell
$body = $account | ConvertTo-Json
$splatInvokeRestMethodProps['Body'] = [System.Text.Encoding]::UTF8.GetBytes($body)
```

#### Error handling

version `1.0.0` is designed to run on cloud environments only.
If, for some reason, the connector will need to run using a local / on-premises HelloID agent, you will need to modify the error handling function and logic accordingly.

#### Creation / correlation process

A new functionality is the possibility to update the account in the target system during the correlation process. By default, this behavior is disabled. Meaning, the account will only be created or correlated.

You can change this behavior in the `configuration` by setting the checkbox `UpdatePersonOnCorrelate` to the value of `true`.

> Be aware that this might have unexpected implications.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
