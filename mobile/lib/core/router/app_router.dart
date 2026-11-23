import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../features/authentication/login_screen.dart';
import '../../features/authentication/register_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/student/assessments/student_assessments_screen.dart';
import '../../features/student/classrooms/student_classrooms_screen.dart';
import '../../features/student/dashboard/student_dashboard_screen.dart';
import '../../features/student/educational_games/game_engine_screen.dart';
import '../../features/student/learning_materials/student_learning_screen.dart';
import '../../features/student/progress/student_progress_screen.dart';
import '../../features/teacher/ai_generator/teacher_ai_generator_screen.dart';
import '../../features/teacher/analytics/teacher_analytics_screen.dart';
import '../../features/teacher/assessments/teacher_assessments_screen.dart';
import '../../features/teacher/classrooms/teacher_classrooms_screen.dart';
import '../../features/teacher/content_editor/teacher_content_editor_screen.dart';
import '../../features/teacher/dashboard/teacher_dashboard_screen.dart';
import '../../features/teacher/documents/teacher_documents_screen.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_providers.dart';
import '../widgets/app_bottom_navigation.dart';

const _teacherDestinations = [
  NavDestinationItem(label: 'Beranda', icon: LucideIcons.layoutDashboard, route: '/teacher/dashboard'),
  NavDestinationItem(label: 'Materi', icon: LucideIcons.fileText, route: '/teacher/materials'),
  NavDestinationItem(label: 'AI Gen', icon: LucideIcons.cpu, route: '/teacher/generator'),
  NavDestinationItem(label: 'Kelas', icon: LucideIcons.school, route: '/teacher/classrooms'),
  NavDestinationItem(label: 'Evaluasi', icon: LucideIcons.clipboardList, route: '/teacher/assessments'),
  NavDestinationItem(label: 'Profil', icon: LucideIcons.user, route: '/teacher/profile'),
];

const _studentDestinations = [
  NavDestinationItem(label: 'Beranda', icon: LucideIcons.house, route: '/student/home'),
  NavDestinationItem(label: 'Kelas', icon: LucideIcons.school, route: '/student/classes'),
  NavDestinationItem(label: 'Belajar', icon: LucideIcons.bookOpen, route: '/student/learning'),
  NavDestinationItem(label: 'Tugas', icon: LucideIcons.clipboardCheck, route: '/student/assignments'),
  NavDestinationItem(label: 'Progres', icon: LucideIcons.trendingUp, route: '/student/progress'),
  NavDestinationItem(label: 'Profil', icon: LucideIcons.user, route: '/student/profile'),
];

class _RouterRefreshNotifier extends ChangeNotifier {
  void trigger() => notifyListeners();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.listen<AuthState>(authControllerProvider, (_, __) {
    refreshNotifier.trigger();
  });
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/onboarding',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final path = state.uri.path;
      final isPublic = path == '/onboarding' || path == '/login' || path == '/register';

      if (!authState.isAuthenticated) {
        return isPublic ? null : '/login';
      }

      final role = authState.user!.role;
      final defaultHome =
          role == UserRole.teacher ? '/teacher/dashboard' : '/student/home';

      if (isPublic) return defaultHome;

      // Cross-role route protection on client (authoritative RBAC remains on backend)
      if (role == UserRole.teacher && path.startsWith('/student')) {
        return '/teacher/dashboard';
      }
      if (role == UserRole.student && path.startsWith('/teacher')) {
        return '/student/home';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),

      // Teacher Shell (6 destinations)
      ShellRoute(
        builder: (context, state, child) {
          final currentIndex = _teacherDestinations
              .indexWhere((d) => state.uri.path.startsWith(d.route))
              .clamp(0, _teacherDestinations.length - 1);
          return Scaffold(
            extendBody: true,
            body: child,
            bottomNavigationBar: AppBottomNavigation(
              items: _teacherDestinations,
              currentIndex: currentIndex,
              onSelect: (i) => context.go(_teacherDestinations[i].route),
            ),
          );
        },
        routes: [
          GoRoute(path: '/teacher/dashboard', builder: (_, __) => const TeacherDashboardScreen()),
          GoRoute(path: '/teacher/materials', builder: (_, __) => const TeacherDocumentsScreen()),
          GoRoute(path: '/teacher/generator', builder: (_, __) => const TeacherAiGeneratorScreen()),
          GoRoute(path: '/teacher/classrooms', builder: (_, __) => const TeacherClassroomsScreen()),
          GoRoute(path: '/teacher/assessments', builder: (_, __) => const TeacherAssessmentsScreen()),
          GoRoute(path: '/teacher/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
      GoRoute(
        path: '/teacher/content/:id',
        builder: (_, state) =>
            TeacherContentEditorScreen(contentId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/teacher/analytics/:classroomId',
        builder: (_, state) =>
            TeacherAnalyticsScreen(classroomId: state.pathParameters['classroomId'] ?? ''),
      ),

      // Student Shell (6 destinations)
      ShellRoute(
        builder: (context, state, child) {
          final currentIndex = _studentDestinations
              .indexWhere((d) => state.uri.path.startsWith(d.route))
              .clamp(0, _studentDestinations.length - 1);
          return Scaffold(
            extendBody: true,
            body: child,
            bottomNavigationBar: AppBottomNavigation(
              items: _studentDestinations,
              currentIndex: currentIndex,
              onSelect: (i) => context.go(_studentDestinations[i].route),
            ),
          );
        },
        routes: [
          GoRoute(path: '/student/home', builder: (_, __) => const StudentDashboardScreen()),
          GoRoute(path: '/student/classes', builder: (_, __) => const StudentClassroomsScreen()),
          GoRoute(path: '/student/learning', builder: (_, __) => const StudentLearningScreen()),
          GoRoute(path: '/student/assignments', builder: (_, __) => const StudentAssessmentsScreen()),
          GoRoute(path: '/student/progress', builder: (_, __) => const StudentProgressScreen()),
          GoRoute(path: '/student/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
      GoRoute(
        path: '/student/game/:materialId',
        builder: (_, state) =>
            GameEngineScreen(materialId: state.pathParameters['materialId'] ?? ''),
      ),
    ],
  );
});
