import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/core/storage/token_storage.dart';
import 'package:thermoscan/features/alerts/data/alerts_repository.dart';
import 'package:thermoscan/features/alerts/domain/alert_models.dart';
import 'package:thermoscan/features/auth/data/auth_repository.dart';
import 'package:thermoscan/features/auth/domain/auth_user.dart';
import 'package:thermoscan/features/companies/data/company_repository.dart';
import 'package:thermoscan/features/companies/domain/company_models.dart';
import 'package:thermoscan/features/modules/data/module_repository.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/users/data/user_repository.dart';
import 'package:thermoscan/features/users/domain/user_models.dart';
import 'package:thermoscan/main.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.initialUser}) : super(dio: Dio());

  final AuthUser? initialUser;

  @override
  Future<AuthUser> getMe() async {
    if (initialUser == null) {
      throw Exception('Unauthenticated');
    }
    return initialUser!;
  }
}

class _FakeCompanyRepository extends CompanyRepository {
  _FakeCompanyRepository() : super(dio: Dio());

  @override
  Future<List<Company>> listCompanies({int limit = 100, int offset = 0}) async {
    return const [
      Company(
        id: 'comp-1',
        name: 'SolTech Energy Ltd',
        address: 'São Paulo, BR',
        isActive: true,
        createdAt: '2026-10-29T10:00:00Z',
        updatedAt: '2026-10-29T10:00:00Z',
      ),
    ];
  }
}

class _FakeUserRepository extends UserRepository {
  _FakeUserRepository() : super(dio: Dio());

  @override
  Future<List<CompanyUser>> listUsers({
    String? role,
    int limit = 100,
    int offset = 0,
  }) async {
    return const [
      CompanyUser(
        id: 'mgr-1',
        companyId: 'comp-1',
        name: 'Elena Rostova',
        email: 'elena@soltech.io',
        role: 'manager',
        isActive: true,
        isDefaultManager: true,
        mustChangePassword: false,
        createdAt: '2026-10-29T10:00:00Z',
        updatedAt: '2026-10-29T10:00:00Z',
      ),
    ];
  }
}

class _FakeModuleRepository extends ModuleRepository {
  _FakeModuleRepository() : super(dio: Dio());

  @override
  Future<List<PvModule>> listModules({
    int limit = 100,
    int offset = 0,
  }) async {
    return const [
      PvModule(
        id: 'mod-1',
        companyId: 'comp-1',
        installerTechnicianId: 'tech-1',
        installerName: 'Marco Silva',
        installerEmail: 'marco@soltech.io',
        name: 'PV-001 Roof Array',
        macAddress: 'AA:BB:CC:DD:EE:01',
        isActive: true,
        monitoringStatus: 'active',
        inspectionIntervalDays: 7,
        createdAt: '2026-10-29T10:00:00Z',
        updatedAt: '2026-10-29T10:00:00Z',
        userRelationship: 'installer_technician',
        permissions: ModulePermissions(
          canEditGeometryAndLocation: true,
          canEditSolarAngle: true,
          canEditInterval: true,
          canManageAccess: true,
        ),
      ),
    ];
  }

  @override
  Future<ModuleDetails> getModuleDetails(String moduleId) async {
    const mod = PvModule(
      id: 'mod-1',
      companyId: 'comp-1',
      installerTechnicianId: 'tech-1',
      installerName: 'Marco Silva',
      installerEmail: 'marco@soltech.io',
      name: 'PV-001 Roof Array',
      macAddress: 'AA:BB:CC:DD:EE:01',
      isActive: true,
      monitoringStatus: 'active',
      inspectionIntervalDays: 7,
      createdAt: '2026-10-29T10:00:00Z',
      updatedAt: '2026-10-29T10:00:00Z',
      userRelationship: 'installer_technician',
      permissions: ModulePermissions(
        canEditGeometryAndLocation: true,
        canEditSolarAngle: true,
        canEditInterval: true,
        canManageAccess: true,
      ),
    );
    return const ModuleDetails(
      module: mod,
      responsibleManagers: [],
      companyManagers: [],
      companyTechnicians: [],
      companyClients: [],
    );
  }

  @override
  Future<List<ModuleMeasurement>> listMeasurements({
    required String moduleId,
    int limit = 50,
    int offset = 0,
  }) async {
    return const [
      ModuleMeasurement(
        id: 'meas-1',
        moduleId: 'mod-1',
        inspectionId: 'insp-1',
        sourceEventId: 'evt-1',
        measuredAt: '2026-11-02T14:15:00Z',
        xPositionCm: 12.4,
        baselineTemperatureC: 36.4,
        maxTemperatureC: 42.5,
        hotspotDetected: false,
        hotspotConfirmed: false,
        voltageV: 18.2,
        currentA: 4.1,
        powerW: 74.6,
        receivedAt: '2026-11-02T14:15:05Z',
      ),
    ];
  }

  @override
  Future<List<ModuleCleaning>> listCleanings({
    required String moduleId,
    int limit = 50,
    int offset = 0,
  }) async {
    return const [
      ModuleCleaning(
        id: 'cln-1',
        moduleId: 'mod-1',
        anomalyEventId: 'anom-1',
        sourceEventId: 'evt-2',
        targetXPositionCm: 12.0,
        pumpActuated: true,
        attemptNumber: 1,
        startedAt: '2026-11-02T06:00:14Z',
        endedAt: '2026-11-02T06:00:56Z',
        durationSeconds: 42.0,
        estimatedWaterVolumeMl: 180.0,
        status: 'completed',
        postCleaningResult: 'resolved',
        createdAt: '2026-11-02T06:00:14Z',
      ),
    ];
  }

  @override
  Future<DeviceStatus> getDeviceStatus({required String moduleId}) async {
    return const DeviceStatus(
      moduleId: 'mod-1',
      macAddress: 'AA:BB:CC:DD:EE:01',
      monitoringStatus: 'active',
      isConfigured: true,
      isOnline: true,
      waterAvailable: true,
      waterStatus: 'available',
      limitsCheckPassed: true,
      thermalSensorActive: true,
    );
  }

  @override
  Future<DeviceStatus> recordDevicePing({
    required String moduleId,
    bool waterAvailable = true,
  }) async {
    return const DeviceStatus(
      moduleId: 'mod-1',
      macAddress: 'AA:BB:CC:DD:EE:01',
      monitoringStatus: 'active',
      isConfigured: true,
      isOnline: true,
      waterAvailable: true,
      waterStatus: 'available',
      limitsCheckPassed: true,
      thermalSensorActive: true,
    );
  }
}

class _FakeAlertsRepository extends AlertsRepository {
  _FakeAlertsRepository() : super(dio: Dio());

  @override
  Future<AlertsSummary> listAlerts() async {
    return const AlertsSummary(
      total: 1,
      critical: 1,
      warning: 0,
      alerts: [
        FieldAlert(
          id: 'alert-1',
          moduleId: 'mod-1',
          moduleName: 'PV-001 Roof Array',
          severity: 'critical',
          type: 'hotspot_unresolved',
          title: 'Hotspot Unresolved: PV-001 Roof Array',
          description: 'Thermal anomaly confirmed at coordinate X=12.0 cm.',
          metaText: 'Delta: +15.3°C vs Baseline',
          xPositionCm: 12.0,
          deltaC: 15.3,
          createdAt: '2026-11-03T10:00:00Z',
        ),
      ],
    );
  }
}

void main() {
  testWidgets('Bootstraps from Splash to Login when no session exists',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        ],
        child: const ThermoScanApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Corporate Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
  });

  testWidgets('Enforces Mandatory Password Change (SCR-03) when required',
      (WidgetTester tester) async {
    final tokenStorage = InMemoryTokenStorage();
    await tokenStorage.saveTokens(
      accessToken: 'fake-access',
      refreshToken: 'fake-refresh',
    );

    const tempPassUser = AuthUser(
      id: 'u-1',
      companyId: 'comp-1',
      name: 'First Manager',
      email: 'mgr@soltech.io',
      role: 'manager',
      isActive: true,
      mustChangePassword: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokenStorage),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(initialUser: tempPassUser),
          ),
        ],
        child: const ThermoScanApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Set Permanent Password'), findsOneWidget);
    expect(find.text('Update Password'), findsOneWidget);
  });

  testWidgets('Routes authenticated Manager to Administration Home (SCR-24)',
      (WidgetTester tester) async {
    final tokenStorage = InMemoryTokenStorage();
    await tokenStorage.saveTokens(
      accessToken: 'fake-access',
      refreshToken: 'fake-refresh',
    );

    const managerUser = AuthUser(
      id: 'mgr-1',
      companyId: 'comp-1',
      name: 'Elena Rostova',
      email: 'elena@soltech.io',
      role: 'manager',
      isActive: true,
      mustChangePassword: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokenStorage),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(initialUser: managerUser),
          ),
          userRepositoryProvider.overrideWithValue(_FakeUserRepository()),
          moduleRepositoryProvider.overrideWithValue(_FakeModuleRepository()),
          alertsRepositoryProvider.overrideWithValue(_FakeAlertsRepository()),
        ],
        child: const ThermoScanApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Administration'), findsOneWidget);
    expect(find.text('PV Modules'), findsOneWidget);
    expect(find.text('Company Users'), findsOneWidget);
    expect(find.text('Clients'), findsOneWidget);
  });

  testWidgets('Routes authenticated Technician to Modules Home (SCR-09)',
      (WidgetTester tester) async {
    final tokenStorage = InMemoryTokenStorage();
    await tokenStorage.saveTokens(
      accessToken: 'fake-access',
      refreshToken: 'fake-refresh',
    );

    const techUser = AuthUser(
      id: 'tech-1',
      companyId: 'comp-1',
      name: 'Marco Silva',
      email: 'marco@soltech.io',
      role: 'technician',
      isActive: true,
      mustChangePassword: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokenStorage),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(initialUser: techUser),
          ),
          userRepositoryProvider.overrideWithValue(_FakeUserRepository()),
          moduleRepositoryProvider.overrideWithValue(_FakeModuleRepository()),
          alertsRepositoryProvider.overrideWithValue(_FakeAlertsRepository()),
        ],
        child: const ThermoScanApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('PV Modules'), findsOneWidget);
    expect(find.text('Install'), findsOneWidget);
    expect(find.text('PV-001 Roof Array'), findsOneWidget);
  });

  testWidgets('Routes authenticated System Admin to Companies Home (SCR-04)',
      (WidgetTester tester) async {
    final tokenStorage = InMemoryTokenStorage();
    await tokenStorage.saveTokens(
      accessToken: 'fake-access',
      refreshToken: 'fake-refresh',
    );

    const adminUser = AuthUser(
      id: 'admin-1',
      name: 'System Admin',
      email: 'admin@thermoscan.local',
      role: 'system_admin',
      isActive: true,
      mustChangePassword: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokenStorage),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(initialUser: adminUser),
          ),
          companyRepositoryProvider.overrideWithValue(_FakeCompanyRepository()),
        ],
        child: const ThermoScanApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Companies'), findsOneWidget);
    expect(find.text('SolTech Energy Ltd'), findsOneWidget);
    // Bottom navigation bar must be suppressed for System Admin
    expect(find.text('Modules'), findsNothing);
    expect(find.text('Alerts'), findsNothing);
  });

  testWidgets(
      'Bottom navigation bar allows switching between Modules, Alerts and Settings for Technician',
      (WidgetTester tester) async {
    final tokenStorage = InMemoryTokenStorage();
    await tokenStorage.saveTokens(
      accessToken: 'fake-access',
      refreshToken: 'fake-refresh',
    );

    const techUser = AuthUser(
      id: 'tech-1',
      companyId: 'comp-1',
      name: 'Marco Silva',
      email: 'marco@soltech.io',
      role: 'technician',
      isActive: true,
      mustChangePassword: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokenStorage),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(initialUser: techUser),
          ),
          userRepositoryProvider.overrideWithValue(_FakeUserRepository()),
          moduleRepositoryProvider.overrideWithValue(_FakeModuleRepository()),
          alertsRepositoryProvider.overrideWithValue(_FakeAlertsRepository()),
        ],
        child: const ThermoScanApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Tab 0: Modules
    expect(find.text('Modules'), findsWidgets);
    expect(find.text('PV-001 Roof Array'), findsOneWidget);

    // Tap Tab 1: Alerts
    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();

    expect(find.text('Active Field Alerts'), findsWidgets);
    expect(find.text('Hotspot Unresolved: PV-001 Roof Array'), findsOneWidget);

    // Tap Tab 2: Settings
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Profile Details'), findsOneWidget);
    expect(find.text('Responsible Managers'), findsOneWidget);

    // Tap back to Tab 0: Modules
    await tester.tap(find.text('Modules'));
    await tester.pumpAndSettle();

    expect(find.text('PV-001 Roof Array'), findsOneWidget);
  });

  testWidgets(
      'Bottom navigation bar allows switching for Manager and suppresses on Wizard',
      (WidgetTester tester) async {
    final tokenStorage = InMemoryTokenStorage();
    await tokenStorage.saveTokens(
      accessToken: 'fake-access',
      refreshToken: 'fake-refresh',
    );

    const managerUser = AuthUser(
      id: 'mgr-1',
      companyId: 'comp-1',
      name: 'Elena Rostova',
      email: 'elena@soltech.io',
      role: 'manager',
      isActive: true,
      mustChangePassword: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokenStorage),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(initialUser: managerUser),
          ),
          userRepositoryProvider.overrideWithValue(_FakeUserRepository()),
          moduleRepositoryProvider.overrideWithValue(_FakeModuleRepository()),
          alertsRepositoryProvider.overrideWithValue(_FakeAlertsRepository()),
        ],
        child: const ThermoScanApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Manager starts on Administration Home (SCR-24)
    expect(find.text('Administration'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Tap Modules tab
    await tester.tap(find.text('Modules'));
    await tester.pumpAndSettle();

    expect(find.text('PV-001 Roof Array'), findsOneWidget);

    // Tap Alerts tab
    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();

    expect(find.text('Active Field Alerts'), findsWidgets);

    // Tap Settings tab (returns to Manager administration)
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Company Users'), findsOneWidget);
  });

  testWidgets(
      'Bottom navigation bar is suppressed during Installation Wizard (SCR-16)',
      (WidgetTester tester) async {
    final tokenStorage = InMemoryTokenStorage();
    await tokenStorage.saveTokens(
      accessToken: 'fake-access',
      refreshToken: 'fake-refresh',
    );

    const techUser = AuthUser(
      id: 'tech-1',
      companyId: 'comp-1',
      name: 'Marco Silva',
      email: 'marco@soltech.io',
      role: 'technician',
      isActive: true,
      mustChangePassword: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokenStorage),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(initialUser: techUser),
          ),
          userRepositoryProvider.overrideWithValue(_FakeUserRepository()),
          moduleRepositoryProvider.overrideWithValue(_FakeModuleRepository()),
          alertsRepositoryProvider.overrideWithValue(_FakeAlertsRepository()),
        ],
        child: const ThermoScanApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Tap Install button on Modules Home
    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();

    // Verify wizard screen loaded
    expect(find.text('Install Module'), findsOneWidget);

    // Bottom Navigation Bar must be suppressed on wizard
    expect(find.text('Modules'), findsNothing);
    expect(find.text('Alerts'), findsNothing);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets(
      'Module details shows Radiometric Scan (SCR-10) and navigates to Measurements (SCR-11) and Cleanings (SCR-12)',
      (WidgetTester tester) async {
    final tokenStorage = InMemoryTokenStorage();
    await tokenStorage.saveTokens(
      accessToken: 'fake-access',
      refreshToken: 'fake-refresh',
    );

    const techUser = AuthUser(
      id: 'tech-1',
      companyId: 'comp-1',
      name: 'Marco Silva',
      email: 'marco@soltech.io',
      role: 'technician',
      isActive: true,
      mustChangePassword: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokenStorage),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(initialUser: techUser),
          ),
          userRepositoryProvider.overrideWithValue(_FakeUserRepository()),
          moduleRepositoryProvider.overrideWithValue(_FakeModuleRepository()),
          alertsRepositoryProvider.overrideWithValue(_FakeAlertsRepository()),
        ],
        child: const ThermoScanApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Tap module card to enter Module Overview (SCR-10)
    await tester.tap(find.text('PV-001 Roof Array'));
    await tester.pumpAndSettle();

    // Verify SCR-10 Radiometric Scan & Telemetry metrics
    expect(find.text('32×24 Sensor Interpolation'), findsOneWidget);
    expect(find.text('Discretização do Painel (Faixas de 5 cm)'), findsOneWidget);
    expect(find.text('Peak Temperature'), findsOneWidget);
    expect(find.text('DC Output Voltage'), findsOneWidget);
    expect(find.text('Active Power'), findsOneWidget);

    // Verify TabBar tabs
    expect(find.text('Visão Geral'), findsOneWidget);
    expect(find.text('Medições'), findsOneWidget);
    expect(find.text('Limpezas'), findsOneWidget);
    expect(find.text('Configuração'), findsOneWidget);

    // Tap Medições in TabBar (SCR-11)
    await tester.tap(find.text('Medições'));
    await tester.pumpAndSettle();

    expect(find.text('Telemetry History'), findsOneWidget);
    expect(find.text('Position X=12.4 cm • Baseline: 36.4°C'), findsOneWidget);
    expect(find.text('NORMAL'), findsOneWidget);

    // Tap Limpezas in TabBar (SCR-12)
    await tester.tap(find.text('Limpezas'));
    await tester.pumpAndSettle();

    expect(find.text('Actuator Wash Log'), findsOneWidget);
    expect(find.text('Wash Attempt #1 • Localized Traverse'), findsOneWidget);
    expect(find.text('VERIFIED POST-CLEAN'), findsOneWidget);
  });

  testWidgets(
      'ESP32 Hardware Handshake checklist (Abordagem A) displays verification steps and navigates to overview',
      (WidgetTester tester) async {
    final tokenStorage = InMemoryTokenStorage();
    await tokenStorage.saveTokens(
      accessToken: 'fake-access',
      refreshToken: 'fake-refresh',
    );

    const techUser = AuthUser(
      id: 'tech-1',
      companyId: 'comp-1',
      name: 'Marco Silva',
      email: 'marco@soltech.io',
      role: 'technician',
      isActive: true,
      mustChangePassword: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokenStorage),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(initialUser: techUser),
          ),
          userRepositoryProvider.overrideWithValue(_FakeUserRepository()),
          moduleRepositoryProvider.overrideWithValue(_FakeModuleRepository()),
          alertsRepositoryProvider.overrideWithValue(_FakeAlertsRepository()),
        ],
        child: const ThermoScanApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Navigate to module overview
    await tester.tap(find.text('PV-001 Roof Array'));
    await tester.pumpAndSettle();

    // Scroll into view and tap "Verify Hardware Handshake →"
    final handshakeFinder = find.text('Verify Hardware Handshake →');
    expect(handshakeFinder, findsOneWidget);
    await tester.ensureVisible(handshakeFinder);
    await tester.pumpAndSettle();
    await tester.tap(handshakeFinder);
    await tester.pumpAndSettle();

    // Verify Hardware Handshake Screen is open
    expect(find.text('Hardware Handshake'), findsOneWidget);
    expect(find.text('ESP32 Hardware Handshake'), findsOneWidget);
    expect(
      find.text('Verifying live Wi-Fi connectivity, safety interlocks and cloud sync'),
      findsOneWidget,
    );

    // Verify all 4 checklist steps are displayed
    expect(find.text('1. Configuration Sync'), findsOneWidget);
    expect(find.text('2. Wi-Fi & HTTPS REST Connection'), findsOneWidget);
    expect(find.text('3. Binary Water Level Sensor'), findsOneWidget);
    expect(find.text('4. Hardware Interlocks & Radiometer'), findsOneWidget);

    // Tap View Module Overview escape button
    final overviewBtnFinder = find.text('View Module Overview');
    await tester.ensureVisible(overviewBtnFinder);
    await tester.pumpAndSettle();
    await tester.tap(overviewBtnFinder);
    await tester.pumpAndSettle();

    // Verify return to Module Overview
    expect(find.text('Visão Geral'), findsOneWidget);
    expect(find.text('PV-001 Roof Array'), findsOneWidget);
  });
}
