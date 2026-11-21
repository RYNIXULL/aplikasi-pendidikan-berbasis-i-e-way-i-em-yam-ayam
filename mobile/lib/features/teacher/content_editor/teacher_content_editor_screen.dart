import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_cards.dart';
import '../../../core/widgets/app_inputs.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/providers/app_providers.dart';

class TeacherContentEditorScreen extends ConsumerStatefulWidget {
  const TeacherContentEditorScreen({super.key, required this.contentId});

  final String contentId;

  @override
  ConsumerState<TeacherContentEditorScreen> createState() => _TeacherContentEditorScreenState();
}

class _TeacherContentEditorScreenState extends ConsumerState<TeacherContentEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _payloadCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _content;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _payloadCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref
          .read(apiClientProvider)
          .dio
          .get<Map<String, dynamic>>('${ApiPaths.contents}/${widget.contentId}');
      final data = (res.data?['data'] as Map<String, dynamic>?) ?? {};
      final currentVer = data['currentVersion'] as Map<String, dynamic>?;
      _content = data;
      _titleCtrl.text = (data['title'] ?? '').toString();
      _payloadCtrl.text = const JsonEncoder.withIndent('  ').convert(currentVer?['payload'] ?? {});
    } on DioException catch (e) {
      _error = AppFailure.fromDioError(e).message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveVersion() async {
    Map<String, dynamic> parsedPayload;
    try {
      parsedPayload = jsonDecode(_payloadCtrl.text) as Map<String, dynamic>;
    } catch (_) {
      AppToast.show(context, message: 'Format struktur JSON tidak valid.', variant: ToastVariant.error);
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).dio.patch<Map<String, dynamic>>(
        '${ApiPaths.contents}/${widget.contentId}',
        data: {
          'title': _titleCtrl.text.trim(),
          'payload': parsedPayload,
          if (_noteCtrl.text.trim().isNotEmpty) 'changeNote': _noteCtrl.text.trim(),
        },
      );
      await _load();
      if (!mounted) return;
      AppToast.show(context, message: 'Versi baru berhasil disimpan.', variant: ToastVariant.success);
    } on DioException catch (e) {
      if (!mounted) return;
      AppToast.show(context, message: AppFailure.fromDioError(e).message, variant: ToastVariant.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _approveContent() async {
    final ok = await ConfirmationDialog.show(
      context,
      title: 'Setujui Konten AI',
      message:
          'Dengan menyetujui, versi saat ini dinyatakan layak dan dapat dipublikasikan ke kelas siswa.',
      confirmLabel: 'Setujui Konten',
    );
    if (!ok) return;

    try {
      await ref.read(apiClientProvider).dio.post<Map<String, dynamic>>(
            '${ApiPaths.contents}/${widget.contentId}/approve',
          );
      await _load();
      if (!mounted) return;
      AppToast.show(context, message: 'Konten telah disetujui.', variant: ToastVariant.success);
    } on DioException catch (e) {
      if (!mounted) return;
      AppToast.show(context, message: AppFailure.fromDioError(e).message, variant: ToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = (_content?['status'] ?? 'DRAFT').toString();
    final type = (_content?['contentType'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: const Text('Editor & Review Konten')),
      body: _loading
          ? const LoadingState(message: 'Memuat konten...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        SubjectBadge(label: type, color: AppColors.secondary),
                        SubjectBadge(
                          label: status,
                          color: status == 'APPROVED' || status == 'PUBLISHED'
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    InputField(
                      controller: _titleCtrl,
                      label: 'Judul Konten',
                      prefixIcon: LucideIcons.type,
                    ),
                    const SizedBox(height: 14),
                    InputField(
                      controller: _noteCtrl,
                      label: 'Catatan Revisi (Opsional)',
                      hint: 'Contoh: Perbaikan distraktor soal nomor 3',
                      prefixIcon: LucideIcons.filePenLine,
                    ),
                    const SizedBox(height: 14),
                    InputField(
                      controller: _payloadCtrl,
                      label: 'Konten Terstruktur (JSON Tervalidasi)',
                      maxLines: 14,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            label: 'Simpan Versi',
                            icon: LucideIcons.save,
                            onPressed: _saving ? null : _saveVersion,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PrimaryButton(
                            label: 'Setujui Konten',
                            icon: LucideIcons.checkCheck,
                            isLoading: _saving,
                            onPressed: _approveContent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }
}
