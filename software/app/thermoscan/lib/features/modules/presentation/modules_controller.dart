import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/features/modules/data/module_repository.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';

final modulesListProvider =
    AsyncNotifierProvider.autoDispose<ModulesListNotifier, List<PvModule>>(
  ModulesListNotifier.new,
);

class ModulesListNotifier extends AutoDisposeAsyncNotifier<List<PvModule>> {
  @override
  Future<List<PvModule>> build() async {
    final repo = ref.watch(moduleRepositoryProvider);
    return repo.listModules();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      final repo = ref.read(moduleRepositoryProvider);
      return repo.listModules();
    });
  }
}

final moduleDetailsProvider =
    FutureProvider.autoDispose.family<ModuleDetails, String>((ref, moduleId) {
  final repo = ref.watch(moduleRepositoryProvider);
  return repo.getModuleDetails(moduleId);
});

final moduleIntervalLogsProvider = FutureProvider.autoDispose
    .family<List<IntervalChangeLogItem>, String>((ref, moduleId) {
  final repo = ref.watch(moduleRepositoryProvider);
  return repo.listIntervalChangeLogs(moduleId);
});

final companyManagersOptionsProvider =
    FutureProvider.autoDispose<List<ModuleManagerItem>>((ref) {
  final repo = ref.watch(moduleRepositoryProvider);
  return repo.listCompanyManagers();
});

final companyClientsOptionsProvider =
    FutureProvider.autoDispose<List<ModuleClientItem>>((ref) {
  final repo = ref.watch(moduleRepositoryProvider);
  return repo.listCompanyClientOptions();
});

final moduleMeasurementsProvider = FutureProvider.autoDispose
    .family<List<ModuleMeasurement>, String>((ref, moduleId) {
  final repo = ref.watch(moduleRepositoryProvider);
  return repo.listMeasurements(moduleId: moduleId);
});

final moduleCleaningsProvider = FutureProvider.autoDispose
    .family<List<ModuleCleaning>, String>((ref, moduleId) {
  final repo = ref.watch(moduleRepositoryProvider);
  return repo.listCleanings(moduleId: moduleId);
});

final moduleThermalMapProvider = FutureProvider.autoDispose
    .family<ModuleThermalMap?, String>((ref, moduleId) {
  final repo = ref.watch(moduleRepositoryProvider);
  return repo.getLatestThermalMap(moduleId: moduleId);
});
