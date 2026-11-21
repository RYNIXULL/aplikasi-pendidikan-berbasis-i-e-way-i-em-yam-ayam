import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_cards.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/models/models.dart';
import '../../../shared/providers/app_providers.dart';

final studentAssessmentsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    final res = await ref
        .read(apiClientProvider)
        .dio
        .get<Map<String, dynamic>>(ApiPaths.studentAssessments);
    final raw = (res.data?['data'] as List?) ?? const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  } on DioException catch (e) {
    throw AppFailure.fromDioError(e);
  }
});

class StudentAssessmentsScreen extends ConsumerWidget {
  const StudentAssessmentsScreen({super.key});

  Future<void> _startQuiz(BuildContext context, WidgetRef ref, Map<String, dynamic> assessment) async {
    final id = assessment['id'].toString();
    try {
      final res = await ref
          .read(apiClientProvider)
          .dio
          .post<Map<String, dynamic>>('${ApiPaths.assessments}/$id/attempts');
      final data = (res.data?['data'] as Map<String, dynamic>?) ?? {};
      final attempt = (data['attempt'] as Map<String, dynamic>?) ?? {};
      final rawQuestions = (data['questions'] as List?) ?? const [];
      final questions = rawQuestions
          .whereType<Map>()
          .map((q) => AssessmentQuestionModel.fromJson(Map<String, dynamic>.from(q)))
          .toList();

      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => QuizRunnerScreen(
            attemptId: attempt['id'].toString(),
            title: (assessment['title'] ?? 'Kuis').toString(),
            timeLimitSeconds: (assessment['timeLimitSeconds'] as num?)?.toInt(),
            questions: questions,
          ),
        ),
      );
      ref.invalidate(studentAssessmentsProvider);
    } on DioException catch (e) {
      if (!context.mounted) return;
      AppToast.show(context, message: AppFailure.fromDioError(e).message, variant: ToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncItems = ref.watch(studentAssessmentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tugas & Ujian')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(studentAssessmentsProvider),
        child: asyncItems.when(
          loading: () => const LoadingState(message: 'Memuat daftar tugas...'),
          error: (err, _) => ErrorState(
            message: err is AppFailure ? err.message : err.toString(),
            onRetry: () => ref.invalidate(studentAssessmentsProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const EmptyState(
                icon: LucideIcons.clipboardCheck,
                title: 'Belum Ada Tugas atau Ujian',
                description: 'Kuis dan ujian dari kelas Anda akan muncul di halaman ini.',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: items.length,
              itemBuilder: (_, idx) {
                final a = items[idx];
                final cls = (a['classroom'] as Map<String, dynamic>?) ?? {};
                final counts = (a['_count'] as Map<String, dynamic>?) ?? {};
                final attempts = (a['attempts'] as List?) ?? const [];
                final lastAttempt =
                    attempts.isNotEmpty ? Map<String, dynamic>.from(attempts.first as Map) : null;
                final lastStatus = lastAttempt?['status']?.toString();

                return ContentCard(
                  title: (a['title'] ?? '').toString(),
                  contentTypeLabel: '${counts['questions'] ?? 0} soal',
                  statusLabel: lastStatus ?? 'KERJAKAN',
                  statusColor:
                      lastStatus == 'GRADED' ? AppColors.success : AppColors.primary,
                  subject: cls['subject']?.toString(),
                  subtitle: cls['name']?.toString(),
                  onTap: () => _startQuiz(context, ref, a),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class QuizRunnerScreen extends ConsumerStatefulWidget {
  const QuizRunnerScreen({
    super.key,
    required this.attemptId,
    required this.title,
    required this.questions,
    this.timeLimitSeconds,
  });

  final String attemptId;
  final String title;
  final List<AssessmentQuestionModel> questions;
  final int? timeLimitSeconds;

  @override
  ConsumerState<QuizRunnerScreen> createState() => _QuizRunnerScreenState();
}

class _QuizRunnerScreenState extends ConsumerState<QuizRunnerScreen> {
  final Map<String, String> _answers = {};
  int _index = 0;
  int? _remainingSeconds;
  Timer? _timer;
  bool _submitting = false;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    if (widget.timeLimitSeconds != null && widget.timeLimitSeconds! > 0) {
      _remainingSeconds = widget.timeLimitSeconds;
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if ((_remainingSeconds ?? 0) <= 1) {
          t.cancel();
          _submitAttempt(autoSubmit: true);
        } else {
          setState(() => _remainingSeconds = (_remainingSeconds ?? 1) - 1);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _submitAttempt({bool autoSubmit = false}) async {
    if (_submitting) return;
    if (!autoSubmit) {
      final ok = await ConfirmationDialog.show(
        context,
        title: 'Kumpulkan Jawaban',
        message: 'Pastikan seluruh soal telah dijawab. Jawaban tidak dapat diubah setelah dikumpulkan.',
        confirmLabel: 'Kumpulkan',
      );
      if (!ok) return;
    }

    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider).dio;
      if (_answers.isNotEmpty) {
        await api.put<void>(
          '${ApiPaths.attempts}/${widget.attemptId}/answers',
          data: {
            'answers': _answers.entries
                .map((e) => {'questionId': e.key, 'studentAnswer': e.value})
                .toList(),
          },
        );
      }
      final res = await api.post<Map<String, dynamic>>(
        '${ApiPaths.attempts}/${widget.attemptId}/submit',
      );
      _timer?.cancel();
      setState(() => _result = (res.data?['data'] as Map<String, dynamic>?) ?? {});
      if (!mounted) return;
      AppToast.show(context, message: 'Jawaban berhasil dikumpulkan.', variant: ToastVariant.success);
    } on DioException catch (e) {
      if (!mounted) return;
      AppToast.show(context, message: AppFailure.fromDioError(e).message, variant: ToastVariant.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_result != null) {
      final pct = (_result!['percentage'] as num?)?.toDouble() ?? 0;
      final passed = _result!['passed'] as bool?;
      return Scaffold(
        appBar: AppBar(title: const Text('Hasil Evaluasi')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                passed == true ? LucideIcons.award : LucideIcons.clipboardCheck,
                size: 56,
                color: passed == true ? AppColors.success : AppColors.primary,
              ),
              const SizedBox(height: 16),
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 38),
              ),
              const SizedBox(height: 8),
              Text(
                _result!['hasPendingManualGrading'] == true
                    ? 'Nilai pilihan ganda telah dihitung. Soal esai menunggu penilaian pengajar.'
                    : (passed == true
                        ? 'Selamat, Anda memenuhi standar kelulusan.'
                        : 'Terus pelajari materi untuk meningkatkan skor Anda.'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Kembali ke Daftar Tugas',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      );
    }

    final q = widget.questions[_index];
    final currentAnswer = _answers[q.id] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_remainingSeconds != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: SubjectBadge(
                  icon: LucideIcons.clock,
                  label:
                      '${(_remainingSeconds! ~/ 60).toString().padLeft(2, '0')}:${(_remainingSeconds! % 60).toString().padLeft(2, '0')}',
                  color: _remainingSeconds! < 60 ? AppColors.error : AppColors.primary,
                ),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppProgressIndicator(
              value: (_index + 1) / widget.questions.length,
              label: 'Soal ${_index + 1} dari ${widget.questions.length}',
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                children: [
                  Text(q.prompt, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  if (q.questionType == 'MULTIPLE_CHOICE' || q.questionType == 'TRUE_FALSE')
                    ...q.options.map((opt) {
                      final selected = currentAnswer == opt;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: RadioListTile<String>(
                          value: opt,
                          groupValue: currentAnswer.isEmpty ? null : currentAnswer,
                          title: Text(opt),
                          activeColor: AppColors.primary,
                          selected: selected,
                          onChanged: (v) {
                            if (v != null) setState(() => _answers[q.id] = v);
                          },
                        ),
                      );
                    })
                  else
                    TextFormField(
                      key: ValueKey(q.id),
                      initialValue: currentAnswer,
                      maxLines: q.questionType == 'ESSAY' ? 6 : 2,
                      decoration: const InputDecoration(
                        hintText: 'Tuliskan jawaban Anda di sini...',
                      ),
                      onChanged: (v) => _answers[q.id] = v,
                    ),
                ],
              ),
            ),
            Row(
              children: [
                if (_index > 0)
                  Expanded(
                    child: SecondaryButton(
                      label: 'Sebelumnya',
                      onPressed: () => setState(() => _index--),
                    ),
                  ),
                if (_index > 0) const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    label: _index == widget.questions.length - 1 ? 'Kumpulkan' : 'Lanjut',
                    isLoading: _submitting,
                    onPressed: _index == widget.questions.length - 1
                        ? () => _submitAttempt()
                        : () => setState(() => _index++),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
