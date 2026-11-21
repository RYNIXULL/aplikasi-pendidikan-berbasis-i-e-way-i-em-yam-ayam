import { Router } from 'express';
import { z } from 'zod';
import { ContentType, MemberStatus, Prisma, UserRole } from '@prisma/client';
import { prisma } from '../../config/prisma';
import { AppError } from '../../common/errors';
import { requireAuth, requireRole } from '../../common/middleware/auth';
import { validateBody } from '../../common/middleware/validate';
import { sendSuccess } from '../../common/response';

const submitGameSessionSchema = z.object({
  score: z.number().int().min(0),
  maxScore: z.number().int().positive(),
  accuracyPercentage: z.number().min(0).max(100),
  durationSeconds: z.number().int().min(1).max(7200),
  streakMax: z.number().int().min(0).default(0),
  completed: z.boolean().default(true),
  sessionSummary: z.record(z.unknown()).default({}),
});

export const gamesRouter = Router();

async function getAuthorizedGameMaterial(materialId: string, userId: string, role: UserRole) {
  const material = await prisma.classroomMaterial.findUnique({
    where: { id: materialId },
    include: {
      classroom: true,
      content: true,
      publishedVersion: true,
    },
  });
  if (!material || material.content.contentType !== ContentType.GAME || !material.content.gameType) {
    throw new AppError(404, 'NOT_FOUND', 'Educational game not found.');
  }

  if (role === UserRole.TEACHER) {
    if (material.classroom.teacherId !== userId) {
      throw new AppError(403, 'FORBIDDEN', 'You do not own this classroom.');
    }
    return material;
  }

  const membership = await prisma.classroomMember.findFirst({
    where: { classroomId: material.classroomId, studentId: userId, status: MemberStatus.ACTIVE },
  });
  if (!membership || !material.isVisible) {
    throw new AppError(403, 'FORBIDDEN', 'You do not have access to this educational game.');
  }
  return material;
}

gamesRouter.get('/classrooms/:classroomId/games', requireAuth, async (req, res, next) => {
  try {
    const { userId, role } = req.auth!;
    if (role === UserRole.TEACHER) {
      const cls = await prisma.classroom.findFirst({
        where: { id: req.params.classroomId, teacherId: userId, deletedAt: null },
      });
      if (!cls) throw new AppError(404, 'NOT_FOUND', 'Classroom not found.');
    } else {
      const mem = await prisma.classroomMember.findFirst({
        where: { classroomId: req.params.classroomId, studentId: userId, status: MemberStatus.ACTIVE },
      });
      if (!mem) throw new AppError(403, 'FORBIDDEN', 'Not enrolled in this classroom.');
    }

    const materials = await prisma.classroomMaterial.findMany({
      where: {
        classroomId: req.params.classroomId,
        ...(role === UserRole.STUDENT ? { isVisible: true } : {}),
        content: { contentType: ContentType.GAME },
      },
      include: {
        content: { select: { gameType: true, subject: true, documentId: true } },
      },
      orderBy: [{ displayOrder: 'asc' }, { publishedAt: 'desc' }],
    });
    sendSuccess(req, res, materials);
  } catch (err) {
    next(err);
  }
});

gamesRouter.get('/games/:materialId/config', requireAuth, async (req, res, next) => {
  try {
    const material = await getAuthorizedGameMaterial(
      req.params.materialId,
      req.auth!.userId,
      req.auth!.role,
    );
    sendSuccess(req, res, {
      materialId: material.id,
      classroomId: material.classroomId,
      title: material.title,
      gameType: material.content.gameType,
      config: material.publishedVersion.payload,
      sourceReferences: material.publishedVersion.sourceReferences,
    });
  } catch (err) {
    next(err);
  }
});

gamesRouter.post(
  '/games/:materialId/sessions',
  requireAuth,
  requireRole(UserRole.STUDENT),
  validateBody(submitGameSessionSchema),
  async (req, res, next) => {
    try {
      const studentId = req.auth!.userId;
      const material = await getAuthorizedGameMaterial(
        req.params.materialId,
        studentId,
        UserRole.STUDENT,
      );

      const payload = (material.publishedVersion.payload ?? {}) as { max_possible_score?: number };
      const configMax =
        typeof payload.max_possible_score === 'number' && payload.max_possible_score > 0
          ? payload.max_possible_score
          : req.body.maxScore;

      if (req.body.score > configMax) {
        throw new AppError(
          400,
          'VALIDATION_ERROR',
          `Submitted score (${req.body.score}) exceeds game maximum (${configMax}).`,
        );
      }

      const session = await prisma.$transaction(async (tx) => {
        const created = await tx.gameSession.create({
          data: {
            studentId,
            classroomId: material.classroomId,
            materialId: material.id,
            gameType: material.content.gameType!,
            score: req.body.score,
            maxScore: configMax,
            accuracyPercentage: req.body.accuracyPercentage,
            durationSeconds: req.body.durationSeconds,
            streakMax: req.body.streakMax,
            completed: req.body.completed,
            sessionSummary: req.body.sessionSummary as Prisma.InputJsonValue,
          },
        });

        await tx.learningActivity.create({
          data: {
            studentId,
            classroomId: material.classroomId,
            activityType: 'GAME_COMPLETED',
            referenceType: 'GAME_SESSION',
            referenceId: created.id,
            metadata: {
              gameType: material.content.gameType,
              score: req.body.score,
              maxScore: configMax,
            },
          },
        });

        return created;
      });

      sendSuccess(req, res, session, 201);
    } catch (err) {
      next(err);
    }
  },
);

gamesRouter.get(
  '/games/:materialId/history',
  requireAuth,
  requireRole(UserRole.STUDENT),
  async (req, res, next) => {
    try {
      await getAuthorizedGameMaterial(req.params.materialId, req.auth!.userId, UserRole.STUDENT);
      const history = await prisma.gameSession.findMany({
        where: { materialId: req.params.materialId, studentId: req.auth!.userId },
        orderBy: { playedAt: 'desc' },
        take: 30,
      });
      sendSuccess(req, res, history);
    } catch (err) {
      next(err);
    }
  },
);

gamesRouter.get('/games/:materialId/leaderboard', requireAuth, async (req, res, next) => {
  try {
    await getAuthorizedGameMaterial(req.params.materialId, req.auth!.userId, req.auth!.role);
    const sessions = await prisma.gameSession.findMany({
      where: { materialId: req.params.materialId, completed: true },
      include: {
        student: { select: { id: true, profile: { select: { displayName: true, fullName: true } } } },
      },
      orderBy: [{ score: 'desc' }, { durationSeconds: 'asc' }],
      take: 100,
    });

    // Keep best score per student (privacy-safe: displayName only, never email)
    const bestByStudent = new Map<
      string,
      { displayName: string; bestScore: number; maxScore: number; durationSeconds: number; playedAt: Date }
    >();
    for (const s of sessions) {
      if (!bestByStudent.has(s.studentId)) {
        bestByStudent.set(s.studentId, {
          displayName: s.student.profile?.displayName || s.student.profile?.fullName || 'Student',
          bestScore: s.score,
          maxScore: s.maxScore,
          durationSeconds: s.durationSeconds,
          playedAt: s.playedAt,
        });
      }
    }

    const leaderboard = Array.from(bestByStudent.values())
      .slice(0, 20)
      .map((entry, idx) => ({ rank: idx + 1, ...entry }));

    sendSuccess(req, res, leaderboard);
  } catch (err) {
    next(err);
  }
});
