# IIS and SQL Server Express Deployment

This guide describes a Windows Server deployment of the Golf Stats Flask app with IIS in front of a production WSGI server and SQL Server Express as its database.

## Deployment Gate

The current app is a local-use prototype, not a production-ready multi-user service. Before making it reachable by other people, complete these application changes:

- Add an authentication and authorization policy for the whole site and every `/api` route. IIS Windows Authentication can restrict an internal site to an AD group, but all allowed users can currently create and update records. The app has no user roles.
- Protect `/api/config` and `/api/config/test`. They currently allow a caller to change the database connection, and the settings page stores a SQL password in plaintext in `website/config.json`. Prefer a pre-provisioned connection using Windows Authentication; remove or administrator-restrict these endpoints for normal users. Ensure file permissions keep the config and credentials readable only by the service identity and administrators.
- Replace Flask's built-in development server with Waitress or another supported production WSGI server. Do not expose the WSGI listener to the network.
- Review error responses and logging before deployment. Database errors are returned to clients and can contain SQL/connection details.
- Set and test an explicit dependency set, including Flask, pyodbc and the selected WSGI server. The current requirements file does not pin versions or include a production server.

Do not treat binding to localhost or IIS authentication alone as a substitute for reviewing and securing the app's configuration endpoints and mutating API routes.

## Recommended Topology

```text
Browser -- HTTPS --> IIS (TLS, authentication, authorization, request logging)
                         |
                         +-- HTTP on loopback --> Waitress Windows service
                                                    |
                                                    +-- ODBC Driver 18 --> SQL Server Express
```

Host the app at the IIS site's root, such as `https://golf.example.org/`, rather than a virtual directory. The front end requests `/api/...` and `/favicon.svg` from the web root, so a virtual-directory deployment will need code changes to support a base path.

## Server Prerequisites

- Supported Windows Server with IIS installed.
- IIS URL Rewrite and Application Request Routing (ARR), with ARR proxying enabled.
- A valid TLS certificate and an IIS HTTPS binding.
- Supported 64-bit Python, the Microsoft ODBC Driver 18 for SQL Server, and a matching 64-bit Python environment.
- SQL Server Express installed and running. Decide whether it is on this server or a separate database host.
- A dedicated, non-administrator Windows identity for the Waitress service. Do not run the app as LocalSystem or an administrator.
- A service wrapper, such as WinSW or NSSM, to keep Waitress running and start it after reboot.

## Prepare SQL Server

1. Run `database/01_create_schema.sql` against the intended SQL Server instance as a database administrator.
2. Run `database/02_seed_sample_data.sql` only if sample records are wanted. Do not seed production data unnecessarily.
3. Create a SQL Server login for the Waitress service identity and a database user in `GolfStats`. For a local instance, Windows Authentication is preferred. For a remote instance, use an appropriate domain identity or a managed SQL credential.
4. Grant only the database permissions required by the app's queries and operations. The app reads data, inserts players/courses/rounds, updates course details and photos, and removes photos. Do not grant `db_owner` by default. Test the database information page separately because its metadata queries may need additional metadata permissions.
5. For a remote SQL instance, configure SQL Server TCP/IP and a fixed port, then allow that port only from the web server in the host and network firewalls. Do not expose SQL Server to the public internet.
6. Configure a trusted SQL Server TLS certificate. ODBC Driver 18 encrypts connections by default. The current app defaults `TrustServerCertificate` to `true`; for a properly certified server, set this to `false` and verify the certificate name and trust chain. Do not rely on trusting arbitrary certificates for a network deployment.

## Install the App

1. Deploy a reviewed release of the repository to a stable directory, for example `C:\Apps\GolfStats\website`. Do not deploy from a developer's working tree.
2. Create a virtual environment and install the locked production requirements:

   ```powershell
   Set-Location C:\Apps\GolfStats\website
   py -3 -m venv .venv
   .\.venv\Scripts\python.exe -m pip install --upgrade pip
   .\.venv\Scripts\python.exe -m pip install -r requirements.txt
   ```

   The production requirements must include the selected WSGI server, such as Waitress, at a tested version.
3. Provision the database connection before starting the service. The current app reads `config.json` next to `app.py`; use Windows Authentication and the service identity where possible. If retaining the Settings page, grant the service write access to this file and restrict the endpoint to administrators. Otherwise, make the connection read-only to the app and disable or remove the settings-write endpoints.
4. Apply NTFS permissions: administrators and deployment operators may modify the application; the service identity may read application files and write only to explicitly required data/config locations. IIS should not need write access to the application.
5. Test the WSGI server interactively on loopback before registering it as a service. From the `website` directory, a typical Waitress command is:

   ```powershell
   .\.venv\Scripts\waitress-serve.exe --listen=127.0.0.1:8000 app:app
   ```

   Confirm the home page and `http://127.0.0.1:8000/api/database/info` work locally. Stop the test process before starting the service.
6. Configure the service wrapper to run that command with the working directory set to the `website` directory and the service identity selected above. Configure automatic restart on failure and capture logs in a protected log directory. Start the service and verify it listens only on `127.0.0.1:8000`.

## Configure IIS

1. Create a dedicated IIS site with the intended host name and HTTPS binding. Add HTTP-to-HTTPS redirection if required by the environment.
2. Install URL Rewrite and ARR, and enable ARR proxying at the server level.
3. Add an inbound reverse-proxy rule that forwards all paths and query strings to `http://127.0.0.1:8000/{R:0}`. Preserve the request method and body so the API's `POST`, `PUT` and `DELETE` requests continue to work. Do not create a static-file-only rewrite rule.
4. Configure authentication and authorization on the site so they cover both page and API requests. For an internal deployment, restrict access to the intended AD group. Verify unauthenticated requests to `/`, `/api/config`, and write routes are rejected at IIS.
5. Keep the Waitress port blocked from inbound network access. Only IIS should be the public-facing listener. Configure IIS request filtering and logging in line with local policy.
6. Confirm the application is at the site's root. If using a URL prefix, first change and test the front-end URLs and Flask routing to honor that prefix.

## GitHub Actions Deployment

The repository includes `.github/workflows/deploy-windows.yml`, a manual-only deployment workflow. It runs the checks and deployment steps in `scripts/deploy-golf-stats.ps1`. Before registering the runner, an administrator can use [install-golf-stats-prerequisites.ps1](../scripts/install-golf-stats-prerequisites.ps1) to install and configure the non-SQL machine prerequisites. The bootstrap does not install SQL Server, create the IIS site or TLS binding, configure the Waitress Windows service, or register the GitHub runner; those remain separate setup steps.

### Prepare the Windows Runner

1. On Windows Server 2022, run the prerequisite bootstrap from an elevated 64-bit PowerShell session. It requires the already-installed Chocolatey 2.7.5+ client and access to its configured package source:

   ```powershell
   .\scripts\install-golf-stats-prerequisites.ps1
   ```

   The script installs required IIS features with `Install-WindowsFeature`, then Python 3.12 x64 (`python312`), ODBC Driver 18 (`sqlserver-odbcdriver-18`), `sqlcmd` (`sqlserver-cmdlineutils`), URL Rewrite (`urlrewrite`) and ARR (`iis-arr`) with Chocolatey. It enables ARR proxying, skips components already installed, and retries transient feed/network errors. `sqlcmd` and ODBC are client tools only; this does not install the SQL Server engine.
2. In the GitHub repository, open **Settings > Actions > Runners > New self-hosted runner**, select **Windows** and **x64**, then follow the generated registration instructions on the server. GitHub supplies a short-lived registration token; enter it only in the runner setup prompt and never commit or document it.
3. Assign the custom label `golf-stats-prod`. The workflow also requires the standard `self-hosted`, `Windows` and `X64` labels. Install the runner as a Windows service and configure it to run as a dedicated deployment identity so it is available after logoff and restart.
4. The runner identity needs local rights to install files, change the app configuration, set ACLs and restart the Waitress service. It also needs Windows Authentication access to the target SQL instance for schema deployment, and permission to access the IIS HTTPS health endpoint. Use a dedicated identity, not a personal account. The Waitress service uses a separate identity with separate runtime SQL permissions.
5. Treat this production runner as highly privileged. Restrict repository and workflow-file write access, restrict who can start deployments, and do not run pull-request or other untrusted workflows on this runner. A workflow executed on it can use the runner service identity's server and database permissions.

### Configure the GitHub Environment

1. In **Settings > Environments**, create an environment named `production`.
2. Require approval from an appropriate reviewer and limit deployment branches to the trusted release branch, such as `main`. The workflow job targets this environment, so GitHub applies its protection rules before the deployment job runs.
3. Add these **environment variables** (not secrets) to `production`:

   | Variable | Example | Purpose |
   | --- | --- | --- |
   | `GOLF_DEPLOY_ROOT` | `C:\Apps\GolfStats` | Stable deployment root; app files go in its `website` subdirectory. |
   | `GOLF_SERVICE_NAME` | `GolfStatsWaitress` | Existing Waitress Windows service name. |
   | `GOLF_IIS_SITE_NAME` | `Golf Stats` | Existing IIS site name. |
   | `GOLF_HEALTH_URL` | `https://golf.example.org/api/database/info` | HTTPS health endpoint accessible to the runner identity. |

   The workflow does not store a SQL password in GitHub; SQL uses the runner's Windows identity. Protect access to these variables and the environment as deployment configuration.
4. Before the first deployment, create the IIS site and HTTPS binding, configure Windows Authentication (Anonymous disabled), create its reverse-proxy rule to `http://127.0.0.1:8000/`, and create the Waitress Windows service. The service must run automatically under its dedicated identity, listen only on loopback, and launch `website\.venv\Scripts\waitress-serve.exe --listen=127.0.0.1:8000 app:app` with the working directory set to `website`. The health URL must return `/api/database/info` as JSON when requested using the runner identity's Windows credentials.
5. Grant the runner's SQL deployment identity the SQL permissions to create `GolfStats` and apply schema changes. The workflow checks that the target SQL edition is **Express** and the version supports the schema scripts. Do not grant the Waitress runtime identity deployment privileges.

### Run a Manual Deployment

The workflow is [.github/workflows/deploy-windows.yml](../.github/workflows/deploy-windows.yml). It has only the `workflow_dispatch` trigger: pushes, pull requests, schedules and tags do not deploy. The job runs on the `golf-stats-prod` runner, requests only repository `contents: read`, uses the `production` environment, and has a 30-minute timeout. A concurrency group prevents simultaneous production deployments; additional runs wait rather than cancel the active deployment.

1. Review and merge the intended changes to the approved deployment branch. Verify backups, runner status, IIS configuration, SQL permissions and service health first.
2. In **Actions > Deploy Golf Stats to IIS**, select **Run workflow**, choose the approved branch, and set the inputs:

   | Input | Default | Guidance |
   | --- | --- | --- |
   | `sql_server` | `.\SQLEXPRESS` | SQL instance to deploy against. Use `.` for a default local instance, or the appropriate server/instance name. |
   | `seed_sample_data` | `false` | Leave off for production. When enabled, inserts the repository's sample records. |
   | `trust_server_certificate` | `false` | Enable only for a trusted self-signed SQL certificate. Prefer a correctly installed SQL TLS certificate. |

3. Start the run. If GitHub pauses for the `production` environment, an authorized reviewer approves it. The job then checks Python 3.12 x64, ODBC Driver 18, `sqlcmd`, the local IIS site and HTTPS binding, Windows Authentication, URL Rewrite, ARR proxying, the existing service and SQL Server Express version/connectivity.
4. After checks pass, the deploy script applies `database/01_create_schema.sql`, optionally seeds sample data, copies the website, writes Windows-authenticated SQL settings, installs Python requirements, restarts Waitress and checks the configured HTTPS health URL.
5. Review the complete job log in the GitHub Actions run. Then perform the client-side acceptance tests below.

### Troubleshooting the Workflow

| Symptom | Checks |
| --- | --- |
| Run stays queued | Confirm the runner service is online and has all four required labels: `self-hosted`, `Windows`, `X64` and `golf-stats-prod`. |
| Run waits for approval | An authorized reviewer must approve the `production` environment deployment. Check its branch restrictions if approval cannot proceed. |
| Missing GitHub variable | Configure all four `GOLF_*` variables on the `production` environment, not only at repository level. |
| Chocolatey package install returns 503 | The bootstrap retries transient feed errors. If it still fails, inspect `C:\ProgramData\chocolatey\logs\chocolatey.log`, check server access to the configured Chocolatey feed, then rerun the bootstrap. |
| SQL connection or schema failure | Check the selected instance, SQL Server service, runner Windows identity, Windows Authentication and schema/database permissions. The deploy script requires SQL Server Express. |
| Health check fails with 401/403 | Allow the runner service identity through IIS Windows Authentication/authorization and verify the HTTPS URL and certificate. |
| Health check fails with 500 or times out | Check Waitress service state/logs, its database identity/permissions, `config.json`, SQL TLS trust and SQL connectivity. |
| Python package install fails | Verify the runner has network access to the configured Python package index or an approved internal mirror. |

The workflow does not take a database backup or automatically roll back an application or schema deployment. Confirm that a current backup can be restored before deploying. The app still has no per-user roles: IIS Windows Authentication gates access, but every authorized user can use the app's write operations and database settings. Complete the deployment security gate above before exposing it to a shared audience.

## Acceptance Tests

Run these checks from a client machine, not only on the server:

- The HTTPS site loads, the certificate is valid, and HTTP redirects to HTTPS if configured.
- Unauthenticated users cannot load the site or call any `/api` route; authorized users can access only the intended data and operations.
- The overview, players, courses, rounds, reports and photos load correctly.
- Add a test player/course/round, update course details, and upload/remove a photo; verify each change in SQL Server. Remove test data using an approved method.
- `/api/database/info` reports the expected SQL instance and database. Check Express data-file size and confirm the scheduled backup is running.
- The Waitress listener is reachable only from the server itself, while the IIS site is reachable on the intended HTTPS binding.
- Restart the Windows server and verify both services return without an interactive login.

## Operations and Rollback

- Schedule full database backups to storage outside the SQL data directory. Monitor backup success, disk space, SQL Express's 10 GB data-file limit and photo growth. Perform a restore test before relying on the backup.
- Back up the application release and its protected configuration separately. Do not put credentials in source control or deployment logs.
- Record the deployed code version, Python version, ODBC driver version, dependency lock, SQL version and configuration location.
- To roll back, stop the Waitress service, restore the previous application release and compatible configuration, restart the service, and verify the acceptance checks. Restore a database backup only when the release changed the schema or the data itself must be recovered; coordinate this with users because restoring replaces newer database changes.

## Current Repository Notes

- [website/app.py](../website/app.py) starts Flask's development server on `127.0.0.1:5001` when run directly. The IIS deployment should instead launch the WSGI application object (`app:app`) with Waitress.
- [website/requirements.txt](../website/requirements.txt) includes Flask, pyodbc and Waitress, but does not pin versions. Pin and test dependency versions before production deployment.
- [website/README.md](../website/README.md) says settings are for local testing and notes the plaintext password storage. Resolve that before enabling the Settings page on a shared IIS site.
- [documentation/site-documentation.md](site-documentation.md) currently describes the server as local-only and development-server-only; update it when the production deployment changes are implemented.
