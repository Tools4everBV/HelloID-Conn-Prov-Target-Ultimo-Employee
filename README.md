
# HelloID-Conn-Prov-Target-Ultimo-Employee

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://www.ultimo.com/wp-content/themes/ultimo-software-solutions/dist/images/ifs-ultimo-rgb.svg">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Ultimo-Employee](#helloid-conn-prov-target-ultimo-employee)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Provisioning PowerShell V2 connector](#provisioning-powershell-v2-connector)
      - [Correlation configuration](#correlation-configuration)
      - [Field mapping](#field-mapping)
    - [Connection settings](#connection-settings)
    - [Remarks](#remarks)
      - [Using the `ExternalId` as primary key](#using-the-externalid-as-primary-key)
      - [Using database _auto increment_ as primary key](#using-database-auto-increment-as-primary-key)
        - [Additional lookup needed](#additional-lookup-needed)
      - [Correlation __always__ based on `Id`](#correlation-always-based-on-id)
      - [`Id` max length of `9` chars](#id-max-length-of-9-chars)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Ultimo-Employee_ is a _target_ connector. _Ultimo-Employee_ provides a set of REST API's that allow you to programmatically interact with its data. The HelloID connector uses the API endpoints listed in the table below.

> [!NOTE]
> While most of Ultimo's APIs are custom-built for each customer and not standardized, the _employee_ API follows standardized specifications.

| Endpoint                | Description       |
| ----------------------- | ----------------- |
| /api/v1/object/Employee | Employee endpoint |

The following lifecycle actions are available:

| Action             | Description                          |
| ------------------ | ------------------------------------ |
| create.ps1         | PowerShell _create_ lifecycle action |
| delete.ps1         | PowerShell _delete_ lifecycle action |
| update.ps1         | PowerShell _update_ lifecycle action |
| configuration.json | Default _configuration.json_         |
| fieldMapping.json  | Default _fieldMapping.json_          |

## Getting started

### Provisioning PowerShell V2 connector

#### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Ultimo-Employee_ to a person in _HelloID_.

To properly setup the correlation:

1. Open the `Correlation` tab.

2. Specify the following configuration:

    | Setting                   | Value                             |
    | ------------------------- | --------------------------------- |
    | Enable correlation        | `True`                            |
    | Person correlation field  | `PersonContext.Person.ExternalId` |
    | Account correlation field | `ExternalId`                      |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

#### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Connection settings

The following settings are required to connect to the API.

| Setting | Description                      | Mandatory |
| ------- | -------------------------------- | --------- |
| BaseUrl | The URL to the API               | Yes       |
| ApiKey  | The ApiKey to connect to the API | Yes       |

### Remarks

#### Using the `ExternalId` as primary key

The `Id` serves as the primary key for the entity in the database. However, it is also possible to use the `ExternalId` as an alternative primary key in the database.

In version `1.0.0` of the connector, the `ExternalId` is used as the primary key in the database. This is implemented using an `HTTP.PUT` method in the API call, with a parameter, which value holds the value of the `ExternalId`.

```powershell
$splatParams['Uri'] = "$($actionContext.Configuration.BaseUrl)/api/v1/object/Employee('$($correlationValue)')"
$splatParams['Body'] = [System.Text.Encoding]::UTF8.GetBytes($body)
$splatParams['Method'] = 'PUT'
$splatParams['ContentType'] = 'application/json'
$createdAccount = Invoke-RestMethod @splatParams -Verbose:$false
$accountReference = $createdAccount.Id
```

> [!TIP]
> Make sure that correlation is enabled if you're using the externalId as primary key.

#### Using database _auto increment_ as primary key

If for some reason, you need to switch to using the `Id` is the primary key in the database you'll have to modify the code using an HTTP post method.
See example below.

```powershell
$splatParams['Uri'] = "$($actionContext.Configuration.BaseUrl)/api/v1/object/Employee"
$splatParams['Body'] = [System.Text.Encoding]::UTF8.GetBytes($body)
$splatParams['Method'] = 'POST'
$splatParams['ContentType'] = 'application/json'
$createdAccount = Invoke-RestMethod @splatParams -Verbose:$false
$accountReference = $createdAccount.Id
```

##### Additional lookup needed

This may also imply that an additional lookup is required to find the `ExternalId` for a specific user.

```powershell
$splatParams['Uri'] = "$($actionContext.Configuration.BaseUrl)/api/v1/object/Employee"
$splatParams['Method'] = 'GET'
$response = Invoke-RestMethod @splatParams -Verbose:$false
$lookup = $response.items | Group-Object -Property ExternalId -AsHashTable -AsString
$lookupUser = $lookup[$actionContext.Data.ExternalId]
```

#### Correlation __always__ based on `Id`

The correlation is always based on the 'Id,' whether it contains the database ID or the `ExternalId`.

#### `Id` max length of `9` chars

The `ExternalId` has a max length of 9 characters.

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/4953-helloid-conn-prov-target-ultimo-employee)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
