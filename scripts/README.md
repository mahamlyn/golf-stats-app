# Deployment Scripts

This folder contains the Windows Server prerequisite installer and the deployment script used by the manual GitHub Actions workflow. Neither script installs the SQL Server database engine.

| Script | Purpose |
| --- | --- |
| [install-golf-stats-prerequisites.ps1](install-golf-stats-prerequisites.ps1) | One-time, elevated setup of IIS features and the non-SQL app prerequisites. |
| [deploy-golf-stats.ps1](deploy-golf-stats.ps1) | Applies the database schema and deploys the app. Normally run through GitHub Actions. |

See the [IIS and SQL Express deployment guide](../documentation/iis-sql-express-deployment.md) for the full server setup and security requirements.

## Install Prerequisites

Run this once on the Windows Server from an **elevated 64-bit PowerShell** session. Stage the official vendor installers in a local directory first. Example filenames below are illustrative; pass the actual filenames you downloaded.

```powershell
.\scripts\install-golf-stats-prerequisites.ps1 `
  -InstallerDirectory 'C:\Installers\GolfStats' `
  -PythonInstaller 'python-3.12.x-amd64.exe' `
  -OdbcDriverInstaller 'msodbcsql18.msi' `
  -SqlCmdInstaller 'sqlcmd.msi' `
  -UrlRewriteInstaller 'rewrite_amd64_en-US.msi' `
  -ArrInstaller 'requestRouter_amd64.msi'
```

The script installs only missing components:

- IIS, static content, logging, filtering, Windows Authentication and management features.
- Python 3.12 x64, including `py.exe` and pip.
- Microsoft ODBC Driver 18 for SQL Server and the `sqlcmd` client utility.
- IIS URL Rewrite and Application Request Routing (ARR); ARR proxying is enabled.

It checks Authenticode signatures and expected publishers before running vendor installers. If a component is already present, its installer filename can be omitted. `-InstallerDirectory` is still required and must be an existing directory. A reboot warning means restart the server before configuring the site or running the deployment workflow.

This script does **not** install SQL Server, create a database, create an IIS site or TLS binding, configure the Waitress Windows service, or register the GitHub Actions runner. Those are separate setup tasks. Installer logs are written to the current user's temporary directory.

## Deploy the App

Use the GitHub Actions workflow rather than invoking the deployment script manually:

1. Register and configure the self-hosted Windows runner as described in the deployment guide. It must have the `golf-stats-prod` label and run with the rights required by the deployment.
2. Configure the GitHub `production` Environment variables:

   | Variable | Example | Description |
   | --- | --- | --- |
   | `GOLF_DEPLOY_ROOT` | `C:\Apps\GolfStats` | Stable deployment directory. The app is installed under its `website` subdirectory. |
   | `GOLF_SERVICE_NAME` | `GolfStatsWaitress` | Existing Waitress Windows service name. |
   | `GOLF_IIS_SITE_NAME` | `Golf Stats` | Existing IIS site name. |
   | `GOLF_HEALTH_URL` | `https://golf.example.org/api/database/info` | HTTPS health endpoint accessible to the runner identity. |

3. In GitHub, select **Actions > Deploy Golf Stats to IIS > Run workflow** and approve the `production` environment deployment.
4. Enter the SQL Server instance. Leave sample-data seeding disabled for a production database.

The workflow passes its inputs to `deploy-golf-stats.ps1`. The deployment script checks the required machine components, SQL Server Express version and connectivity, IIS site and authentication configuration, and the existing automatic-start Waitress service. It then applies `database/01_create_schema.sql`, optionally applies `database/02_seed_sample_data.sql`, copies the website, configures Windows-authenticated SQL settings, installs Python requirements, restarts Waitress, and checks the HTTPS health endpoint.

The runner identity must use Windows Authentication to connect to SQL Server and have deployment permissions to create `GolfStats` and apply schema changes. The Waitress service has a separate runtime identity and database permissions. Python package installation requires the server to reach the configured package index or an approved internal mirror.

The workflow is manually triggered only. It does not create or configure the runner, service, IIS site, certificate, reverse-proxy rule or database backup. Take and verify a database backup before deploying schema changes; automatic rollback is not implemented.

## Local Validation

The scripts can be parsed without installing components:

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path .\scripts\install-golf-stats-prerequisites.ps1),
  [ref]$tokens,
  [ref]$errors
) | Out-Null
$errors
```

Installing prerequisites changes Windows Server roles and software and must only be run on the intended server after reviewing the deployment guide.
