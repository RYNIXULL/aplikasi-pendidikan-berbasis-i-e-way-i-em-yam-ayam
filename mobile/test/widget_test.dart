import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:edu_ai_mobile/core/router/app_router.dart';
import 'package:edu_ai_mobile/core/storage/token_storage.dart';
import 'package:edu_ai_mobile/core/theme/app_theme.dart';
import 'package:edu_ai_mobile/core/widgets/app_bottom_navigation.dart';
import 'package:edu_ai_mobile/core/widgets/app_buttons.dart';
import 'package:edu_ai_mobile/core/widgets/app_cards.dart';
import 'package:edu_ai_mobile/core/widgets/app_states.dart';
import 'package:edu_ai_mobile/core/widgets/app_toast.dart';
import 'package:edu_ai_mobile/features/student/dashboard/student_dashboard_screen.dart';
import 'package:edu_ai_mobile/features/student/educational_games/game_engine_screen.dart';
import 'package:edu_ai_mobile/features/teacher/dashboard/teacher_dashboard_screen.dart';
import 'package:edu_ai_mobile/shared/models/models.dart';
import 'package:edu_ai_mobile/shared/providers/app_providers.dart';

void main() {
  group('Unit Tests — Models & Token Storage', () {
    test('UserModel parses nested profile and roles accurately', () {
      final teacher = UserModel.fromJson({
        'id': 'u-1',
        'email': 'budi@example.com',
        'role': 'TEACHER',
        'profile': {
          'fullName': 'Budi Santoso',
          'subjectSpecialty': 'Biologi',
        },
      });
      expect(teacher.role, UserRole.teacher);
      expect(teacher.fullName, 'Budi Santoso');
      expect(teacher.subjectSpecialty, 'Biologi');
    });

    test('InMemoryTokenStorage saves, reads, and clears tokens', () async {
      final storage = InMemoryTokenStorage();
      await storage.saveTokens(accessToken: 'acc-1', refreshToken: 'ref-1');
      expect(await storage.readAccessToken(), 'acc-1');
      expect(await storage.readRefreshToken(), 'ref-1');
      await storage.clearTokens();
      expect(await storage.readAccessToken(), isNull);
    });

    test('GameConfigModel parses declarative config JSON', () {
      final cfg = GameConfigModel.fromJson({
        'game_type': 'true_false',
        'title': 'Benar atau Salah',
        'instructions': 'Pilih jawaban tepat.',
        'max_possible_score': 100,
        'settings': {'time_limit_seconds': 60},
        'items': [
          {'id': 'tf1', 'statement': 'Lambung menghasilkan pepsin.', 'is_true': true, 'points': 100},
        ],
      }, materialId: 'mat-1');
      expect(cfg.gameType, 'true_false');
      expect(cfg.maxPossibleScore, 100);
      expect(cfg.items.length, 1);
    });
  });

  group('Widget Tests — Design System & Custom Toast', () {
    testWidgets('renders DocumentCard, PrimaryButton, EmptyState, and AppToast', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ListView(
                children: [
                  const DocumentCard(
                    title: 'Modul Biologi Kelas XI',
                    subject: 'Biologi',
                    format: 'PDF',
                    status: 'READY',
                    progress: 100,
                    pageCount: 24,
                  ),
                  PrimaryButton(
                    label: 'Tampilkan Notifikasi',
                    icon: LucideIcons.bell,
                    onPressed: () {
                      AppToast.show(
                        context,
                        message: 'Konten berhasil disimpan.',
                        variant: ToastVariant.success,
                      );
                    },
                  ),
                  const EmptyState(
                    icon: LucideIcons.folderOpen,
                    title: 'Kosong',
                    description: 'Belum ada item.',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Modul Biologi Kelas XI'), findsOneWidget);
      expect(find.text('PDF - 24 halaman'), findsOneWidget);

      await tester.tap(find.text('Tampilkan Notifikasi'));
      await tester.pump();
      expect(find.text('Konten berhasil disimpan.'), findsOneWidget);

      // Wait out toast dismissal timer cleanly
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('Navigation Tests — Role-Based Routing', () {
    testWidgets('authenticated TEACHER enters TeacherShell with 6 teacher destinations',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
          teacherDashboardProvider.overrideWith(
            (ref) async => {
              'metrics': {
                'documentCount': 3,
                'pendingDraftCount': 1,
                'classroomCount': 2,
                'pendingGradingCount': 4,
              },
              'recentDocuments': const [],
              'recentContents': const [],
            },
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(authControllerProvider.notifier).setAuthenticatedUserForTest(
            const UserModel(
              id: 't-1',
              email: 'budi@example.com',
              role: UserRole.teacher,
              fullName: 'Budi Santoso',
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              final router = ref.watch(appRouterProvider);
              return MaterialApp.router(
                theme: AppTheme.light(),
                routerConfig: router,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppBottomNavigation), findsOneWidget);
      expect(find.text('AI Gen'), findsOneWidget);
      expect(find.text('Evaluasi'), findsOneWidget);
      expect(find.text('Dokumen Materi'), findsOneWidget);
    });

    testWidgets('authenticated STUDENT enters StudentShell with 6 student destinations',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
          studentDashboardProvider.overrideWith(
            (ref) async => {
              'summary': {
                'classroomCount': 2,
                'completedMaterials': 5,
                'averageScore': 88.5,
              },
              'latestMaterials': const [],
              'upcomingAssessments': const [],
            },
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(authControllerProvider.notifier).setAuthenticatedUserForTest(
            const UserModel(
              id: 's-1',
              email: 'siti@example.com',
              role: UserRole.student,
              fullName: 'Siti Rahmawati',
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              final router = ref.watch(appRouterProvider);
              return MaterialApp.router(
                theme: AppTheme.light(),
                routerConfig: router,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppBottomNavigation), findsOneWidget);
      expect(find.text('Belajar'), findsOneWidget);
      expect(find.text('Progres'), findsOneWidget);
      expect(find.text('88.5%'), findsOneWidget);
    });
  });

  group('Educational Game Engine — Native Renderers', () {
    testWidgets('TrueFalseRenderer scores correct answer and invokes completion callback',
        (tester) async {
      GamePlayResult? result;
      final config = GameConfigModel.fromJson({
        'game_type': 'true_false',
        'title': 'Benar atau Salah Biologi',
        'instructions': 'Pilih benar atau salah.',
        'max_possible_score': 100,
        'items': [
          {'id': 'tf1', 'statement': 'Lambung menghasilkan HCl.', 'is_true': true, 'points': 100},
        ],
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: TrueFalseRenderer(
              config: config,
              onComplete: (r) => result = r,
            ),
          ),
        ),
      );

      expect(find.text('Lambung menghasilkan HCl.'), findsOneWidget);
      await tester.tap(find.text('Benar'));
      await tester.pump();

      expect(result, isNotNull);
      expect(result!.score, 100);
      expect(result!.accuracyPercentage, 100.0);
    });

    testWidgets('CrosswordRenderer validates typed answers and scores accurately', (tester) async {
      GamePlayResult? result;
      final config = GameConfigModel.fromJson({
        'game_type': 'crossword',
        'title': 'TTS Biologi',
        'instructions': 'Isi kotak.',
        'max_possible_score': 100,
        'grid_size': {'rows': 6, 'cols': 8},
        'entries': [
          {
            'number': 1,
            'direction': 'across',
            'row': 1,
            'col': 0,
            'answer': 'LAMBUNG',
            'clue': 'Organ pencernaan utama',
          },
        ],
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: CrosswordRenderer(
              config: config,
              onComplete: (r) => result = r,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'lambung');
      await tester.tap(find.text('Periksa Jawaban TTS'));
      await tester.pump();

      expect(result, isNotNull);
      expect(result!.score, 100);
    });
  });
}
