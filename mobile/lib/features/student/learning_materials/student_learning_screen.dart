import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/storage/offline_cache_db.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_cards.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/providers/app_providers.dart';
import '../../teacher/classrooms/teacher_classrooms_screen.dart';

class StudentLearningScreen extends ConsumerStatefulWidget {
  const StudentLearningScreen({super.key});

  @override
  ConsumerState<StudentLearningScreen> createState() => _StudentLearningScreenState();
}

class _StudentLearningScreenState extends ConsumerState<StudentLearningScreen> {
  String? _selectedClassroomId;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _materials = const [];

  Future<void> _loadMaterials(String classroomId) async {
    setState(() {
      _selectedClassroomId = classroomId;
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref
          .read(apiClientProvider)
          .dio
          .get<Map<String, dynamic>>('${ApiPaths.classrooms}/$classroomId/materials');
      final raw = (res.data?['data'] as List?) ?? const [];
      _materials = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } on DioException catch (e) {
      _error = AppFailure.fromDioError(e).message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openMaterial(Map<String, dynamic> material) async {
    final materialId = material['id'].toString();
    final classroomId = _selectedClassroomId!;
    final contentMeta = (material['content'] as Map<String, dynamic>?) ?? {};
    final contentType = (contentMeta['contentType'] ?? 'SUMMARY').toString();

    if (contentType == 'GAME') {
      context.push('/student/game/$materialId');
      return;
    }

    Map<String, dynamic>? payload;
    try {
      final res = await ref
          .read(apiClientProvider)
          .dio
          .get<Map<String, dynamic>>('${ApiPaths.classrooms}/$classroomId/materials/$materialId');
      final full = (res.data?['data'] as Map<String, dynamic>?) ?? {};
      final ver = (full['publishedVersion'] as Map<String, dynamic>?) ?? {};
      payload = (ver['payload'] as Map<String, dynamic>?) ?? {};

      // Cache locally in SQLite for offline study
      await ref.read(offlineCacheProvider).upsertMaterial(
            CachedMaterialRecord(
              materialId: materialId,
              classroomId: classroomId,
              title: (material['title'] ?? '').toString(),
              contentType: contentType,
              payloadJson: payload,
              cachedAt: DateTime.now(),
            ),
          );
    } catch (_) {
      final cached = await ref.read(offlineCacheProvider).getMaterial(materialId);
      if (cached != null) {
        payload = cached.payloadJson;
        if (mounted) {
          AppToast.show(
            context,
            message: 'Menampilkan salinan offline tersimpan.',
            variant: ToastVariant.info,
          );
        }
      }
    }

    if (!mounted) return;
    if (payload == null) {
      AppToast.show(context, message: 'Gagal memuat materi pembelajaran.', variant: ToastVariant.error);
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MaterialReaderScreen(
          materialId: materialId,
          title: (material['title'] ?? '').toString(),
          contentType: contentType,
          payload: payload!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncClasses = ref.watch(classroomsListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Belajar & Game')),
      body: asyncClasses.when(
        loading: () => const LoadingState(message: 'Memuat kelas...'),
        error: (err, _) => ErrorState(
          message: err is AppFailure ? err.message : err.toString(),
          onRetry: () => ref.invalidate(classroomsListProvider),
        ),
        data: (classes) {
          if (classes.isEmpty) {
            return const EmptyState(
              icon: LucideIcons.bookOpen,
              title: 'Belum Ada Materi Kelas',
              description: 'Gabung ke kelas terlebih dahulu di tab Kelas Saya.',
            );
          }

          if (_selectedClassroomId == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _selectedClassroomId == null) {
                _loadMaterials(classes.first.id);
              }
            });
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: DropdownButtonFormField<String>(
                  value: classes.any((c) => c.id == _selectedClassroomId)
                      ? _selectedClassroomId
                      : classes.first.id,
                  decoration: const InputDecoration(
                    labelText: 'Pilih Kelas',
                    prefixIcon: Icon(LucideIcons.school, size: 18),
                  ),
                  items: classes
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (id) {
                    if (id != null) _loadMaterials(id);
                  },
                ),
              ),
              Expanded(
                child: _loading
                    ? const LoadingState(message: 'Memuat materi...')
                    : _error != null
                        ? ErrorState(
                            message: _error!,
                            onRetry: () {
                              if (_selectedClassroomId != null) _loadMaterials(_selectedClassroomId!);
                            },
                          )
                        : _materials.isEmpty
                            ? const EmptyState(
                                icon: LucideIcons.layers,
                                title: 'Belum Ada Materi Dipublikasikan',
                                description: 'Pengajar belum membagikan materi ke kelas ini.',
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                                itemCount: _materials.length,
                                itemBuilder: (_, idx) {
                                  final m = _materials[idx];
                                  final content = (m['content'] as Map<String, dynamic>?) ?? {};
                                  final type = (content['contentType'] ?? 'SUMMARY').toString();
                                  return ContentCard(
                                    title: (m['title'] ?? '').toString(),
                                    contentTypeLabel: type == 'GAME'
                                        ? 'GAME: ${content['gameType'] ?? ''}'
                                        : type,
                                    statusLabel: type == 'GAME' ? 'MAIN' : 'BUKA',
                                    statusColor: type == 'GAME'
                                        ? AppColors.secondary
                                        : AppColors.primary,
                                    subject: content['subject']?.toString(),
                                    onTap: () => _openMaterial(m),
                                  );
                                },
                              ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Unified rich interactive viewer for Summary, Presentation slides,
/// Flip Flashcards, Mind Map tree, and Worksheets.
class MaterialReaderScreen extends ConsumerStatefulWidget {
  const MaterialReaderScreen({
    super.key,
    required this.materialId,
    required this.title,
    required this.contentType,
    required this.payload,
  });

  final String materialId;
  final String title;
  final String contentType;
  final Map<String, dynamic> payload;

  @override
  ConsumerState<MaterialReaderScreen> createState() => _MaterialReaderScreenState();
}

class _MaterialReaderScreenState extends ConsumerState<MaterialReaderScreen> {
  int _flashcardIdx = 0;
  bool _flashcardFlipped = false;

  Future<void> _markCompleted() async {
    try {
      await ref.read(apiClientProvider).dio.post<void>(
        '${ApiPaths.studentProgress}/${widget.materialId}',
        data: {'completionPercentage': 100, 'timeSpentSecondsDelta': 60},
      );
      if (!mounted) return;
      AppToast.show(context, message: 'Progres materi ditandai selesai.', variant: ToastVariant.success);
    } catch (_) {
      await ref.read(offlineCacheProvider).enqueueProgressSync(
            materialId: widget.materialId,
            completionPercentage: 100,
            timeSpentDelta: 60,
          );
      if (!mounted) return;
      AppToast.show(
        context,
        message: 'Tersimpan offline. Akan disinkronkan saat online.',
        variant: ToastVariant.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildBody(context),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Tandai Materi Selesai',
            icon: LucideIcons.circleCheck,
            onPressed: _markCompleted,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (widget.contentType) {
      case 'FLASHCARDS':
        final cards = (widget.payload['cards'] as List?) ?? const [];
        if (cards.isEmpty) return const Text('Belum ada kartu belajar.');
        final current = Map<String, dynamic>.from(cards[_flashcardIdx % cards.length] as Map);
        return Column(
          children: [
            Text('Kartu ${_flashcardIdx + 1} dari ${cards.length}',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(() => _flashcardFlipped = !_flashcardFlipped),
              child: Card(
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 210),
                  padding: const EdgeInsets.all(24),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SubjectBadge(label: _flashcardFlipped ? 'Jawaban' : 'Pertanyaan'),
                      const SizedBox(height: 16),
                      Text(
                        (_flashcardFlipped ? current['back'] : current['front']).toString(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 14),
                      Text('Ketuk kartu untuk membalik',
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SecondaryButton(
                  label: 'Sebelumnya',
                  fullWidth: false,
                  onPressed: _flashcardIdx > 0
                      ? () => setState(() {
                            _flashcardIdx--;
                            _flashcardFlipped = false;
                          })
                      : null,
                ),
                PrimaryButton(
                  label: 'Berikutnya',
                  fullWidth: false,
                  onPressed: _flashcardIdx < cards.length - 1
                      ? () => setState(() {
                            _flashcardIdx++;
                            _flashcardFlipped = false;
                          })
                      : null,
                ),
              ],
            ),
          ],
        );

      case 'MIND_MAP':
        final root = widget.payload['root'] as Map<String, dynamic>?;
        if (root == null) return const Text('Struktur peta konsep kosong.');
        return _MindMapNodeTile(node: root, depth: 0);

      case 'PRESENTATION':
        final slides = (widget.payload['slides'] as List?) ?? const [];
        return Column(
          children: slides.whereType<Map>().map((s) {
            final bullets = (s['content'] as List?) ?? const [];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SubjectBadge(label: 'Slide ${s['slide_number'] ?? ''}'),
                    const SizedBox(height: 8),
                    Text((s['title'] ?? '').toString(),
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    ...bullets.map((b) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('- $b', style: Theme.of(context).textTheme.bodyLarge),
                        )),
                  ],
                ),
              ),
            );
          }).toList(),
        );

      case 'WORKSHEET':
        final activities = (widget.payload['activities'] as List?) ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((widget.payload['instructions'] ?? '').toString(),
                style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 14),
            ...activities.whereType<Map>().map((a) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SubjectBadge(label: '${a['max_points'] ?? 20} poin'),
                        const SizedBox(height: 8),
                        Text((a['prompt'] ?? '').toString(),
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  ),
                )),
          ],
        );

      default:
        // SUMMARY
        final shortSummary = (widget.payload['short_summary'] ?? '').toString();
        final sections = (widget.payload['detailed_summary'] as List?) ?? const [];
        final points = (widget.payload['key_points'] as List?) ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ringkasan Singkat', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(shortSummary, style: Theme.of(context).textTheme.bodyLarge),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Poin Penting', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...points.whereType<Map>().map((p) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(LucideIcons.check, size: 16, color: AppColors.secondary),
                  title: Text((p['point'] ?? '').toString()),
                  trailing: SubjectBadge(
                    label: 'Hal. ${(p['source_reference'] as Map?)?['page'] ?? '-'}',
                  ),
                )),
            const SizedBox(height: 14),
            Text('Pembahasan Mendalam', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...sections.whereType<Map>().map((s) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((s['section_title'] ?? '').toString(),
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text((s['body'] ?? '').toString(),
                            style: Theme.of(context).textTheme.bodyLarge),
                      ],
                    ),
                  ),
                )),
          ],
        );
    }
  }
}

class _MindMapNodeTile extends StatelessWidget {
  const _MindMapNodeTile({required this.node, required this.depth});

  final Map<String, dynamic> node;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final children = (node['children'] as List?) ?? const [];
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                depth == 0 ? LucideIcons.gitFork : LucideIcons.cornerDownRight,
                size: 18,
                color: depth == 0 ? AppColors.primary : AppColors.secondary,
              ),
              title: Text((node['label'] ?? '').toString(),
                  style: Theme.of(context).textTheme.titleMedium),
              subtitle: node['summary'] != null
                  ? Text(node['summary'].toString())
                  : (node['relationship'] != null
                      ? Text('Relasi: ${node['relationship']}')
                      : null),
            ),
          ),
          ...children
              .whereType<Map>()
              .map((c) => _MindMapNodeTile(node: Map<String, dynamic>.from(c), depth: depth + 1)),
        ],
      ),
    );
  }
}
