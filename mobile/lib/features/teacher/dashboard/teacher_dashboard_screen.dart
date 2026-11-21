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

final teacherDashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  try {
    final res = await ref.read(apiClientProvider).dio.get<Map<String, dynamic>>(
          ApiPaths.teacherDashboard,
        );
    return (res.data?['data'] as Map<String, dynamic>?) ?? {};
  } on DioException catch (e) {
    throw AppFailure.fromDioError(e);
  }
});

class TeacherDashboardScreen extends ConsumerWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final asyncData = ref.watch(teacherDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Halo, ${user?.displayName ?? user?.fullName ?? "Pengajar"}'),
            Text(
              'Ruang Kerja Pengajar',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(teacherDashboardProvider),
        child: asyncData.when(
          loading: () => const LoadingState(message: 'Memuat ringkasan ruang kerja...'),
          error: (err, _) => ErrorState(
            message: err is AppFailure ? err.message : err.toString(),
            onRetry: () => ref.invalidate(teacherDashboardProvider),
          ),
          data: (data) {
            final metrics = (data['metrics'] as Map<String, dynamic>?) ?? {};
            final recentDocs = (data['recentDocuments'] as List?) ?? const [];
            final recentContents = (data['recentContents'] as List?) ?? const [];

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.55,
                  children: [
                    _KpiTile(
                      label: 'Dokumen Materi',
                      value: '${metrics['documentCount'] ?? 0}',
                      icon: LucideIcons.fileText,
                      color: AppColors.primary,
                    ),
                    _KpiTile(
                      label: 'Menunggu Review',
                      value: '${metrics['pendingDraftCount'] ?? 0}',
                      icon: LucideIcons.clipboardCheck,
                      color: AppColors.warning,
                    ),
                    _KpiTile(
                      label: 'Kelas Aktif',
                      value: '${metrics['classroomCount'] ?? 0}',
                      icon: LucideIcons.users,
                      color: AppColors.secondary,
                    ),
                    _KpiTile(
                      label: 'Perlu Penilaian',
                      value: '${metrics['pendingGradingCount'] ?? 0}',
                      icon: LucideIcons.fileCheck2,
                      color: AppColors.info,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: PrimaryButton(
                        label: 'Unggah Materi',
                        icon: LucideIcons.upload,
                        onPressed: () => context.go('/teacher/materials'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SecondaryButton(
                        label: 'Buat Konten AI',
                        icon: LucideIcons.cpu,
                        onPressed: () => context.go('/teacher/generator'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text('Dokumen Terbaru', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                if (recentDocs.isEmpty)
                  const EmptyState(
                    icon: LucideIcons.folderOpen,
                    title: 'Belum Ada Dokumen',
                    description: 'Unggah PDF, DOCX, atau PPTX untuk memulai analisis AI.',
                  )
                else
                  ...recentDocs.whereType<Map>().map((raw) {
                    final d = Map<String, dynamic>.from(raw);
                    return DocumentCard(
                      title: (d['title'] ?? '').toString(),
                      subject: (d['subject'] ?? '').toString(),
                      format: 'DOC',
                      status: (d['status'] ?? 'UPLOADED').toString(),
                      progress: d['status'] == 'READY' ? 100 : 40,
                      onTap: () => context.go('/teacher/materials'),
                    );
                  }),
                const SizedBox(height: 16),
                Text('Konten AI Terbaru', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                if (recentContents.isEmpty)
                  const EmptyState(
                    icon: LucideIcons.layers,
                    title: 'Belum Ada Konten AI',
                    description: 'Gunakan AI Generator untuk menyusun rangkuman, kuis, atau game.',
                  )
                else
                  ...recentContents.whereType<Map>().map((raw) {
                    final c = Map<String, dynamic>.from(raw);
                    return ContentCard(
                      title: (c['title'] ?? '').toString(),
                      contentTypeLabel: (c['contentType'] ?? 'SUMMARY').toString(),
                      statusLabel: (c['status'] ?? 'DRAFT').toString(),
                      onTap: () => context.push('/teacher/content/${c['id']}'),
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

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 20),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: color),
                ),
              ],
            ),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
