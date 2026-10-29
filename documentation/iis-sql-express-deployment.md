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

### One-time GitHub and runner setup

Run the bootstrap from an elevated 64-bit PowerShell session on Windows Server. It uses `winget` to fetch packages, so ensure `winget` is available and the server can reach its configured source and package download locations:

```powershell
.\scripts\install-golf-stats-prerequisites.ps1
```

The script enables the IIS web, Windows Authentication and management features, installs Python 3.12 x64, ODBC Driver 18, `sqlcmd`, URL Rewrite and ARR from exact winget package IDs, then enables ARR proxying. It is safe to rerun: already-installed components are detected and skipped. If a reboot is required, restart before continuing. `sqlcmd` and ODBC are client tools/drivers only; this script does not install the SQL Server engine or create a database.

1. Install and register a self-hosted GitHub Actions runner on the Windows Server. Add the custom runner label `golf-stats-prod` in addition to the default `self-hosted`, `Windows` and `X64` labels. Run the runner as a dedicated deployment identity with only the local administrator and SQL deployment rights needed for this job. Add this identity to the IIS Windows Authentication allow-list so the workflow can call its HTTPS health endpoint.
2. Do not allow pull-request jobs or untrusted repository code to run on this production runner. Workflows execute with the runner identity's server and database permissions. Restrict who can edit workflows and start deployments.
3. Create a GitHub Environment named `production`. Require reviewer approval and restrict permitted deployment branches to the trusted release branch (for example, `main`). The workflow uses this environment as its approval gate.
4. Add these environment variables to `production`:

   | Variable | Example | Purpose |
   | --- | --- | --- |
   | `GOLF_DEPLOY_ROOT` | `C:\Apps\GolfStats` | Stable deployment root; the website is placed in its `website` subdirectory. |
   | `GOLF_SERVICE_NAME` | `GolfStatsWaitress` | Name of the pre-created Waitress Windows service. |
   | `GOLF_IIS_SITE_NAME` | `Golf Stats` | Existing IIS site name. |
   | `GOLF_HEALTH_URL` | `https://golf.example.org/api/database/info` | HTTPS health endpoint, reachable from the runner and authenticated with its Windows identity. |

5. Ensure the runner identity can connect to SQL Server with Windows Authentication, create `GolfStats` if it does not exist, and apply the schema objects on each deployment. This identity is separate from the Waitress service identity. Use a dedicated SQL deployment principal and grant only the permissions required for database creation and schema changes; do not use a personal login. The Waitress service identity needs its own runtime permissions on `GolfStats`.
6. Pre-create the Windows service using the dedicated Waitress service identity. Configure it for automatic startup and restart-on-failure, and set it to run `website\\.venv\\Scripts\\waitress-serve.exe --listen=127.0.0.1:8000 app:app` with its working directory set to `website`. The first workflow run expects the service to exist, though it will create the virtual environment if absent. Ensure the IIS reverse-proxy rule targets `http://127.0.0.1:8000/` and that the HTTPS health URL returns the app's JSON database information.

### Running a deployment

1. Review and merge the intended changes to the deployment branch. Confirm the production runner, IIS authorization, SQL permissions, and backups are ready.
2. In GitHub, select **Actions > Deploy Golf Stats to IIS > Run workflow** and choose the trusted branch. Enter the SQL instance. Keep **Insert the sample courses, players and rounds** unchecked for a real database; the schema script is run every deployment, while sample data is opt-in.
3. Approve the `production` environment deployment when prompted. The workflow validates Python 3.12 x64, the 64-bit ODBC Driver 18, `sqlcmd`, SQL Server Express version/connectivity, IIS HTTPS and Windows Authentication, URL Rewrite, ARR proxying, the configured service and required environment variables. Any failed prerequisite stops the deployment.
4. After preflight, it runs `01_create_schema.sql`, optionally runs `02_seed_sample_data.sql`, copies the website, writes Windows-authenticated SQL settings, installs the requirements, restarts the Waitress service and checks the HTTPS health endpoint against the expected SQL Server Express database.

The workflow is triggered only by `workflow_dispatch`; it has no push, pull-request, schedule or tag trigger. SQL connection uses the runner's Windows identity, so no SQL password is stored in GitHub. The optional certificate-trust input should only be enabled for a trusted self-signed SQL certificate; use a properly trusted certificate and leave it off otherwise.

The workflow does not provide automatic rollback or take a database backup. Confirm that a current backup exists before deploying schema changes and follow the rollback procedure above if the new app fails its health check. The app still has no per-user roles; IIS Windows Authentication gates access but every authorized user can use the app's write operations and database settings. Complete the deployment gate above before exposing the app to a shared audience.

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
