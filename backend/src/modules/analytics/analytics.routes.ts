import { Router } from 'express';
import { z } from 'zod';
import {
  AssessmentStatus,
  AttemptStatus,
  ContentStatus,
  MemberStatus,
  ProgressStatus,
  UserRole,
} from '@prisma/client';
import { prisma } from '../../config/prisma';
import { AppError } from '../../common/errors';
import { requireAuth, requireRole } from '../../common/middleware/auth';
import { validateBody } from '../../common/middleware/validate';
import { sendSuccess } from '../../common/response';

const upsertProgressSchema = z.object({
  completionPercentage: z.number().int().min(0).max(100),
  timeSpentSecondsDelta: z.number().int().min(0).max(14400).default(0),
});

export const analyticsRouter = Router();

analyticsRouter.get('/teacher/dashboard', requireAuth, requireRole(UserRole.TEACHER), async (req, res, next) => {
  try {
    const teacherId = req.auth!.userId;
    const [
      documentCount,
      pendingDraftCount,
      classroomCount,
      pendingGradingCount,
      recentDocuments,
      recentContents,
    ] = await Promise.all([
      prisma.document.count({ where: { teacherId, deletedAt: null } }),
      prisma.generatedContent.count({
        where: { teacherId, deletedAt: null, status: { in: [ContentStatus.DRAFT, ContentStatus.IN_REVIEW] } },
      }),
      prisma.classroom.count({ where: { teacherId, deletedAt: null } }),
      prisma.assessmentAttempt.count({
        where: {
          status: AttemptStatus.SUBMITTED,
          assessment: { teacherId, deletedAt: null },
        },
      }),
      prisma.document.findMany({
        where: { teacherId, deletedAt: null },
        select: { id: true, title: true, subject: true, status: true, createdAt: true },
        orderBy: { createdAt: 'desc' },
        take: 5,
      }),
      prisma.generatedContent.findMany({
        where: { teacherId, deletedAt: null },
        select: { id: true, title: true, contentType: true, status: true, updatedAt: true },
        orderBy: { updatedAt: 'desc' },
        take: 5,
      }),
    ]);

    sendSuccess(req, res, {
      metrics: {
        documentCount,
        pendingDraftCount,
        classroomCount,
        pendingGradingCount,
      },
      recentDocuments,
      recentContents,
    });
  } catch (err) {
    next(err);
  }
});

analyticsRouter.get('/student/dashboard', requireAuth, requireRole(UserRole.STUDENT), async (req, res, next) => {
  try {
    const studentId = req.auth!.userId;
    const memberships = await prisma.classroomMember.findMany({
      where: { studentId, status: MemberStatus.ACTIVE },
      include: { classroom: { select: { id: true, name: true, subject: true, gradeLevel: true } } },
    });
    const classroomIds = memberships.map((m) => m.classroomId);

    const [latestMaterials, openAssessments, progressRecords, recentAttempts] = await Promise.all([
      prisma.classroomMaterial.findMany({
        where: { classroomId: { in: classroomIds }, isVisible: true },
        include: {
          classroom: { select: { name: true, subject: true } },
          content: { select: { contentType: true, gameType: true } },
        },
        orderBy: { publishedAt: 'desc' },
        take: 8,
      }),
      prisma.assessment.findMany({
        where: {
          classroomId: { in: classroomIds },
          deletedAt: null,
          status: AssessmentStatus.PUBLISHED,
        },
        include: { classroom: { select: { name: true, subject: true } } },
        orderBy: [{ availableUntil: 'asc' }, { createdAt: 'desc' }],
        take: 8,
      }),
      prisma.studentProgress.findMany({
        where: { studentId },
      }),
      prisma.assessmentAttempt.findMany({
        where: { studentId, status: AttemptStatus.GRADED },
        include: { assessment: { select: { title: true } } },
        orderBy: { gradedAt: 'desc' },
        take: 5,
      }),
    ]);

    const completedMaterials = progressRecords.filter(
      (p) => p.status === ProgressStatus.COMPLETED,
    ).length;
    const avgScore =
      recentAttempts.length > 0
        ? Number(
            (
              recentAttempts.reduce((sum, a) => sum + Number(a.percentage), 0) /
              recentAttempts.length
            ).toFixed(2),
          )
        : 0;

    sendSuccess(req, res, {
      enrolledClassrooms: memberships.map((m) => m.classroom),
      latestMaterials,
      upcomingAssessments: openAssessments,
      recentScores: recentAttempts.map((a) => ({
        attemptId: a.id,
        assessmentTitle: a.assessment.title,
        percentage: Number(a.percentage),
        passed: a.passed,
        gradedAt: a.gradedAt,
      })),
      summary: {
        classroomCount: memberships.length,
        completedMaterials,
        averageScore: avgScore,
      },
    });
  } catch (err) {
    next(err);
  }
});

analyticsRouter.post(
  '/student/progress/:materialId',
  requireAuth,
  requireRole(UserRole.STUDENT),
  validateBody(upsertProgressSchema),
  async (req, res, next) => {
    try {
      const studentId = req.auth!.userId;
      const material = await prisma.classroomMaterial.findUnique({
        where: { id: req.params.materialId },
      });
      if (!material || !material.isVisible) {
        throw new AppError(404, 'NOT_FOUND', 'Material not found.');
      }

      const member = await prisma.classroomMember.findFirst({
        where: { classroomId: material.classroomId, studentId, status: MemberStatus.ACTIVE },
      });
      if (!member) {
        throw new AppError(403, 'FORBIDDEN', 'You are not enrolled in this classroom.');
      }

      const pct = req.body.completionPercentage;
      const status =
        pct >= 100
          ? ProgressStatus.COMPLETED
          : pct > 0
            ? ProgressStatus.IN_PROGRESS
            : ProgressStatus.NOT_STARTED;

      const progress = await prisma.studentProgress.upsert({
        where: { studentId_materialId: { studentId, materialId: material.id } },
        update: {
          status,
          completionPercentage: pct,
          timeSpentSeconds: { increment: req.body.timeSpentSecondsDelta },
          lastAccessedAt: new Date(),
          ...(status === ProgressStatus.COMPLETED ? { completedAt: new Date() } : {}),
        },
        create: {
          studentId,
          classroomId: material.classroomId,
          materialId: material.id,
          status,
          completionPercentage: pct,
          timeSpentSeconds: req.body.timeSpentSecondsDelta,
          lastAccessedAt: new Date(),
          completedAt: status === ProgressStatus.COMPLETED ? new Date() : null,
        },
      });

      sendSuccess(req, res, progress);
    } catch (err) {
      next(err);
    }
  },
);

analyticsRouter.get('/student/progress', requireAuth, requireRole(UserRole.STUDENT), async (req, res, next) => {
  try {
    const studentId = req.auth!.userId;
    const [progress, activities, gradedAttempts] = await Promise.all([
      prisma.studentProgress.findMany({
        where: { studentId },
        include: {
          material: { select: { title: true, content: { select: { contentType: true } } } },
          classroom: { select: { name: true, subject: true } },
        },
        orderBy: { updatedAt: 'desc' },
      }),
      prisma.learningActivity.findMany({
        where: { studentId },
        orderBy: { occurredAt: 'desc' },
        take: 25,
      }),
      prisma.assessmentAttempt.findMany({
        where: { studentId, status: AttemptStatus.GRADED },
        include: { assessment: { select: { title: true, passingScore: true } } },
        orderBy: { gradedAt: 'desc' },
        take: 20,
      }),
    ]);

    sendSuccess(req, res, { progress, activities, gradedAttempts });
  } catch (err) {
    next(err);
  }
});

analyticsRouter.get(
  '/classrooms/:classroomId/analytics',
  requireAuth,
  requireRole(UserRole.TEACHER),
  async (req, res, next) => {
    try {
      const classroom = await prisma.classroom.findFirst({
        where: { id: req.params.classroomId, teacherId: req.auth!.userId, deletedAt: null },
      });
      if (!classroom) throw new AppError(404, 'NOT_FOUND', 'Classroom not found.');

      const [studentCount, materialCount, progressList, gradedAttempts] = await Promise.all([
        prisma.classroomMember.count({
          where: { classroomId: classroom.id, status: MemberStatus.ACTIVE },
        }),
        prisma.classroomMaterial.count({
          where: { classroomId: classroom.id, isVisible: true },
        }),
        prisma.studentProgress.findMany({
          where: { classroomId: classroom.id },
        }),
        prisma.assessmentAttempt.findMany({
          where: {
            status: AttemptStatus.GRADED,
            assessment: { classroomId: classroom.id, deletedAt: null },
          },
          include: {
            answers: { include: { question: { select: { id: true, prompt: true, difficulty: true } } } },
          },
        }),
      ]);

      const completedCount = progressList.filter((p) => p.status === ProgressStatus.COMPLETED).length;
      const expectedTotal = Math.max(1, studentCount * materialCount);
      const completionRate =
        studentCount > 0 && materialCount > 0
          ? Number(((completedCount / expectedTotal) * 100).toFixed(2))
          : 0;

      const scores = gradedAttempts.map((a) => Number(a.percentage));
      const averageScore =
        scores.length > 0
          ? Number((scores.reduce((s, v) => s + v, 0) / scores.length).toFixed(2))
          : 0;

      const distribution = { '0-49': 0, '50-69': 0, '70-84': 0, '85-100': 0 };
      for (const s of scores) {
        if (s < 50) distribution['0-49']++;
        else if (s < 70) distribution['50-69']++;
        else if (s < 85) distribution['70-84']++;
        else distribution['85-100']++;
      }

      // Compute most frequently missed questions
      const questionTracker = new Map<string, { prompt: string; total: number; wrong: number }>();
      for (const att of gradedAttempts) {
        for (const ans of att.answers) {
          if (ans.isCorrect === null) continue;
          const entry = questionTracker.get(ans.questionId) ?? {
            prompt: ans.question.prompt,
            total: 0,
            wrong: 0,
          };
          entry.total++;
          if (!ans.isCorrect) entry.wrong++;
          questionTracker.set(ans.questionId, entry);
        }
      }

      const weakQuestions = Array.from(questionTracker.entries())
        .map(([questionId, stat]) => ({
          questionId,
          prompt: stat.prompt,
          totalAttempts: stat.total,
          successRate: Number((((stat.total - stat.wrong) / stat.total) * 100).toFixed(2)),
        }))
        .sort((a, b) => a.successRate - b.successRate)
        .slice(0, 10);

      sendSuccess(req, res, {
        classroomId: classroom.id,
        classroomName: classroom.name,
        totalStudents: studentCount,
        totalMaterials: materialCount,
        completionRate,
        averageScore,
        scoreDistribution: distribution,
        weakQuestions,
      });
    } catch (err) {
      next(err);
    }
  },
);

analyticsRouter.get(
  '/assessments/:id/analytics',
  requireAuth,
  requireRole(UserRole.TEACHER),
  async (req, res, next) => {
    try {
      const assessment = await prisma.assessment.findFirst({
        where: { id: req.params.id, teacherId: req.auth!.userId, deletedAt: null },
        include: {
          questions: { orderBy: { questionOrder: 'asc' } },
          attempts: {
            where: { status: AttemptStatus.GRADED },
            include: { answers: true },
          },
        },
      });
      if (!assessment) throw new AppError(404, 'NOT_FOUND', 'Assessment not found.');

      const attemptsCount = assessment.attempts.length;
      const averageScore =
        attemptsCount > 0
          ? Number(
              (
                assessment.attempts.reduce((s, a) => s + Number(a.percentage), 0) / attemptsCount
              ).toFixed(2),
            )
          : 0;
      const passRate =
        attemptsCount > 0
          ? Number(
              ((assessment.attempts.filter((a) => a.passed).length / attemptsCount) * 100).toFixed(2),
            )
          : 0;

      const questionStats = assessment.questions.map((q) => {
        const related = assessment.attempts.flatMap((a) =>
          a.answers.filter((ans) => ans.questionId === q.id && ans.isCorrect !== null),
        );
        const correct = related.filter((r) => r.isCorrect).length;
        return {
          questionId: q.id,
          questionOrder: q.questionOrder,
          prompt: q.prompt,
          difficulty: q.difficulty,
          responses: related.length,
          correctRate:
            related.length > 0 ? Number(((correct / related.length) * 100).toFixed(2)) : 0,
        };
      });

      sendSuccess(req, res, {
        assessmentId: assessment.id,
        title: assessment.title,
        gradedAttempts: attemptsCount,
        averageScore,
        passRate,
        questionStats,
      });
    } catch (err) {
      next(err);
    }
  },
);
