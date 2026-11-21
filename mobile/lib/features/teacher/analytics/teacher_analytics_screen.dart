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

final classroomAnalyticsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, classroomId) async {
  try {
    final res = await ref
        .read(apiClientProvider)
        .dio
        .get<Map<String, dynamic>>('${ApiPaths.classrooms}/$classroomId/analytics');
    return (res.data?['data'] as Map<String, dynamic>?) ?? {};
  } on DioException catch (e) {
    throw AppFailure.fromDioError(e);
  }
});

class TeacherAnalyticsScreen extends ConsumerWidget {
  const TeacherAnalyticsScreen({super.key, required this.classroomId});

  final String classroomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAnalytics = ref.watch(classroomAnalyticsProvider(classroomId));

    return Scaffold(
      appBar: AppBar(title: const Text('Analitik Pembelajaran')),
      body: asyncAnalytics.when(
        loading: () => const LoadingState(message: 'Menghitung analitik kelas...'),
        error: (err, _) => ErrorState(
          message: err is AppFailure ? err.message : err.toString(),
          onRetry: () => ref.invalidate(classroomAnalyticsProvider(classroomId)),
        ),
        data: (data) {
          final dist = (data['scoreDistribution'] as Map<String, dynamic>?) ??
              {'0-49': 0, '50-69': 0, '70-84': 0, '85-100': 0};
          final weakQuestions = (data['weakQuestions'] as List?) ?? const [];
          final labels = ['0-49', '50-69', '70-84', '85-100'];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                (data['classroomName'] ?? 'Kelas').toString(),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Rata-Rata Nilai', style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 4),
                            Text(
                              '${data['averageScore'] ?? 0}%',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Penyelesaian', style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 4),
                            Text(
                              '${data['completionRate'] ?? 0}%',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(color: AppColors.secondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Distribusi Nilai Siswa', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 180,
                        child: BarChart(
                          BarChartData(
                            borderData: FlBorderData(show: false),
                            gridData: const FlGridData(show: false),
                            titlesData: FlTitlesData(
                              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (v, _) {
                                    final idx = v.toInt();
                                    return idx >= 0 && idx < labels.length
                                        ? Text(labels[idx], style: const TextStyle(fontSize: 11))
                                        : const SizedBox.shrink();
                                  },
                                ),
                              ),
                            ),
                            barGroups: List.generate(labels.length, (i) {
                              final count = (dist[labels[i]] as num?)?.toDouble() ?? 0;
                              return BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: count,
                                    width: 24,
                                    color: i >= 2 ? AppColors.secondary : AppColors.warning,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Soal Paling Sering Keliru', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              if (weakQuestions.isEmpty)
                const EmptyState(
                  icon: LucideIcons.chartColumn,
                  title: 'Belum Ada Data Soal',
                  description: 'Statistik per soal muncul setelah siswa menyelesaikan evaluasi.',
                )
              else
                ...weakQuestions.whereType<Map>().map((q) {
                  final rate = (q['successRate'] as num?)?.toDouble() ?? 0;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((q['prompt'] ?? '').toString(),
                              style: Theme.of(context).textTheme.bodyLarge),
                          const SizedBox(height: 8),
                          AppProgressIndicator(
                            value: rate / 100.0,
                            label: 'Tingkat ketepatan (${q['totalAttempts'] ?? 0} jawaban)',
                            color: rate >= 70 ? AppColors.success : AppColors.error,
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
    );
  }
}
