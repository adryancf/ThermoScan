import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/widgets/scaffold_with_bottom_nav_bar.dart';
import 'package:thermoscan/features/alerts/presentation/alerts_feed_screen.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/auth/presentation/login_screen.dart';
import 'package:thermoscan/features/auth/presentation/mandatory_password_change_screen.dart';
import 'package:thermoscan/features/auth/presentation/splash_screen.dart';
import 'package:thermoscan/features/companies/presentation/companies_home_screen.dart';
import 'package:thermoscan/features/companies/presentation/company_details_screen.dart';
import 'package:thermoscan/features/companies/presentation/create_company_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_access_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_cleanings_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_configuration_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_installation_wizard_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_measurements_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_overview_screen.dart';
import 'package:thermoscan/features/modules/presentation/modules_home_screen.dart';
import 'package:thermoscan/features/profile/presentation/profile_screen.dart';
import 'package:thermoscan/features/users/presentation/clients_list_screen.dart';
import 'package:thermoscan/features/users/presentation/company_users_screen.dart';
import 'package:thermoscan/features/users/presentation/create_client_screen.dart';
import 'package:thermoscan/features/users/presentation/create_user_screen.dart';
import 'package:thermoscan/features/users/presentation/manager_admin_home_screen.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen<AuthState>(
      authControllerProvider,
      (_, _) => notifyListeners(),
    );
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      // 1. While verifying stored session, stay on /splash (SCR-01)
      if (authState.status == AuthStatus.initializing) {
        return location == '/splash' ? null : '/splash';
      }

      // 2. Unauthenticated -> force /login (SCR-02)
      if (!authState.isAuthenticated) {
        return location == '/login' ? null : '/login';
      }

      final user = authState.user!;

      // 3. Mandatory password change enforcement -> force /change-password (SCR-03)
      if (user.mustChangePassword) {
        return location == '/change-password' ? null : '/change-password';
      }

      // 4. Authenticated & password already changed:
      // Redirect away from auth onboarding screens to role-appropriate home
      if (location == '/splash' ||
          location == '/login' ||
          location == '/change-password') {
        return user.homeRoute;
      }

      // 5. Role-based route guards
      if (location.startsWith('/admin') && !user.isSystemAdmin) {
        return user.homeRoute;
      }
      if (location.startsWith('/manager') && !user.isManager) {
        return user.homeRoute;
      }
      if (location == '/modules/install' && !user.isTechnician) {
        return user.homeRoute;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const MandatoryPasswordChangeScreen(),
      ),
      GoRoute(
        path: '/admin/companies',
        builder: (context, state) => const CompaniesHomeScreen(),
      ),
      GoRoute(
        path: '/admin/companies/new',
        builder: (context, state) => const CreateCompanyScreen(),
      ),
      GoRoute(
        path: '/admin/companies/:companyId',
        builder: (context, state) {
          final companyId = state.pathParameters['companyId'] ?? '';
          return CompanyDetailsScreen(companyId: companyId);
        },
      ),
      GoRoute(
        path: '/manager/users',
        builder: (context, state) => const CompanyUsersScreen(),
      ),
      GoRoute(
        path: '/manager/users/new',
        builder: (context, state) => const CreateUserScreen(),
      ),
      GoRoute(
        path: '/manager/clients',
        builder: (context, state) => const ClientsListScreen(),
      ),
      GoRoute(
        path: '/manager/clients/new',
        builder: (context, state) => const CreateClientScreen(),
      ),
      GoRoute(
        path: '/modules/install',
        builder: (context, state) => const ModuleInstallationWizardScreen(),
      ),
      GoRoute(
        path: '/modules/:moduleId/install',
        builder: (context, state) {
          final moduleId = state.pathParameters['moduleId'] ?? '';
          return ModuleInstallationWizardScreen(existingModuleId: moduleId);
        },
      ),
      GoRoute(
        path: '/modules/:moduleId/configuration',
        builder: (context, state) {
          final moduleId = state.pathParameters['moduleId'] ?? '';
          return ModuleConfigurationScreen(moduleId: moduleId);
        },
      ),
      GoRoute(
        path: '/modules/:moduleId/access',
        builder: (context, state) {
          final moduleId = state.pathParameters['moduleId'] ?? '';
          return ModuleAccessScreen(moduleId: moduleId);
        },
      ),

      // Primary authenticated tabs wrapped in persistent BottomNavigationBar shell
      ShellRoute(
        builder: (context, state, child) {
          return ScaffoldWithBottomNavBar(
            currentLocation: state.matchedLocation,
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const ModulesHomeScreen(),
          ),
          GoRoute(
            path: '/modules',
            builder: (context, state) => const ModulesHomeScreen(),
          ),
          GoRoute(
            path: '/modules/:moduleId',
            builder: (context, state) {
              final moduleId = state.pathParameters['moduleId'] ?? '';
              return ModuleOverviewScreen(moduleId: moduleId);
            },
          ),
          GoRoute(
            path: '/modules/:moduleId/measurements',
            builder: (context, state) {
              final moduleId = state.pathParameters['moduleId'] ?? '';
              return ModuleMeasurementsScreen(moduleId: moduleId);
            },
          ),
          GoRoute(
            path: '/modules/:moduleId/cleanings',
            builder: (context, state) {
              final moduleId = state.pathParameters['moduleId'] ?? '';
              return ModuleCleaningsScreen(moduleId: moduleId);
            },
          ),
          GoRoute(
            path: '/alerts',
            builder: (context, state) => const AlertsFeedScreen(),
          ),
          GoRoute(
            path: '/manager',
            builder: (context, state) => const ManagerAdminHomeScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
    ],
  );
});
