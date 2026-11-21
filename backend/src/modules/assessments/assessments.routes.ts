import { Router } from 'express';
import { z } from 'zod';
import {
  AssessmentStatus,
  AssessmentType,
  AttemptStatus,
  DifficultyLevel,
  MemberStatus,
  Prisma,
  QuestionType,
  UserRole,
} from '@prisma/client';
import { prisma } from '../../config/prisma';
import { AppError } from '../../common/errors';
import { requireAuth, requireRole } from '../../common/middleware/auth';
import { validateBody } from '../../common/middleware/validate';
import { sendSuccess } from '../../common/response';
import { computeFinalScore, gradeObjectiveAnswers } from './grading';

const questionInputSchema = z.object({
  questionType: z.nativeEnum(QuestionType),
  difficulty: z.nativeEnum(DifficultyLevel).default(DifficultyLevel.MEDIUM),
  prompt: z.string().trim().min(3),
  options: z.array(z.string().trim().min(1)).nullable().optional(),
  correctAnswer: z.string().trim().min(1),
  explanation: z.string().trim().nullable().optional(),
  points: z.number().positive().default(10),
  sourceReference: z.record(z.unknown()).nullable().optional(),
});

const createAssessmentSchema = z.object({
  sourceContentId: z.string().uuid().optional(),
  title: z.string().trim().min(2).max(255),
  instructions: z.string().trim().max(2000).optional(),
  assessmentType: z.nativeEnum(AssessmentType).default(AssessmentType.SELF_QUIZ),
  timeLimitSeconds: z.number().int().positive().nullable().optional(),
  maxAttempts: z.number().int().min(1).max(20).default(1),
  passingScore: z.number().min(0).max(100).default(70),
  shuffleQuestions: z.boolean().default(false),
  showExplanations: z.boolean().default(true),
  availableFrom: z.string().datetime().nullable().optional(),
  availableUntil: z.string().datetime().nullable().optional(),
  questions: z.array(questionInputSchema).optional(),
});

const updateAssessmentSchema = z.object({
  title: z.string().trim().min(2).max(255).optional(),
  instructions: z.string().trim().max(2000).nullable().optional(),
  timeLimitSeconds: z.number().int().positive().nullable().optional(),
  maxAttempts: z.number().int().min(1).max(20).optional(),
  passingScore: z.number().min(0).max(100).optional(),
  shuffleQuestions: z.boolean().optional(),
  showExplanations: z.boolean().optional(),
  availableFrom: z.string().datetime().nullable().optional(),
  availableUntil: z.string().datetime().nullable().optional(),
});

const saveAnswersSchema = z.object({
  answers: z
    .array(
      z.object({
        questionId: z.string().uuid(),
        studentAnswer: z.string().max(10000).nullable(),
      }),
    )
    .min(1),
});

const manualGradeSchema = z.object({
  grades: z
    .array(
      z.object({
        questionId: z.string().uuid(),
        awardedPoints: z.number().min(0),
        isCorrect: z.boolean().optional(),
        teacherFeedback: z.string().trim().max(2000).optional(),
      }),
    )
    .min(1),
});

const QUESTION_TYPE_MAP: Record<string, QuestionType> = {
  multiple_choice: QuestionType.MULTIPLE_CHOICE,
  true_false: QuestionType.TRUE_FALSE,
  short_answer: QuestionType.SHORT_ANSWER,
  essay: QuestionType.ESSAY,
};

const DIFFICULTY_MAP: Record<string, DifficultyLevel> = {
  easy: DifficultyLevel.EASY,
  medium: DifficultyLevel.MEDIUM,
  hard: DifficultyLevel.HARD,
};

export const assessmentsRouter = Router();

assessmentsRouter.post(
  '/classrooms/:classroomId/assessments',
  requireAuth,
  requireRole(UserRole.TEACHER),
  validateBody(createAssessmentSchema),
  async (req, res, next) => {
    try {
      const teacherId = req.auth!.userId;
      const classroom = await prisma.classroom.findFirst({
        where: { id: req.params.classroomId, teacherId, deletedAt: null },
      });
      if (!classroom) {
        throw new AppError(404, 'NOT_FOUND', 'Classroom not found.');
      }

      let questionsToCreate = req.body.questions as Array<z.infer<typeof questionInputSchema>> | undefined;

      // Snapshot questions from an approved AI quiz content if sourceContentId is given
      if ((!questionsToCreate || questionsToCreate.length === 0) && req.body.sourceContentId) {
        const content = await prisma.generatedContent.findFirst({
          where: { id: req.body.sourceContentId, teacherId, deletedAt: null },
          include: { versions: { orderBy: { versionNumber: 'desc' } } },
        });
        if (!content || !content.approvedVersionId) {
          throw new AppError(
            400,
            'CONTENT_NOT_APPROVED',
            'Source quiz content must be approved before creating an assessment.',
          );
        }
        const approvedVersion = content.versions.find((v) => v.id === content.approvedVersionId);
        const payload = (approvedVersion?.payload ?? {}) as {
          questions?: Array<Record<string, unknown>>;
        };
        questionsToCreate = (payload.questions ?? []).map((q) => ({
          questionType:
            QUESTION_TYPE_MAP[String(q.type ?? 'multiple_choice').toLowerCase()] ??
            QuestionType.MULTIPLE_CHOICE,
          difficulty:
            DIFFICULTY_MAP[String(q.difficulty ?? 'medium').toLowerCase()] ?? DifficultyLevel.MEDIUM,
          prompt: String(q.question ?? ''),
          options: Array.isArray(q.options) ? q.options.map(String) : null,
          correctAnswer: String(q.correct_answer ?? ''),
          explanation: q.explanation ? String(q.explanation) : null,
          points: typeof q.points === 'number' && q.points > 0 ? q.points : 10,
          sourceReference: (q.source_reference as Record<string, unknown> | undefined) ?? null,
        }));
      }

      if (!questionsToCreate || questionsToCreate.length === 0) {
        throw new AppError(400, 'VALIDATION_ERROR', 'At least one question is required.');
      }

      const totalPoints = questionsToCreate.reduce((sum, q) => sum + q.points, 0);

      const assessment = await prisma.assessment.create({
        data: {
          classroomId: classroom.id,
          teacherId,
          sourceContentId: req.body.sourceContentId ?? null,
          title: req.body.title,
          instructions: req.body.instructions,
          assessmentType: req.body.assessmentType,
          timeLimitSeconds: req.body.timeLimitSeconds ?? null,
          maxAttempts: req.body.maxAttempts,
          passingScore: req.body.passingScore,
          totalPoints,
          shuffleQuestions: req.body.shuffleQuestions,
          showExplanations: req.body.showExplanations,
          availableFrom: req.body.availableFrom ? new Date(req.body.availableFrom) : null,
          availableUntil: req.body.availableUntil ? new Date(req.body.availableUntil) : null,
          questions: {
            create: questionsToCreate.map((q, idx) => ({
              questionOrder: idx + 1,
              questionType: q.questionType,
              difficulty: q.difficulty,
              prompt: q.prompt,
              options: q.options ? (q.options as Prisma.InputJsonValue) : Prisma.JsonNull,
              correctAnswer: q.correctAnswer,
              explanation: q.explanation ?? null,
              points: q.points,
              sourceReference: q.sourceReference
                ? (q.sourceReference as Prisma.InputJsonValue)
                : Prisma.JsonNull,
            })),
          },
        },
        include: { questions: { orderBy: { questionOrder: 'asc' } } },
      });

      sendSuccess(req, res, assessment, 201);
    } catch (err) {
      next(err);
    }
  },
);

assessmentsRouter.get('/classrooms/:classroomId/assessments', requireAuth, async (req, res, next) => {
  try {
    const { userId, role } = req.auth!;
    if (role === UserRole.TEACHER) {
      const classroom = await prisma.classroom.findFirst({
        where: { id: req.params.classroomId, teacherId: userId, deletedAt: null },
      });
      if (!classroom) throw new AppError(404, 'NOT_FOUND', 'Classroom not found.');

      const items = await prisma.assessment.findMany({
        where: { classroomId: classroom.id, deletedAt: null },
        include: { _count: { select: { questions: true, attempts: true } } },
        orderBy: { createdAt: 'desc' },
      });
      sendSuccess(req, res, items);
      return;
    }

    const membership = await prisma.classroomMember.findFirst({
      where: { classroomId: req.params.classroomId, studentId: userId, status: MemberStatus.ACTIVE },
    });
    if (!membership) throw new AppError(403, 'FORBIDDEN', 'You are not enrolled in this classroom.');

    const items = await prisma.assessment.findMany({
      where: {
        classroomId: req.params.classroomId,
        deletedAt: null,
        status: { in: [AssessmentStatus.PUBLISHED, AssessmentStatus.CLOSED] },
      },
      include: {
        _count: { select: { questions: true } },
        attempts: { where: { studentId: userId }, orderBy: { attemptNumber: 'desc' } },
      },
      orderBy: { createdAt: 'desc' },
    });
    sendSuccess(req, res, items);
  } catch (err) {
    next(err);
  }
});

assessmentsRouter.get('/student/assessments', requireAuth, requireRole(UserRole.STUDENT), async (req, res, next) => {
  try {
    const studentId = req.auth!.userId;
    const memberships = await prisma.classroomMember.findMany({
      where: { studentId, status: MemberStatus.ACTIVE },
      select: { classroomId: true },
    });
    const classroomIds = memberships.map((m) => m.classroomId);

    const items = await prisma.assessment.findMany({
      where: {
        classroomId: { in: classroomIds },
        deletedAt: null,
        status: { in: [AssessmentStatus.PUBLISHED, AssessmentStatus.CLOSED] },
      },
      include: {
        classroom: { select: { id: true, name: true, subject: true } },
        _count: { select: { questions: true } },
        attempts: { where: { studentId }, orderBy: { attemptNumber: 'desc' } },
      },
      orderBy: [{ availableUntil: 'asc' }, { createdAt: 'desc' }],
    });
    sendSuccess(req, res, items);
  } catch (err) {
    next(err);
  }
});

assessmentsRouter.get('/assessments/:id', requireAuth, async (req, res, next) => {
  try {
    const { userId, role } = req.auth!;
    const assessment = await prisma.assessment.findFirst({
      where: { id: req.params.id, deletedAt: null },
      include: { questions: { orderBy: { questionOrder: 'asc' } } },
    });
    if (!assessment) throw new AppError(404, 'NOT_FOUND', 'Assessment not found.');

    if (role === UserRole.TEACHER) {
      if (assessment.teacherId !== userId) {
        throw new AppError(403, 'FORBIDDEN', 'You do not own this assessment.');
      }
      sendSuccess(req, res, assessment);
      return;
    }

    const member = await prisma.classroomMember.findFirst({
      where: { classroomId: assessment.classroomId, studentId: userId, status: MemberStatus.ACTIVE },
    });
    if (!member) throw new AppError(403, 'FORBIDDEN', 'You are not enrolled in this classroom.');
    if (assessment.status === AssessmentStatus.DRAFT) {
      throw new AppError(404, 'NOT_FOUND', 'Assessment not found.');
    }

    // Strip answer keys & explanations from student assessment payload
    sendSuccess(req, res, {
      ...assessment,
      questions: assessment.questions.map((q) => ({
        id: q.id,
        questionOrder: q.questionOrder,
        questionType: q.questionType,
        difficulty: q.difficulty,
        prompt: q.prompt,
        options: q.options,
        points: Number(q.points),
      })),
    });
  } catch (err) {
    next(err);
  }
});

assessmentsRouter.patch(
  '/assessments/:id',
  requireAuth,
  requireRole(UserRole.TEACHER),
  validateBody(updateAssessmentSchema),
  async (req, res, next) => {
    try {
      const assessment = await prisma.assessment.findFirst({
        where: { id: req.params.id, teacherId: req.auth!.userId, deletedAt: null },
      });
      if (!assessment) throw new AppError(404, 'NOT_FOUND', 'Assessment not found.');
      if (assessment.status !== AssessmentStatus.DRAFT) {
        throw new AppError(409, 'CONFLICT', 'Only DRAFT assessments can be modified.');
      }

      const updated = await prisma.assessment.update({
        where: { id: assessment.id },
        data: {
          ...req.body,
          availableFrom:
            req.body.availableFrom !== undefined
              ? req.body.availableFrom
                ? new Date(req.body.availableFrom)
                : null
              : undefined,
          availableUntil:
            req.body.availableUntil !== undefined
              ? req.body.availableUntil
                ? new Date(req.body.availableUntil)
                : null
              : undefined,
        },
      });
      sendSuccess(req, res, updated);
    } catch (err) {
      next(err);
    }
  },
);

assessmentsRouter.post(
  '/assessments/:id/publish',
  requireAuth,
  requireRole(UserRole.TEACHER),
  async (req, res, next) => {
    try {
      const assessment = await prisma.assessment.findFirst({
        where: { id: req.params.id, teacherId: req.auth!.userId, deletedAt: null },
        include: { _count: { select: { questions: true } } },
      });
      if (!assessment) throw new AppError(404, 'NOT_FOUND', 'Assessment not found.');
      if (assessment._count.questions === 0) {
        throw new AppError(400, 'VALIDATION_ERROR', 'Cannot publish an assessment with zero questions.');
      }
      const published = await prisma.assessment.update({
        where: { id: assessment.id },
        data: { status: AssessmentStatus.PUBLISHED },
      });
      sendSuccess(req, res, published);
    } catch (err) {
      next(err);
    }
  },
);

assessmentsRouter.post(
  '/assessments/:id/close',
  requireAuth,
  requireRole(UserRole.TEACHER),
  async (req, res, next) => {
    try {
      const assessment = await prisma.assessment.findFirst({
        where: { id: req.params.id, teacherId: req.auth!.userId, deletedAt: null },
      });
      if (!assessment) throw new AppError(404, 'NOT_FOUND', 'Assessment not found.');
      const closed = await prisma.assessment.update({
        where: { id: assessment.id },
        data: { status: AssessmentStatus.CLOSED },
      });
      sendSuccess(req, res, closed);
    } catch (err) {
      next(err);
    }
  },
);

assessmentsRouter.post(
  '/assessments/:id/attempts',
  requireAuth,
  requireRole(UserRole.STUDENT),
  async (req, res, next) => {
    try {
      const studentId = req.auth!.userId;
      const assessment = await prisma.assessment.findFirst({
        where: { id: req.params.id, deletedAt: null },
        include: { questions: { orderBy: { questionOrder: 'asc' } } },
      });
      if (!assessment) throw new AppError(404, 'NOT_FOUND', 'Assessment not found.');

      const member = await prisma.classroomMember.findFirst({
        where: { classroomId: assessment.classroomId, studentId, status: MemberStatus.ACTIVE },
      });
      if (!member) throw new AppError(403, 'FORBIDDEN', 'You are not enrolled in this classroom.');

      const now = new Date();
      if (
        assessment.status !== AssessmentStatus.PUBLISHED ||
        (assessment.availableFrom && now < assessment.availableFrom) ||
        (assessment.availableUntil && now > assessment.availableUntil)
      ) {
        throw new AppError(409, 'ASSESSMENT_CLOSED', 'Assessment is not currently open for attempts.');
      }

      const priorAttempts = await prisma.assessmentAttempt.findMany({
        where: { assessmentId: assessment.id, studentId },
        orderBy: { attemptNumber: 'desc' },
      });

      const inProgress = priorAttempts.find((a) => a.status === AttemptStatus.IN_PROGRESS);
      if (inProgress) {
        sendSuccess(req, res, {
          attempt: inProgress,
          questions: assessment.questions.map((q) => ({
            id: q.id,
            questionOrder: q.questionOrder,
            questionType: q.questionType,
            difficulty: q.difficulty,
            prompt: q.prompt,
            options: q.options,
            points: Number(q.points),
          })),
        });
        return;
      }

      if (priorAttempts.length >= assessment.maxAttempts) {
        throw new AppError(
          409,
          'DUPLICATE_SUBMISSION',
          `Maximum allowed attempts (${assessment.maxAttempts}) already used.`,
        );
      }

      const expiresAt = assessment.timeLimitSeconds
        ? new Date(now.getTime() + assessment.timeLimitSeconds * 1000)
        : null;

      const attempt = await prisma.assessmentAttempt.create({
        data: {
          assessmentId: assessment.id,
          studentId,
          attemptNumber: priorAttempts.length + 1,
          status: AttemptStatus.IN_PROGRESS,
          expiresAt,
        },
      });

      sendSuccess(
        req,
        res,
        {
          attempt,
          questions: assessment.questions.map((q) => ({
            id: q.id,
            questionOrder: q.questionOrder,
            questionType: q.questionType,
            difficulty: q.difficulty,
            prompt: q.prompt,
            options: q.options,
            points: Number(q.points),
          })),
        },
        201,
      );
    } catch (err) {
      next(err);
    }
  },
);

assessmentsRouter.put(
  '/attempts/:attemptId/answers',
  requireAuth,
  requireRole(UserRole.STUDENT),
  validateBody(saveAnswersSchema),
  async (req, res, next) => {
    try {
      const attempt = await prisma.assessmentAttempt.findFirst({
        where: { id: req.params.attemptId, studentId: req.auth!.userId },
      });
      if (!attempt) throw new AppError(404, 'NOT_FOUND', 'Attempt not found.');
      if (attempt.status !== AttemptStatus.IN_PROGRESS) {
        throw new AppError(409, 'DUPLICATE_SUBMISSION', 'Attempt has already been submitted.');
      }

      await prisma.$transaction(
        req.body.answers.map((ans: { questionId: string; studentAnswer: string | null }) =>
          prisma.assessmentAnswer.upsert({
            where: {
              attemptId_questionId: {
                attemptId: attempt.id,
                questionId: ans.questionId,
              },
            },
            update: { studentAnswer: ans.studentAnswer, answeredAt: new Date() },
            create: {
              attemptId: attempt.id,
              questionId: ans.questionId,
              studentAnswer: ans.studentAnswer,
            },
          }),
        ),
      );

      sendSuccess(req, res, { savedCount: req.body.answers.length });
    } catch (err) {
      next(err);
    }
  },
);

assessmentsRouter.post(
  '/attempts/:attemptId/submit',
  requireAuth,
  requireRole(UserRole.STUDENT),
  async (req, res, next) => {
    try {
      const studentId = req.auth!.userId;
      const attempt = await prisma.assessmentAttempt.findFirst({
        where: { id: req.params.attemptId, studentId },
        include: {
          assessment: { include: { questions: true } },
          answers: true,
        },
      });
      if (!attempt) throw new AppError(404, 'NOT_FOUND', 'Attempt not found.');
      if (attempt.status !== AttemptStatus.IN_PROGRESS) {
        throw new AppError(409, 'DUPLICATE_SUBMISSION', 'Attempt was already submitted.');
      }

      const graded = gradeObjectiveAnswers(
        attempt.assessment.questions.map((q) => ({
          id: q.id,
          questionType: q.questionType,
          correctAnswer: q.correctAnswer,
          points: Number(q.points),
        })),
        attempt.answers.map((a) => ({
          questionId: a.questionId,
          studentAnswer: a.studentAnswer,
        })),
      );

      const finalScore = computeFinalScore({
        autoScore: graded.autoScore,
        manualScore: 0,
        maxScore: graded.maxScore,
        passingScorePercent: Number(attempt.assessment.passingScore),
      });

      const finalStatus = graded.hasPendingManualGrading
        ? AttemptStatus.SUBMITTED
        : AttemptStatus.GRADED;

      const updatedAttempt = await prisma.$transaction(async (tx) => {
        for (const r of graded.results) {
          await tx.assessmentAnswer.upsert({
            where: { attemptId_questionId: { attemptId: attempt.id, questionId: r.questionId } },
            update: {
              isCorrect: r.isCorrect,
              awardedPoints: r.awardedPoints,
              requiresManualGrading: r.requiresManualGrading,
            },
            create: {
              attemptId: attempt.id,
              questionId: r.questionId,
              studentAnswer: null,
              isCorrect: r.isCorrect,
              awardedPoints: r.awardedPoints,
              requiresManualGrading: r.requiresManualGrading,
            },
          });
        }

        const updated = await tx.assessmentAttempt.update({
          where: { id: attempt.id },
          data: {
            status: finalStatus,
            submittedAt: new Date(),
            gradedAt: finalStatus === AttemptStatus.GRADED ? new Date() : null,
            autoScore: graded.autoScore,
            totalScore: finalScore.totalScore,
            percentage: finalScore.percentage,
            passed: finalStatus === AttemptStatus.GRADED ? finalScore.passed : null,
          },
        });

        await tx.learningActivity.create({
          data: {
            studentId,
            classroomId: attempt.assessment.classroomId,
            activityType: 'ASSESSMENT_SUBMITTED',
            referenceType: 'ASSESSMENT',
            referenceId: attempt.assessmentId,
            metadata: { attemptId: attempt.id, percentage: finalScore.percentage },
          },
        });

        return updated;
      });

      sendSuccess(req, res, {
        ...updatedAttempt,
        hasPendingManualGrading: graded.hasPendingManualGrading,
      });
    } catch (err) {
      next(err);
    }
  },
);

assessmentsRouter.get(
  '/assessments/:id/attempts',
  requireAuth,
  requireRole(UserRole.TEACHER),
  async (req, res, next) => {
    try {
      const assessment = await prisma.assessment.findFirst({
        where: { id: req.params.id, teacherId: req.auth!.userId, deletedAt: null },
      });
      if (!assessment) throw new AppError(404, 'NOT_FOUND', 'Assessment not found.');

      const attempts = await prisma.assessmentAttempt.findMany({
        where: { assessmentId: assessment.id },
        include: {
          student: {
            select: {
              id: true,
              email: true,
              profile: { select: { fullName: true, displayName: true } },
            },
          },
        },
        orderBy: { submittedAt: 'desc' },
      });
      sendSuccess(req, res, attempts);
    } catch (err) {
      next(err);
    }
  },
);

assessmentsRouter.get('/attempts/:attemptId', requireAuth, async (req, res, next) => {
  try {
    const attempt = await prisma.assessmentAttempt.findUnique({
      where: { id: req.params.attemptId },
      include: {
        assessment: { select: { id: true, title: true, teacherId: true, showExplanations: true } },
        answers: { include: { question: true } },
      },
    });
    if (!attempt) throw new AppError(404, 'NOT_FOUND', 'Attempt not found.');

    const { userId, role } = req.auth!;
    if (role === UserRole.TEACHER && attempt.assessment.teacherId !== userId) {
      throw new AppError(403, 'FORBIDDEN', 'Access denied to this assessment attempt.');
    }
    if (role === UserRole.STUDENT && attempt.studentId !== userId) {
      throw new AppError(403, 'FORBIDDEN', 'You cannot view another student attempt.');
    }

    sendSuccess(req, res, attempt);
  } catch (err) {
    next(err);
  }
});

assessmentsRouter.post(
  '/attempts/:attemptId/grade',
  requireAuth,
  requireRole(UserRole.TEACHER),
  validateBody(manualGradeSchema),
  async (req, res, next) => {
    try {
      const teacherId = req.auth!.userId;
      const attempt = await prisma.assessmentAttempt.findUnique({
        where: { id: req.params.attemptId },
        include: { assessment: { include: { questions: true } }, answers: true },
      });
      if (!attempt || attempt.assessment.teacherId !== teacherId) {
        throw new AppError(404, 'NOT_FOUND', 'Attempt not found.');
      }

      const questionMap = new Map(attempt.assessment.questions.map((q) => [q.id, q]));

      for (const g of req.body.grades as Array<{
        questionId: string;
        awardedPoints: number;
        isCorrect?: boolean;
        teacherFeedback?: string;
      }>) {
        const q = questionMap.get(g.questionId);
        if (!q) {
          throw new AppError(400, 'VALIDATION_ERROR', `Unknown questionId ${g.questionId}.`);
        }
        if (g.awardedPoints > Number(q.points)) {
          throw new AppError(
            400,
            'VALIDATION_ERROR',
            `Awarded points (${g.awardedPoints}) exceed max question points (${Number(q.points)}).`,
          );
        }
      }

      const updated = await prisma.$transaction(async (tx) => {
        for (const g of req.body.grades) {
          await tx.assessmentAnswer.updateMany({
            where: { attemptId: attempt.id, questionId: g.questionId },
            data: {
              awardedPoints: g.awardedPoints,
              isCorrect: g.isCorrect ?? g.awardedPoints > 0,
              requiresManualGrading: false,
              teacherFeedback: g.teacherFeedback ?? null,
            },
          });
        }

        const refreshedAnswers = await tx.assessmentAnswer.findMany({
          where: { attemptId: attempt.id },
          include: { question: true },
        });

        let autoScore = 0;
        let manualScore = 0;
        let pendingRemaining = false;

        for (const ans of refreshedAnswers) {
          if (ans.requiresManualGrading) pendingRemaining = true;
          if (
            ans.question.questionType === QuestionType.MULTIPLE_CHOICE ||
            ans.question.questionType === QuestionType.TRUE_FALSE
          ) {
            autoScore += Number(ans.awardedPoints);
          } else {
            manualScore += Number(ans.awardedPoints);
          }
        }

        const maxScore = attempt.assessment.questions.reduce((s, q) => s + Number(q.points), 0);
        const scores = computeFinalScore({
          autoScore,
          manualScore,
          maxScore,
          passingScorePercent: Number(attempt.assessment.passingScore),
        });

        return tx.assessmentAttempt.update({
          where: { id: attempt.id },
          data: {
            status: pendingRemaining ? AttemptStatus.SUBMITTED : AttemptStatus.GRADED,
            gradedBy: teacherId,
            gradedAt: pendingRemaining ? null : new Date(),
            autoScore,
            manualScore,
            totalScore: scores.totalScore,
            percentage: scores.percentage,
            passed: pendingRemaining ? null : scores.passed,
          },
        });
      });

      sendSuccess(req, res, updated);
    } catch (err) {
      next(err);
    }
  },
);

assessmentsRouter.get('/attempts/:attemptId/result', requireAuth, async (req, res, next) => {
  try {
    const attempt = await prisma.assessmentAttempt.findUnique({
      where: { id: req.params.attemptId },
      include: {
        assessment: {
          select: {
            id: true,
            title: true,
            teacherId: true,
            totalPoints: true,
            passingScore: true,
            showExplanations: true,
          },
        },
        answers: {
          include: { question: true },
          orderBy: { question: { questionOrder: 'asc' } },
        },
      },
    });
    if (!attempt) throw new AppError(404, 'NOT_FOUND', 'Attempt not found.');

    const { userId, role } = req.auth!;
    if (role === UserRole.STUDENT && attempt.studentId !== userId) {
      throw new AppError(403, 'FORBIDDEN', 'You cannot access another student result.');
    }
    if (role === UserRole.TEACHER && attempt.assessment.teacherId !== userId) {
      throw new AppError(403, 'FORBIDDEN', 'You do not own this assessment.');
    }
    if (attempt.status === AttemptStatus.IN_PROGRESS) {
      throw new AppError(409, 'CONFLICT', 'Submit the attempt before viewing results.');
    }

    const showExpl = role === UserRole.TEACHER || attempt.assessment.showExplanations;

    sendSuccess(req, res, {
      attemptId: attempt.id,
      assessmentTitle: attempt.assessment.title,
      status: attempt.status,
      autoScore: Number(attempt.autoScore),
      manualScore: Number(attempt.manualScore),
      totalScore: Number(attempt.totalScore),
      maxScore: Number(attempt.assessment.totalPoints),
      percentage: Number(attempt.percentage),
      passed: attempt.passed,
      submittedAt: attempt.submittedAt,
      gradedAt: attempt.gradedAt,
      items: attempt.answers.map((a) => ({
        questionId: a.questionId,
        questionOrder: a.question.questionOrder,
        questionType: a.question.questionType,
        prompt: a.question.prompt,
        studentAnswer: a.studentAnswer,
        correctAnswer: showExpl ? a.question.correctAnswer : null,
        explanation: showExpl ? a.question.explanation : null,
        isCorrect: a.isCorrect,
        awardedPoints: Number(a.awardedPoints),
        maxPoints: Number(a.question.points),
        requiresManualGrading: a.requiresManualGrading,
        teacherFeedback: a.teacherFeedback,
      })),
    });
  } catch (err) {
    next(err);
  }
});
