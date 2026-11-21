import { Router } from 'express';
import { z } from 'zod';
import {
  ContentType,
  DocumentStatus,
  GameType,
  JobStatus,
  Prisma,
  UserRole,
} from '@prisma/client';
import { prisma } from '../../config/prisma';
import { AppError } from '../../common/errors';
import { requireAuth, requireRole } from '../../common/middleware/auth';
import { aiRateLimiter } from '../../common/middleware/rateLimit';
import { validateBody } from '../../common/middleware/validate';
import { buildPagination, sendSuccess } from '../../common/response';
import { enqueueAiGenerationJob } from './queues';
import { enforceTeacherAiQuota, getTeacherAiQuotaStatus } from './quota.service';

const generateRequestSchema = z
  .object({
    documentId: z.string().uuid(),
    contentType: z.nativeEnum(ContentType),
    gameType: z.nativeEnum(GameType).optional(),
    config: z.record(z.unknown()).default({}),
  })
  .refine((val) => val.contentType !== ContentType.GAME || Boolean(val.gameType), {
    message: 'gameType is required when contentType is GAME',
    path: ['gameType'],
  });

export const aiRouter = Router();

aiRouter.use(requireAuth, requireRole(UserRole.TEACHER));

aiRouter.post('/generate', aiRateLimiter, validateBody(generateRequestSchema), async (req, res, next) => {
  try {
    const teacherId = req.auth!.userId;
    const idempotencyKey = req.header('idempotency-key')?.trim() || null;

    if (idempotencyKey) {
      const existing = await prisma.generationJob.findFirst({
        where: { teacherId, idempotencyKey },
      });
      if (existing) {
        sendSuccess(
          req,
          res,
          {
            jobId: existing.id,
            status: existing.status,
            contentType: existing.contentType,
            gameType: existing.gameType,
            progress: existing.progress,
            deduplicated: true,
          },
          202,
        );
        return;
      }
    }

    const doc = await prisma.document.findFirst({
      where: { id: req.body.documentId, teacherId, deletedAt: null },
    });
    if (!doc) {
      throw new AppError(404, 'NOT_FOUND', 'Source document not found.');
    }
    if (doc.status !== DocumentStatus.READY && doc.status !== DocumentStatus.ANALYZED) {
      throw new AppError(
        400,
        'DOCUMENT_NOT_READY',
        `Document must be READY before content generation (current status: ${doc.status}).`,
      );
    }

    await enforceTeacherAiQuota(teacherId);

    const job = await prisma.generationJob.create({
      data: {
        teacherId,
        documentId: doc.id,
        contentType: req.body.contentType,
        gameType: req.body.gameType ?? null,
        idempotencyKey,
        requestConfig: req.body.config as Prisma.InputJsonValue,
        status: JobStatus.QUEUED,
        progress: 0,
      },
    });

    const bullJobId = await enqueueAiGenerationJob({
      jobId: job.id,
      teacherId,
      documentId: doc.id,
      requestId: req.requestId,
    });

    if (bullJobId) {
      await prisma.generationJob.update({
        where: { id: job.id },
        data: { bullJobId },
      });
    }

    sendSuccess(
      req,
      res,
      {
        jobId: job.id,
        status: job.status,
        contentType: job.contentType,
        gameType: job.gameType,
        progress: job.progress,
      },
      202,
    );
  } catch (err) {
    next(err);
  }
});

aiRouter.get('/jobs', async (req, res, next) => {
  try {
    const page = Math.max(1, Number(req.query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(req.query.limit ?? 20)));
    const where = {
      teacherId: req.auth!.userId,
      ...(req.query.documentId ? { documentId: String(req.query.documentId) } : {}),
      ...(req.query.status ? { status: String(req.query.status) as JobStatus } : {}),
    };

    const [items, total] = await Promise.all([
      prisma.generationJob.findMany({
        where,
        include: { generatedContent: { select: { id: true, title: true, status: true } } },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      prisma.generationJob.count({ where }),
    ]);

    sendSuccess(req, res, items, 200, buildPagination(page, limit, total));
  } catch (err) {
    next(err);
  }
});

aiRouter.get('/jobs/:jobId', async (req, res, next) => {
  try {
    const job = await prisma.generationJob.findFirst({
      where: { id: req.params.jobId, teacherId: req.auth!.userId },
      include: { generatedContent: { select: { id: true, title: true, status: true } } },
    });
    if (!job) {
      throw new AppError(404, 'NOT_FOUND', 'Generation job not found.');
    }
    sendSuccess(req, res, job);
  } catch (err) {
    next(err);
  }
});

aiRouter.post('/jobs/:jobId/retry', async (req, res, next) => {
  try {
    const job = await prisma.generationJob.findFirst({
      where: { id: req.params.jobId, teacherId: req.auth!.userId },
    });
    if (!job) {
      throw new AppError(404, 'NOT_FOUND', 'Generation job not found.');
    }
    if (job.status !== JobStatus.FAILED) {
      throw new AppError(409, 'CONFLICT', 'Only FAILED jobs can be retried.');
    }
    await enforceTeacherAiQuota(req.auth!.userId);

    const updated = await prisma.generationJob.update({
      where: { id: job.id },
      data: {
        status: JobStatus.QUEUED,
        progress: 0,
        errorCode: null,
        errorMessage: null,
        completedAt: null,
      },
    });
    await enqueueAiGenerationJob({
      jobId: job.id,
      teacherId: req.auth!.userId,
      documentId: job.documentId,
      requestId: req.requestId,
    });
    sendSuccess(req, res, updated, 202);
  } catch (err) {
    next(err);
  }
});

aiRouter.post('/jobs/:jobId/cancel', async (req, res, next) => {
  try {
    const job = await prisma.generationJob.findFirst({
      where: { id: req.params.jobId, teacherId: req.auth!.userId },
    });
    if (!job) {
      throw new AppError(404, 'NOT_FOUND', 'Generation job not found.');
    }
    if (job.status !== JobStatus.QUEUED) {
      throw new AppError(409, 'CONFLICT', 'Only QUEUED jobs can be cancelled.');
    }
    const updated = await prisma.generationJob.update({
      where: { id: job.id },
      data: { status: JobStatus.CANCELLED, completedAt: new Date() },
    });
    sendSuccess(req, res, updated);
  } catch (err) {
    next(err);
  }
});

aiRouter.get('/quota', async (req, res, next) => {
  try {
    const quota = await getTeacherAiQuotaStatus(req.auth!.userId);
    sendSuccess(req, res, quota);
  } catch (err) {
    next(err);
  }
});
