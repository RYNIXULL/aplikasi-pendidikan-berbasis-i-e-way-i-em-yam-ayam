class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppRadii {
  const AppRadii._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

class ApiPaths {
  const ApiPaths._();

  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String logout = '/auth/logout';
  static const String logoutAll = '/auth/logout-all';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resetPassword = '/auth/reset-password';
  static const String me = '/auth/me';
  static const String profile = '/users/me/profile';
  static const String password = '/users/me/password';

  static const String documents = '/documents';
  static const String aiGenerate = '/ai/generate';
  static const String aiJobs = '/ai/jobs';
  static const String aiQuota = '/ai/quota';
  static const String contents = '/contents';
  static const String classrooms = '/classrooms';
  static const String joinClassroom = '/classrooms/join';
  static const String studentAssessments = '/student/assessments';
  static const String assessments = '/assessments';
  static const String attempts = '/attempts';
  static const String games = '/games';
  static const String teacherDashboard = '/teacher/dashboard';
  static const String studentDashboard = '/student/dashboard';
  static const String studentProgress = '/student/progress';
}
