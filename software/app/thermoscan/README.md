# ThermoScan (`thermoscan`)

Flutter mobile client for the ThermoScan photovoltaic module monitoring and localized cleaning system.

## Architecture & Stack

- **State Management:** `flutter_riverpod`
- **Routing:** `go_router` with reactive authentication, mandatory password change, and role-based route guards
- **Networking:** `dio` with automatic JWT Bearer token attachment and transparent `/auth/refresh` token rotation on `401 Unauthorized`
- **Secure Storage:** `flutter_secure_storage`
- **Design System:** Custom ThermoScan visual identity (`lib/core/theme/` and `lib/core/widgets/`) using `Chakra Petch`, `IBM Plex Sans`, and `IBM Plex Mono`

## Implemented Modules

- **`lib/core/`**: API configuration, Dio client & error handling (`ACCOUNT_INACTIVE`, `PASSWORD_CHANGE_REQUIRED`, etc.), secure token storage, theme tokens, and shared widgets (`ThermoScanLogo`, `AppPrimaryButton`, `AppSecondaryButton`, `AppDestructiveButton`, `AppTextField`, `StatusChip`, `RoleBadge`, `ThermoScanTopBar`, `TemporaryPasswordModal`).
- **`lib/features/auth/`**:
  - Splash screen with automatic session restoration (`GET /api/v1/auth/me`)
  - Login screen with email/password validation and backend error mapping
  - Mandatory password change screen (`POST /api/v1/auth/change-password`)
  - Profile screen (`PATCH /api/v1/auth/me`, password update, logout, and read-only **Responsible Managers** card for Technicians)
  - Role workspace screen for Technician and Client accounts
- **`lib/features/companies/`** (`system_admin`):
  - Companies list with search and pull-to-refresh (`GET /api/v1/companies`)
  - Create Company + initial default Manager flow (`POST /api/v1/companies`)
  - Company Details & Manager password reset (`GET /api/v1/companies/{id}`, `POST /api/v1/companies/{id}/managers/{userId}/reset-password`)
- **`lib/features/users/`** (`manager`):
  - Company Administration home hub (with live counters for Modules, Managers, Technicians, and Clients)
  - Company Users list with search, role filtering, logged-in user indicator (`You`), status toggle, and password reset (`GET /api/v1/users`, `PATCH /api/v1/users/{id}/status`, `POST /api/v1/users/{id}/reset-password`)
  - Create User screen supporting `manager`, `technician` (with responsible Manager assignment), and `client` (`POST /api/v1/users`)
  - Dedicated Clients list and Create Client screen
- **`lib/features/modules/`** (`manager`, `technician`, `client`):
  - PV Modules home list (`SCR-09`) with search, status filter, and Technician installation entry point
  - 5-step Technician Module Installation Wizard (`SCR-16` to `SCR-20`) with draft save/resume support (`pending_configuration` -> `active`)
  - Module Overview & Radiometric Scan Card (`SCR-10`):
    - Displays inspection session details and baseline temperature (`baseline_temperature_c`).
    - Renders individual thermal frames (32×24) positioned at physical $X$ coordinates (`x_position_cm`) without frame fusion, blending, or stitched matrices.
    - Highlights **only** firmware-confirmed hotspots (`anomaly_events` verified across $\ge 2$ consecutive frames with 60% overlap); does not highlight unconfirmed candidates.
    - Treats missing/null INA219 electrical readings gracefully by rendering `N/A`.
  - Module Measurements & Inspection Explorer (`SCR-11`):
    - Paginated inspection measurements (`GET /api/v1/modules/{id}/inspections/{inspectionId}/measurements?page=1&limit=10` ordered by `x_position_cm ASC`).
    - Interactive page navigation (Previous/Next, page count, total items).
    - Detailed per-step telemetry tiles displaying $X$ coordinate, peak temperature, electrical metrics (`N/A` on sensor null), and confirmed anomaly indicators.
    - Chronological inspection session aggregator with filter pills (`All`, `Hotspots`, `Normal`).
  - Module Cleanings History (`SCR-12`): washing operations log with post-cleaning thermal verification status (`resolved`, `unresolved`, `pending`).
  - Role-aware Module Configuration and Inspection Interval Change History (`SCR-13`)
  - Manager Module Access & Responsible Managers screen (`SCR-14`)
  - Client operational email notification toggle (`SCR-28`)

## Development Commands

```bash
# Install packages
flutter pub get

# Run static analyzer
flutter analyze

# Execute widget tests
flutter test

# Run on Android Emulator (defaults to http://10.0.2.2:8080/api/v1)
flutter run

# Run with custom backend URL
flutter run --dart-define=API_BASE_URL=http://localhost:8080/api/v1
```
