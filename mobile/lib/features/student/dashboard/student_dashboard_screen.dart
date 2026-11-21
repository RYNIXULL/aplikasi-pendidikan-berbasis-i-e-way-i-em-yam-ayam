import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_cards.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/providers/app_providers.dart';

final studentDashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  try {
    final res = await ref
        .read(apiClientProvider)
        .dio
        .get<Map<String, dynamic>>(ApiPaths.studentDashboard);
    return (res.data?['data'] as Map<String, dynamic>?) ?? {};
  } on DioException catch (e) {
    throw AppFailure.fromDioError(e);
  }
});

class StudentDashboardScreen extends ConsumerWidget {
  const StudentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final asyncData = ref.watch(studentDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Halo, ${user?.displayName ?? user?.fullName ?? "Siswa"}'),
            Text(
              'Ruang Belajar Siswa',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(studentDashboardProvider),
        child: asyncData.when(
          loading: () => const LoadingState(message: 'Memuat beranda belajar...'),
          error: (err, _) => ErrorState(
            message: err is AppFailure ? err.message : err.toString(),
            onRetry: () => ref.invalidate(studentDashboardProvider),
          ),
          data: (data) {
            final summary = (data['summary'] as Map<String, dynamic>?) ?? {};
            final latestMaterials = (data['latestMaterials'] as List?) ?? const [];
            final upcoming = (data['upcomingAssessments'] as List?) ?? const [];

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatItem(
                          label: 'Kelas',
                          value: '${summary['classroomCount'] ?? 0}',
                          icon: LucideIcons.school,
                        ),
                        _StatItem(
                          label: 'Materi Selesai',
                          value: '${summary['completedMaterials'] ?? 0}',
                          icon: LucideIcons.circleCheck,
                        ),
                        _StatItem(
                          label: 'Rata-Rata',
                          value: '${summary['averageScore'] ?? 0}%',
                          icon: LucideIcons.award,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                PrimaryButton(
                  label: 'Gabung Kelas dengan Kode',
                  icon: LucideIcons.keyRound,
                  onPressed: () => context.go('/student/classes'),
                ),
                const SizedBox(height: 20),
                Text('Materi Terbaru', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                if (latestMaterials.isEmpty)
                  const EmptyState(
                    icon: LucideIcons.bookOpen,
                    title: 'Belum Ada Materi',
                    description: 'Bergabunglah ke kelas pengajar Anda untuk mulai belajar.',
                  )
                else
                  ...latestMaterials.whereType<Map>().map((raw) {
                    final m = Map<String, dynamic>.from(raw);
                    final content = (m['content'] as Map<String, dynamic>?) ?? {};
                    final cls = (m['classroom'] as Map<String, dynamic>?) ?? {};
                    final type = (content['contentType'] ?? 'SUMMARY').toString();
                    return ContentCard(
                      title: (m['title'] ?? '').toString(),
                      contentTypeLabel: type,
                      statusLabel: (cls['name'] ?? 'Kelas').toString(),
                      statusColor: AppColors.secondary,
                      subject: cls['subject']?.toString(),
                      onTap: () => context.go('/student/learning'),
                    );
                  }),
                const SizedBox(height: 16),
                Text('Tugas & Ujian Aktif', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                if (upcoming.isEmpty)
                  const EmptyState(
                    icon: LucideIcons.clipboardCheck,
                    title: 'Tidak Ada Tugas Mendesak',
                    description: 'Semua kuis dan ujian terbaru akan muncul di bagian ini.',
                  )
                else
                  ...upcoming.whereType<Map>().map((raw) {
                    final a = Map<String, dynamic>.from(raw);
                    final cls = (a['classroom'] as Map<String, dynamic>?) ?? {};
                    return ContentCard(
                      title: (a['title'] ?? '').toString(),
                      contentTypeLabel: (a['assessmentType'] ?? 'QUIZ').toString(),
                      statusLabel: 'TERBUKA',
                      statusColor: AppColors.primary,
                      subject: cls['subject']?.toString(),
                      onTap: () => context.go('/student/assignments'),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12)),
      ],
    );
  }
}
