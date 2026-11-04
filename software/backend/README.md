# ThermoScan Backend

REST API for ThermoScan, a photovoltaic module monitoring and localized cleaning system.

The backend manages authentication, session tokens, multi-tenant company isolation, role-based access control, and user administration.

## Technology Stack

- **Language:** Go (`1.25+`)
- **HTTP Router:** Chi (`v5`)
- **Database:** PostgreSQL (`16`)
- **Database Driver:** `pgx/v5`
- **Database Access:** `sqlc` (typed Go code generated from SQL queries)
- **Authentication:** JWT access tokens (`HS256`, 15 min TTL) + opaque rotating refresh tokens (30 days TTL, stored hashed with SHA-256)
- **Password Storage:** `bcrypt` (`cost 12`)
- **Deployment:** Docker and Docker Compose

## Project Structure

```text
software/backend/
├── cmd/api/                  # Application entrypoint and HTTP server bootstrap
├── db/
│   ├── migrations/           # SQL schema migrations
│   └── queries/              # sqlc SQL query definitions
├── internal/
│   ├── auth/                 # Authentication, JWT/refresh tokens, password management, and middleware
│   ├── bootstrap/            # Initial System Admin account seeding
│   ├── company/              # System Admin company & initial Manager administration
│   ├── config/               # Environment variable configuration loader
│   ├── db/                   # sqlc-generated database access layer
│   ├── httpapi/              # Chi router assembly, CORS, and integration tests
│   ├── httpjson/             # Standardized JSON response and error helpers
│   ├── module/               # Module installation, configuration, interval logs, and access control
│   └── user/                 # Manager company user & client administration
└── sqlc.yaml                 # sqlc code generation configuration
```

## Companies and Access Control

ThermoScan enforces strict company-based data isolation and role-based access control across four roles:

- **System Admin (`system_admin`):** Operates outside company scope (`company_id = NULL`). Creates and views companies, provisions each company's initial default Manager, and resets Manager passwords into temporary passwords.
- **Manager (`manager`):** Operates strictly within their own `company_id`. Creates and lists company users (`manager`, `technician`, `client`), links Technicians to responsible Managers, activates/deactivates Technicians and Clients, and resets Technician and Client passwords.
- **Technician (`technician`):** Operates within their own `company_id` and is associated with one or more responsible Managers (`manager_technicians`).
- **Client (`client`):** Operates within their own `company_id`.

### Key Security Rules Enforced by the Backend

1. **Mandatory Password Change (`PASSWORD_CHANGE_REQUIRED`):** Users provisioned with a temporary password or whose password was reset have `must_change_password = true`. Until they complete `POST /api/v1/auth/change-password`, the authentication middleware blocks all protected endpoints except `GET /api/v1/auth/me`, `POST /api/v1/auth/change-password`, and `POST /api/v1/auth/logout`.
2. **Inactive Account Rejection (`ACCOUNT_INACTIVE`):** Attempting to sign in with valid credentials for a deactivated user account (or an inactive company) returns `403 Forbidden` with code `ACCOUNT_INACTIVE`. Active sessions for deactivated accounts are also immediately rejected by the authentication middleware.
3. **Session Revocation:** Changing a password, resetting a user's password, or deactivating a user immediately revokes all active refresh tokens for that user.
4. **Manager Protection Rules:** A Manager cannot deactivate or reset the password of another Manager (`is_default_manager` and peer Manager accounts are protected from Manager-level status/password mutations).

## Implemented API Endpoints

All endpoints are prefixed with `/api/v1` (except `/health`).

### Health

| Method | Path | Auth | Description |
| :--- | :--- | :--- | :--- |
| `GET` | `/health` (or `/api/v1/health`) | Public | Liveness and database connectivity check |

### Authentication & Profile

| Method | Path | Auth | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/auth/login` | Public | Authenticate with email and password; returns `access_token`, `refresh_token`, and `user` |
| `POST` | `/api/v1/auth/refresh` | Public | Rotate refresh token and issue a new token pair |
| `POST` | `/api/v1/auth/logout` | Public | Revoke the provided refresh token session |
| `POST` | `/api/v1/auth/change-password` | Bearer JWT | Change own password, clear `must_change_password`, and rotate session |
| `GET` | `/api/v1/auth/me` | Bearer JWT | Retrieve authenticated user profile (includes `responsible_managers` for Technicians) |
| `PATCH` | `/api/v1/auth/me` | Bearer JWT | Update authenticated user's own `name` and `email` |

### System Admin — Companies & Managers

| Method | Path | Role | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/companies` | `system_admin` | Create a company and its initial default Manager with a generated one-time temporary password |
| `GET` | `/api/v1/companies` | `system_admin` | List registered companies with pagination (`limit`, `offset`) |
| `GET` | `/api/v1/companies/{companyID}` | `system_admin` | Retrieve company details and its Manager accounts |
| `POST` | `/api/v1/companies/{companyID}/managers/{userID}/reset-password` | `system_admin` | Reset a company Manager's password to a new temporary password |

### Manager — Company Users & Clients

| Method | Path | Role | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/users` | `manager` | Create a `manager`, `technician`, or `client` in the caller's company with a generated temporary password |
| `GET` | `/api/v1/users` | `manager` | List users in the caller's company (`limit`, `offset`, optional `role` filter) |
| `GET` | `/api/v1/users/{userID}` | `manager` | Retrieve user details within the caller's company (includes `manager_ids` for Technicians) |
| `PATCH` | `/api/v1/users/{userID}/status` | `manager` | Activate or deactivate a `technician` or `client` in the caller's company |
| `POST` | `/api/v1/users/{userID}/reset-password` | `manager` | Reset a `technician` or `client` password to a new temporary password |
| `PUT` | `/api/v1/users/{userID}/managers` | `manager` | Replace the responsible Managers assigned to a `technician` |

### PV Modules, Installation, Configuration & Access Control

| Method | Path | Role | Description |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/v1/modules/company-managers` | `technician`, `manager` | List all active Managers in the caller's company for installation assignment |
| `POST` | `/api/v1/modules` | `technician` | Register a new module (`pending_configuration` draft or `active` complete configuration) with MAC and responsible Managers |
| `GET` | `/api/v1/modules` | `manager`, `technician`, `client` | List modules accessible to the caller within their company |
| `GET` | `/api/v1/modules/{moduleID}` | `manager`, `technician`, `client` | Retrieve module details, caller permissions, and responsible Managers |
| `PATCH` | `/api/v1/modules/{moduleID}/configuration` | `manager`, `technician`, `client` | Update module configuration fields according to the caller's module-level permissions and log interval changes |
| `GET` | `/api/v1/modules/{moduleID}/interval-logs` | `manager`, `technician`, `client` | List inspection interval change history for an accessible module |
| `PUT` | `/api/v1/modules/{moduleID}/managers` | `manager` | Update responsible Managers for a module (minimum 1 active Manager required) |
| `PUT` | `/api/v1/modules/{moduleID}/technicians/{technicianID}` | `manager` | Grant or revoke (`can_view`) Technician access to a module (including installer) |
| `PUT` | `/api/v1/modules/{moduleID}/clients` | `manager` | Update Clients assigned to a module |
| `PATCH` | `/api/v1/modules/{moduleID}/email-preferences` | `client` | Enable or disable operational email notifications for an assigned module |
| `GET` | `/api/v1/modules/{moduleID}/latest-inspection` | `manager`, `technician`, `client` | Retrieve latest inspection summary, baseline temperature, and confirmed anomalies |
| `GET` | `/api/v1/modules/{moduleID}/inspections/{inspectionId}/measurements` | `manager`, `technician`, `client` | Paginated raw measurement list (`?page=1&limit=10`, ordered by `x_position_cm ASC`) |

### Device Management, Telemetry & Inspection Lifecycle

These endpoints are used by the physical ESP32 firmware (authenticated via Bearer `device_token` issued at claim) and authorized users:

| Method | Path | Auth | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/devices/claim` | Public | Physical pairing by MAC address; issues unique `device_token` (`dev_sec_...`) |
| `POST` | `/api/v1/devices/{moduleId}/device-ping` | Device Token / JWT | Periodic heartbeat, binary water sensor state (`water_available`), homing limits check, and radiometer status |
| `GET` | `/api/v1/devices/{moduleId}/configuration` | Device Token / JWT | Retrieve latest server configuration version for physical NVS sync |
| `POST` | `/api/v1/devices/{moduleId}/configuration/ack` | Device Token / JWT | Acknowledge configuration applied to NVS; transitions status to `synced` (returns 409 if version is stale) |
| `POST` | `/api/v1/devices/{moduleId}/telemetry` | Device Token / JWT | Ingest raw radiometric measurements in streaming (1 per 2 cm step) or batches (max 5 items) |
| `POST` | `/api/v1/devices/{moduleId}/inspections/{inspectionSourceEventId}/finalize` | Device Token / JWT | Finalize inspection session with baseline temperature and confirmed hotspots |
| `POST` | `/api/v1/devices/{moduleId}/cleanings` | Device Token / JWT | Ingest cleaning actuation report (water consumption, pump duration, attempt, status) |

#### Telemetry Ingestion Contract (`POST /api/v1/devices/{moduleId}/telemetry`)

- **Payload Structure:**
  ```json
  {
    "inspection_source_event_id": "90000000-0000-0000-0000-000000000001",
    "inspection_type": "scheduled",
    "scheduled_for": "2026-11-04T08:00:00Z",
    "batch": [
      {
        "source_event_id": "a1000000-0000-0000-0000-000000000001",
        "measured_at": "2026-11-04T08:00:02Z",
        "x_position_cm": 2.0,
        "max_temperature_c": 35.4,
        "voltage_v": 18.5,
        "current_a": 4.2,
        "power_w": 77.7,
        "thermal_frame": [35.0, null, 35.2, "... (768 items total)"]
      }
    ]
  }
  ```
- **Batch Size:** Maximum of **5** measurement items per request.
- **Raw Measurements Only:** Medição bruta **NÃO** contém `hotspot_detected`. O conceito de candidato por medição individual não existe neste fluxo.
- **Nullable Electrical Readings:** `voltage_v`, `current_a`, and `power_w` are *nullable* (`null` when the INA219 sensor fails, disconnects, or is not populated). They must never be converted into fictional zeros.
- **Thermal Frame:** Exactly 768 float positions (32 columns × 24 rows) with `null` strictly representing invalid/dead sensor pixels.
- **Memory Management:** As soon as the backend responds with `200 OK`, the firmware releases the 768-pixel frame from RAM, avoiding buffer overflow on the ESP32.
- **Scheduled Time Fallback:** If `scheduled_for` is omitted (e.g. firmware lacking RTC sync), the backend falls back to `started_at` automatically.
- **Strict Idempotency:** Resending the same `source_event_id` with identical content succeeds idempotently (`200 OK` with existing records preserved). Any payload with the same `source_event_id` but divergent data is rejected with `409 Conflict`.

#### Inspection Finalization Contract (`POST /api/v1/devices/{moduleId}/inspections/{inspectionSourceEventId}/finalize`)

- **Payload Structure:**
  ```json
  {
    "finished_at": "2026-11-04T08:05:00Z",
    "baseline_temperature_c": 35.2,
    "confirmed_hotspots": [
      {
        "source_event_id": "b1000000-0000-0000-0000-000000000001",
        "global_x_position_cm": 6.0,
        "row_index": 12,
        "max_temperature_c": 52.8,
        "detected_at": "2026-11-04T08:02:15Z",
        "origin_measurement_event_id": "a1000000-0000-0000-0000-000000000003",
        "confirming_event_ids": [
          "a1000000-0000-0000-0000-000000000003",
          "a1000000-0000-0000-0000-000000000004"
        ]
      }
    ]
  }
  ```
- **Baseline Temperature:** Firmware calculates `baseline_temperature_c` as the median of all valid pixel temperatures captured across the entire scan.
- **Spatial Overlap Confirmation:** A hotspot is confirmed **exclusively by the firmware** if a candidate ($T \ge \text{baseline} + 10^\circ\text{C}$) persists across at least 2 consecutive acquisitions (step $2\text{ cm}$, optical overlap $60\%$, spatial tolerance $\le 0.5\text{ cm}$).
- **Hotspot Confirmation Constraints:** `confirming_event_ids` must contain $\ge 2$ unique measurement IDs belonging to the same inspection, and must include `origin_measurement_event_id`.
- **Verification Inspection (`type = "verification"`):** Triggered after cleaning (`cleaning_operation_id` required, which must have `pump_actuated = true` and `post_cleaning_result = "pending"`). The required 30-minute thermal settling wait and valid solar window are enforced by the firmware. Finalization atomically updates the cleaning operation (`resolved` vs `unresolved`) and the anomaly lifecycle (`open`, `resolved`, or `unresolved` with retry budget).

### Architectural Separation of Responsibilities

```text
┌────────────────────────┐      ┌────────────────────────┐      ┌────────────────────────┐
│     ESP32 Firmware     │      │      Go API Server     │      │   Flutter Mobile App   │
├────────────────────────┤      ├────────────────────────┤      ├────────────────────────┤
│ • Autonomous scan      │      │ • HTTPS Authentication │      │ • Authorized Admin/UI  │
│ • Step 2cm movement    │      │ • Strict idempotency   │      │ • Individual frames    │
│ • Streams raw frames   │ ────>│ • Persistence in PG    │ ────>│   rendered at X coord  │
│ • Frees RAM per frame  │ REST │ • Exposes telemetry    │ REST │ • No frame stitching   │
│ • Computes baseline    │      │ • Does NOT stitch maps │      │ • Exclusive highlight   │
│ • Confirms hotspots    │      │ • Does NOT do overlap  │      │   of confirmed spots   │
│ • Enforces water inter-│      │ • Does NOT confirm     │      │ • Displays N/A when    │
│   locks & 30min wait   │      │   hotspots             │      │   electricals are null │
└────────────────────────┘      └────────────────────────┘      └────────────────────────┘
```

- **Firmware:** Captures, streams raw data, calculates inspection baseline, identifies candidates, confirms hotspots via multi-frame spatial overlap, and finalizes sessions. Enforces safety interlocks locally.
- **Backend:** Validates input, stores measurements and inspection state idempotently, and exposes data over REST. **Does NOT** calculate baseline, compare consecutive frames, calculate overlap, stitch composite maps, or confirm hotspots.
- **Mobile:** Renders raw frames at their respective X coordinates. **Does NOT** merge thermal matrices, calculate overlap, recalculate baseline, or infer hotspots. Hotspot visual highlights are strictly driven by backend-confirmed `anomaly_events`. Display of missing electrical metrics shows `N/A`.

### Standardized Error Format

All errors return a consistent JSON structure:

```json
{
  "error": {
    "code": "ACCOUNT_INACTIVE",
    "message": "this account is inactive. Contact your company Manager"
  }
}
```

Common error codes:
- `VALIDATION_ERROR` (`400`)
- `INVALID_CREDENTIALS` (`401`)
- `UNAUTHORIZED` (`401`)
- `ACCOUNT_INACTIVE` (`403`)
- `FORBIDDEN` (`403`)
- `PASSWORD_CHANGE_REQUIRED` (`403`)
- `NOT_FOUND` (`404`)
- `EMAIL_ALREADY_EXISTS` / `COMPANY_ALREADY_EXISTS` (`409`)
- `INTERNAL_ERROR` (`500`)

## Environment Variables

| Variable | Description | Default (Dev) |
| :--- | :--- | :--- |
| `PORT` | HTTP server port | `8080` |
| `DATABASE_URL` | PostgreSQL connection string | Required |
| `JWT_SECRET` | Secret key used to sign JWT access tokens | Required |
| `SYSTEM_ADMIN_EMAIL` | Initial System Admin email seeded on startup | Optional |
| `SYSTEM_ADMIN_PASSWORD` | Initial System Admin password seeded on startup | Optional |
| `SYSTEM_ADMIN_NAME` | Initial System Admin display name | `System Admin` |

## Running and Testing

### With Docker Compose (from `software/`)

```bash
cd software
sudo docker compose up -d --build
```

### Running Tests Locally

```bash
cd software/backend
go test -count=1 ./...
```
