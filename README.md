
# HelloID-Conn-Prov-Target-Ultimo-Employee

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Ultimo-Employee/blob/main/Logo.png?raw=true">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Ultimo-Employee](#helloid-conn-prov-target-ultimo-employee)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [Using the `ExternalId` as primary key](#using-the-externalid-as-primary-key)
    - [Using database _auto increment_ as primary key](#using-database-auto-increment-as-primary-key)
      - [Additional lookup needed](#additional-lookup-needed)
    - [Correlation always based on `Id`](#correlation-always-based-on-id)
    - [`Id` max length of `9` chars](#id-max-length-of-9-chars)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Ultimo-Employee_ is a _target_ connector. _Ultimo-Employee_ provides a set of REST APIs that allow you to programmatically interact with its data.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                | Remarks                     |
| ----------------------------------------- | --------- | ---------------------- | --------------------------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Delete |                             |
| **Permissions**                           | ❌         | -                      |                             |
| **Resources**                             | ✅         | -                      | Departments and Professions |
| **Entitlement Import: Accounts**          | ✅         | -                      |                             |
| **Entitlement Import: Permissions**       | ❌         | -                      |                             |
| **Governance Reconciliation Resolutions** | ✅         | -                      |                             |

> [!NOTE]
> While most of Ultimo's APIs are custom-built for each customer and not standardized, the _employee_ API follows standardized specifications.

## Getting started

### HelloID Icon URL

URL of the icon used for the HelloID Provisioning target system.

```text
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Ultimo-Employee/refs/heads/main/Icon.png
```

### Requirements

- The API key used by HelloID must be authorized to read and modify Employees in Ultimo.
- For resource synchronization, the API key must also be authorized for Department and Profession endpoints.

### Connection settings

The following settings are required to connect to the API.

| Setting | Description                      | Mandatory |
| ------- | -------------------------------- | --------- |
| ApiKey  | The ApiKey to connect to the API | Yes       |
| BaseUrl | The URL to the API               | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Ultimo-Employee_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `ExternalId`                      |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Account Reference

The account reference is populated with the property `Id` from _Ultimo-Employee_.

## Remarks

### Using the `ExternalId` as primary key

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

### Using database _auto increment_ as primary key

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

#### Additional lookup needed

This may also imply that an additional lookup is required to find the `ExternalId` for a specific user.

```powershell
$splatParams['Uri'] = "$($actionContext.Configuration.BaseUrl)/api/v1/object/Employee"
$splatParams['Method'] = 'GET'
$response = Invoke-RestMethod @splatParams -Verbose:$false
$lookup = $response.items | Group-Object -Property ExternalId -AsHashTable -AsString
$lookupUser = $lookup[$actionContext.Data.ExternalId]
```

### Correlation always based on `Id`

The correlation is always based on the 'Id,' whether it contains the database ID or the `ExternalId`.

### `Id` max length of `9` chars

The `ExternalId` has a max length of 9 characters.

## Development resources

### API endpoints

The following endpoints are used by the connector.

| Endpoint                  | HTTP Method     | Description                                    |
| ------------------------- | --------------- | ---------------------------------------------- |
| /api/v1/object/Employee   | GET, PUT, PATCH | Retrieve, create, update and disable employees |
| /api/v1/object/Department | GET, PUT, PATCH | Retrieve, create and update departments        |
| /api/v1/object/Profession | GET, PUT, PATCH | Retrieve, create and update professions        |

### API documentation

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
