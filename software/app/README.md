# ThermoScan Mobile App

Flutter mobile application for ThermoScan, a photovoltaic module monitoring and localized cleaning system.

The application provides role-based access to authentication, mandatory temporary password change, profile management, System Admin company administration, and Manager user and client administration.

## Technology Stack

- **Language:** Dart (`3.11+`)
- **Framework:** Flutter (`Material 3`)
- **State Management:** Riverpod (`flutter_riverpod`)
- **HTTP Client:** Dio (`dio`) with automatic Bearer token injection and 401 refresh token rotation
- **Navigation & Route Guards:** `go_router`
- **Secure Credential Storage:** `flutter_secure_storage`
- **Typography:** `google_fonts` (`Chakra Petch`, `IBM Plex Sans`, `IBM Plex Mono`)

## Project Structure

The Flutter project is located in `software/app/thermoscan/` and follows a feature-first architecture:

```text
software/app/thermoscan/lib/
├── core/
│   ├── config/               # Environment & API base URL configuration
│   ├── network/              # Dio client, auth interceptor, and API error mapping
│   ├── router/               # GoRouter configuration and role/session redirect guards
│   ├── storage/              # Secure storage for tokens and cached session user
│   ├── theme/                # Design system colors, typography, and Material theme
│   └── widgets/              # Reusable UI components (logo, buttons, inputs, chips, top bar, modals)
├── features/
│   ├── auth/                 # Splash, login, mandatory password change, and session state
│   ├── companies/            # System Admin company list, creation, details, and Manager password reset
│   ├── modules/              # PV modules list, 5-step installation wizard, overview, configuration, interval log, and access control
│   ├── profile/              # Own profile editing, password change, and Technician responsible Managers
│   └── users/                # Manager hub, user & client lists, user/client creation, status toggle, and password reset
└── main.dart                 # Application entrypoint
```

## Implemented Features & Screens

### Authentication & Account Lifecycle
- **Splash & Session Bootstrap:** Restores saved credentials on startup, validates the session via `GET /api/v1/auth/me`, and refreshes expired access tokens automatically.
- **Sign In:** Email and password authentication with clear error banners (including specific feedback when attempting to sign in with a deactivated account via `ACCOUNT_INACTIVE`).
- **Mandatory Password Change:** Enforced whenever `must_change_password = true` (after initial account creation or an administrative password reset). Blocks navigation to any other route until completed.
- **User Profile:** Allows any authenticated user to view their role and company metadata, update their own `name` and `email`, change their password, and sign out. For `technician` users, displays a read-only **Responsible Managers** card listing the Managers assigned to them.

### System Admin (`system_admin`)
- **Companies Home:** Searchable and refreshable list of registered companies with active status indicators and creation date.
- **Create Company:** Single-step creation of a new company and its initial default Manager account, displaying the generated one-time temporary password in a copyable modal.
- **Company Details:** Displays company overview metadata and its registered Manager accounts, allowing the System Admin to reset any Manager's password into a new one-time temporary password.

### Manager (`manager`)
- **Company Administration Hub:** Quick-access dashboard for managing Company Users and Clients.
- **Company Users Management:** Searchable list of company users with role filter chips (`All`, `Managers`, `Technicians`, `Clients`), visual highlight (`You` badge) for the currently signed-in Manager, user creation (`manager`, `technician` with multi-select responsible Managers, or `client`), account activation/deactivation for Technicians and Clients, and temporary password resets.
- **Dedicated Clients Management:** Focused list and creation workflow for `client` accounts with search, status filter (`All`, `Active Only`, `Inactive`), status toggle, and temporary password reset.

### Technician (`technician`) & Client (`client`)
- **PV Modules Home:** Searchable and filterable list of accessible modules (`Active`, `Pending Config`), showing MAC address, array summary, scan interval, and relationship badge.
- **5-Step Module Installation Wizard (`technician` only):**
  1. Module name, MAC address validation, and selection of responsible Managers from all active company Managers (supports saving a draft in `pending_configuration` to resume later).
  2. Installation site location (GPS coordinate capture and manual review/editing of latitude, longitude, and elevation).
  3. Surface orientation (sensor capture and manual entry of azimuth and tilt angle, preserving `SENSOR`/`MANUAL` source tags).
  4. Photovoltaic array configuration (dimensions, panel count, spacing, minimum solar angle, and inspection interval).
  5. Full review and confirmation.
- **Module Overview & Configuration:** Role-aware module configuration editing (geometry/location for Manager and Installer Technician; minimum solar angle for Manager and any authorized Technician; inspection interval for Manager, Installer Technician, and assigned Client), inspection interval audit history, Manager access/responsibility control, and Client per-module operational email notification toggle.
- **Module Details & Radiometric Scan Card (`SCR-10`):**
  - Displays the active or latest inspection summary, including the firmware-computed baseline temperature (`baseline_temperature_c`).
  - **No Frame Fusion / Blending:** Raw MLX90640 thermal frames (32×24) are rendered directly at their physical $X$ coordinate (`x_position_cm`) on the panel canvas ruler without artificial linear blending or stitched single matrices.
  - **Exclusive Hotspot Highlight:** Only firmware-confirmed hotspots (`anomaly_events` with $\ge 2$ confirming frames and spatial overlap) receive visual warning badges, boundary markers, and coordinate callouts. Unconfirmed candidates are not highlighted as anomalies.
  - **Graceful Handling of Missing Electrical Metrics:** Displays `N/A` when DC voltage, current, or power readings are null or unavailable due to INA219 sensor faults.
- **Module Measurements & Inspection Explorer (`SCR-11`):**
  - **Paginated Active Inspection Measurements:** Queries `GET /api/v1/modules/{id}/inspections/{inspectionId}/measurements?page=1&limit=10` ordered by `x_position_cm ASC`.
  - Interactive pagination controls (Previous / Next, page counter, total item count).
  - Individual step telemetry tiles with $X$ position, peak temperature, INA219 electrical readings (with `N/A` fallback for null values), and confirmed hotspot indicator.
  - Chronological session grouping for historical inspection logs with expandable session cards and filter pills (`All`, `Hotspots`, `Normal`).

## Environment Configuration

By default, the app automatically selects the local backend URL according to the runtime platform:
- **Android Emulator:** `http://10.0.2.2:8080/api/v1`
- **Desktop / iOS Simulator / Web:** `http://localhost:8080/api/v1`

You can override the backend URL at build or run time using `--dart-define`:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:8080/api/v1
```

## Running and Testing

```bash
cd software/app/thermoscan

# Install dependencies
flutter pub get

# Static analysis
flutter analyze

# Run widget & flow tests
flutter test

# Launch on connected device or emulator
flutter run
```
