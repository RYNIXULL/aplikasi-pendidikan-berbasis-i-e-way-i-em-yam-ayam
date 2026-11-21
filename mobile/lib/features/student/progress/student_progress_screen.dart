import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_cards.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/providers/app_providers.dart';

final studentProgressProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  try {
    final res = await ref
        .read(apiClientProvider)
        .dio
        .get<Map<String, dynamic>>(ApiPaths.studentProgress);
    return (res.data?['data'] as Map<String, dynamic>?) ?? {};
  } on DioException catch (e) {
    throw AppFailure.fromDioError(e);
  }
});

class StudentProgressScreen extends ConsumerWidget {
  const StudentProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(studentProgressProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Perkembangan Belajar')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(studentProgressProvider),
        child: asyncData.when(
          loading: () => const LoadingState(message: 'Memuat riwayat belajar...'),
          error: (err, _) => ErrorState(
            message: err is AppFailure ? err.message : err.toString(),
            onRetry: () => ref.invalidate(studentProgressProvider),
          ),
          data: (data) {
            final progress = (data['progress'] as List?) ?? const [];
            final graded = (data['gradedAttempts'] as List?) ?? const [];

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                if (graded.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tren Nilai Evaluasi', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 160,
                            child: LineChart(
                              LineChartData(
                                minY: 0,
                                maxY: 100,
                                gridData: const FlGridData(show: false),
                                borderData: FlBorderData(show: false),
                                titlesData: const FlTitlesData(show: false),
                                lineBarsData: [
                                  LineChartBarData(
                                    isCurved: true,
                                    color: AppColors.primary,
                                    barWidth: 3,
                                    spots: List.generate(graded.length, (i) {
                                      final att = Map<String, dynamic>.from(graded[i] as Map);
                                      return FlSpot(
                                        i.toDouble(),
                                        (att['percentage'] as num?)?.toDouble() ?? 0,
                                      );
                                    }),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                Text('Progres Materi', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                if (progress.isEmpty)
                  const EmptyState(
                    icon: LucideIcons.trendingUp,
                    title: 'Belum Ada Progres Tercatat',
                    description: 'Buka dan selesaikan materi di kelas Anda untuk melacak kemajuan.',
                  )
                else
                  ...progress.whereType<Map>().map((raw) {
                    final p = Map<String, dynamic>.from(raw);
                    final mat = (p['material'] as Map<String, dynamic>?) ?? {};
                    final cls = (p['classroom'] as Map<String, dynamic>?) ?? {};
                    final pct = (p['completionPercentage'] as num?)?.toInt() ?? 0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text((mat['title'] ?? 'Materi').toString(),
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text((cls['name'] ?? '').toString(),
                                style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 10),
                            AppProgressIndicator(
                              value: pct / 100.0,
                              label: (p['status'] ?? 'IN_PROGRESS').toString(),
                              color: pct >= 100 ? AppColors.success : AppColors.primary,
                            ),
                          ],
                        ),
                      ),
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
