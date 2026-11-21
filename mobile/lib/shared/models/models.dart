enum UserRole { teacher, student, admin }

UserRole parseUserRole(String? raw) {
  switch ((raw ?? '').toUpperCase()) {
    case 'TEACHER':
      return UserRole.teacher;
    case 'ADMIN':
      return UserRole.admin;
    default:
      return UserRole.student;
  }
}

class UserModel {
  const UserModel({
    required this.id,
    required this.email,
    required this.role,
    required this.fullName,
    this.displayName,
    this.institutionName,
    this.subjectSpecialty,
    this.gradeLevel,
    this.preferredLocale = 'id',
  });

  final String id;
  final String email;
  final UserRole role;
  final String fullName;
  final String? displayName;
  final String? institutionName;
  final String? subjectSpecialty;
  final String? gradeLevel;
  final String preferredLocale;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>?;
    return UserModel(
      id: (json['id'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      role: parseUserRole(json['role']?.toString()),
      fullName: (json['fullName'] ?? profile?['fullName'] ?? 'Pengguna').toString(),
      displayName: (json['displayName'] ?? profile?['displayName'])?.toString(),
      institutionName: (json['institutionName'] ?? profile?['institutionName'])?.toString(),
      subjectSpecialty: (json['subjectSpecialty'] ?? profile?['subjectSpecialty'])?.toString(),
      gradeLevel: (json['gradeLevel'] ?? profile?['gradeLevel'])?.toString(),
      preferredLocale: (json['preferredLocale'] ?? profile?['preferredLocale'] ?? 'id').toString(),
    );
  }

  UserModel copyWith({
    String? fullName,
    String? displayName,
    String? institutionName,
    String? subjectSpecialty,
    String? gradeLevel,
    String? preferredLocale,
  }) {
    return UserModel(
      id: id,
      email: email,
      role: role,
      fullName: fullName ?? this.fullName,
      displayName: displayName ?? this.displayName,
      institutionName: institutionName ?? this.institutionName,
      subjectSpecialty: subjectSpecialty ?? this.subjectSpecialty,
      gradeLevel: gradeLevel ?? this.gradeLevel,
      preferredLocale: preferredLocale ?? this.preferredLocale,
    );
  }
}

class DocumentModel {
  const DocumentModel({
    required this.id,
    required this.title,
    required this.subject,
    required this.fileFormat,
    required this.status,
    required this.processingProgress,
    this.topic,
    this.description,
    this.pageCount,
    this.fileSizeBytes = 0,
  });

  final String id;
  final String title;
  final String subject;
  final String fileFormat;
  final String status;
  final int processingProgress;
  final String? topic;
  final String? description;
  final int? pageCount;
  final int fileSizeBytes;

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subject: (json['subject'] ?? '').toString(),
      fileFormat: (json['fileFormat'] ?? 'PDF').toString(),
      status: (json['status'] ?? 'UPLOADED').toString(),
      processingProgress: (json['processingProgress'] as num?)?.toInt() ?? 0,
      topic: json['topic']?.toString(),
      description: json['description']?.toString(),
      pageCount: (json['pageCount'] as num?)?.toInt(),
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

class GeneratedContentModel {
  const GeneratedContentModel({
    required this.id,
    required this.documentId,
    required this.title,
    required this.contentType,
    required this.status,
    this.gameType,
    this.subject,
    this.currentPayload,
  });

  final String id;
  final String documentId;
  final String title;
  final String contentType;
  final String status;
  final String? gameType;
  final String? subject;
  final Map<String, dynamic>? currentPayload;

  factory GeneratedContentModel.fromJson(Map<String, dynamic> json) {
    final currentVersion = json['currentVersion'] as Map<String, dynamic>?;
    return GeneratedContentModel(
      id: (json['id'] ?? '').toString(),
      documentId: (json['documentId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      contentType: (json['contentType'] ?? 'SUMMARY').toString(),
      status: (json['status'] ?? 'DRAFT').toString(),
      gameType: json['gameType']?.toString(),
      subject: json['subject']?.toString(),
      currentPayload: currentVersion?['payload'] as Map<String, dynamic>?,
    );
  }
}

class ClassroomModel {
  const ClassroomModel({
    required this.id,
    required this.name,
    required this.subject,
    required this.joinCode,
    required this.status,
    this.gradeLevel,
    this.description,
    this.memberCount = 0,
    this.materialCount = 0,
  });

  final String id;
  final String name;
  final String subject;
  final String joinCode;
  final String status;
  final String? gradeLevel;
  final String? description;
  final int memberCount;
  final int materialCount;

  factory ClassroomModel.fromJson(Map<String, dynamic> json) {
    final count = json['_count'] as Map<String, dynamic>?;
    return ClassroomModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      subject: (json['subject'] ?? '').toString(),
      joinCode: (json['joinCode'] ?? '').toString(),
      status: (json['status'] ?? 'ACTIVE').toString(),
      gradeLevel: json['gradeLevel']?.toString(),
      description: json['description']?.toString(),
      memberCount: (count?['members'] as num?)?.toInt() ?? 0,
      materialCount: (count?['materials'] as num?)?.toInt() ?? 0,
    );
  }
}

class AssessmentQuestionModel {
  const AssessmentQuestionModel({
    required this.id,
    required this.questionOrder,
    required this.questionType,
    required this.prompt,
    required this.points,
    this.options = const [],
    this.difficulty = 'MEDIUM',
  });

  final String id;
  final int questionOrder;
  final String questionType;
  final String prompt;
  final double points;
  final List<String> options;
  final String difficulty;

  factory AssessmentQuestionModel.fromJson(Map<String, dynamic> json) {
    final rawOpts = json['options'];
    return AssessmentQuestionModel(
      id: (json['id'] ?? '').toString(),
      questionOrder: (json['questionOrder'] as num?)?.toInt() ?? 1,
      questionType: (json['questionType'] ?? 'MULTIPLE_CHOICE').toString(),
      prompt: (json['prompt'] ?? '').toString(),
      points: (json['points'] as num?)?.toDouble() ?? 10,
      options: rawOpts is List ? rawOpts.map((e) => e.toString()).toList() : const [],
      difficulty: (json['difficulty'] ?? 'MEDIUM').toString(),
    );
  }
}

class GameConfigModel {
  const GameConfigModel({
    required this.materialId,
    required this.gameType,
    required this.title,
    required this.instructions,
    required this.timeLimitSeconds,
    required this.maxPossibleScore,
    required this.items,
    this.gridSize,
    this.entries,
  });

  final String materialId;
  final String gameType;
  final String title;
  final String instructions;
  final int timeLimitSeconds;
  final int maxPossibleScore;
  final List<Map<String, dynamic>> items;
  final Map<String, int>? gridSize;
  final List<Map<String, dynamic>>? entries;

  factory GameConfigModel.fromJson(Map<String, dynamic> json, {String materialId = ''}) {
    final settings = (json['settings'] as Map<String, dynamic>?) ?? const {};
    final rawItems = (json['items'] as List?) ?? const [];
    final rawEntries = json['entries'] as List?;
    final rawGrid = json['grid_size'] as Map<String, dynamic>?;

    return GameConfigModel(
      materialId: materialId,
      gameType: (json['game_type'] ?? 'word_matching').toString(),
      title: (json['title'] ?? 'Game Edukatif').toString(),
      instructions: (json['instructions'] ?? '').toString(),
      timeLimitSeconds: (settings['time_limit_seconds'] as num?)?.toInt() ?? 120,
      maxPossibleScore: (json['max_possible_score'] as num?)?.toInt() ?? 100,
      items: rawItems.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList(),
      gridSize: rawGrid != null
          ? {
              'rows': (rawGrid['rows'] as num?)?.toInt() ?? 6,
              'cols': (rawGrid['cols'] as num?)?.toInt() ?? 6,
            }
          : null,
      entries: rawEntries?.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList(),
    );
  }
}
