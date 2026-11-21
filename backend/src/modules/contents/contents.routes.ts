import { Router } from 'express';
import { z } from 'zod';
import {
  ContentStatus,
  ContentType,
  Prisma,
  UserRole,
  VersionOrigin,
} from '@prisma/client';
import { prisma } from '../../config/prisma';
import { storageService } from '../../config/storage';
import { AppError } from '../../common/errors';
import { requireAuth, requireRole } from '../../common/middleware/auth';
import { validateBody } from '../../common/middleware/validate';
import { buildPagination, sendSuccess } from '../../common/response';
import { recordAuditLog } from '../../common/services/audit';
import { pythonAiClient } from '../ai-orchestration/aiClient';

const editContentSchema = z.object({
  title: z.string().trim().min(2).max(255).optional(),
  payload: z.record(z.unknown()),
  changeNote: z.string().trim().max(255).optional(),
});

export const contentsRouter = Router();
contentsRouter.use(requireAuth, requireRole(UserRole.TEACHER));

contentsRouter.get('/', async (req, res, next) => {
  try {
    const page = Math.max(1, Number(req.query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(req.query.limit ?? 20)));
    const q = typeof req.query.q === 'string' ? req.query.q.trim() : undefined;

    const where = {
      teacherId: req.auth!.userId,
      deletedAt: null,
      ...(req.query.documentId ? { documentId: String(req.query.documentId) } : {}),
      ...(req.query.contentType ? { contentType: String(req.query.contentType) as ContentType } : {}),
      ...(req.query.status ? { status: String(req.query.status) as ContentStatus } : {}),
      ...(q ? { title: { contains: q, mode: 'insensitive' as const } } : {}),
    };

    const [items, total] = await Promise.all([
      prisma.generatedContent.findMany({
        where,
        include: {
          document: { select: { id: true, title: true, subject: true } },
        },
        orderBy: { updatedAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      prisma.generatedContent.count({ where }),
    ]);

    sendSuccess(req, res, items, 200, buildPagination(page, limit, total));
  } catch (err) {
    next(err);
  }
});

contentsRouter.get('/:id', async (req, res, next) => {
  try {
    const content = await prisma.generatedContent.findFirst({
      where: { id: req.params.id, teacherId: req.auth!.userId, deletedAt: null },
      include: {
        document: { select: { id: true, title: true, subject: true, pageCount: true } },
        versions: { orderBy: { versionNumber: 'desc' }, take: 1 },
      },
    });
    if (!content) {
      throw new AppError(404, 'NOT_FOUND', 'Generated content not found.');
    }
    sendSuccess(req, res, {
      ...content,
      currentVersion: content.versions[0] ?? null,
    });
  } catch (err) {
    next(err);
  }
});

contentsRouter.patch('/:id', validateBody(editContentSchema), async (req, res, next) => {
  try {
    const teacherId = req.auth!.userId;
    const content = await prisma.generatedContent.findFirst({
      where: { id: req.params.id, teacherId, deletedAt: null },
      include: { versions: { orderBy: { versionNumber: 'desc' }, take: 1 } },
    });
    if (!content) {
      throw new AppError(404, 'NOT_FOUND', 'Generated content not found.');
    }

    const latestVersionNumber = content.versions[0]?.versionNumber ?? 0;
    const latestRefs = content.versions[0]?.sourceReferences ?? [];

    const result = await prisma.$transaction(async (tx) => {
      const nextVersion = await tx.generationVersion.create({
        data: {
          contentId: content.id,
          versionNumber: latestVersionNumber + 1,
          createdBy: teacherId,
          origin: VersionOrigin.TEACHER_EDITED,
          changeNote: req.body.changeNote ?? 'Teacher manual revision',
          payload: req.body.payload as Prisma.InputJsonValue,
          sourceReferences: latestRefs as Prisma.InputJsonValue,
          validationReport: { editedByTeacher: true },
        },
      });

      const updated = await tx.generatedContent.update({
        where: { id: content.id },
        data: {
          title: req.body.title ?? content.title,
          status: ContentStatus.IN_REVIEW,
          currentVersionId: nextVersion.id,
        },
      });

      return { ...updated, currentVersion: nextVersion };
    });

    sendSuccess(req, res, result);
  } catch (err) {
    next(err);
  }
});

contentsRouter.get('/:id/versions', async (req, res, next) => {
  try {
    const content = await prisma.generatedContent.findFirst({
      where: { id: req.params.id, teacherId: req.auth!.userId, deletedAt: null },
    });
    if (!content) {
      throw new AppError(404, 'NOT_FOUND', 'Generated content not found.');
    }

    const versions = await prisma.generationVersion.findMany({
      where: { contentId: content.id },
      orderBy: { versionNumber: 'desc' },
    });
    sendSuccess(req, res, versions);
  } catch (err) {
    next(err);
  }
});

contentsRouter.post('/:id/versions/:versionId/restore', async (req, res, next) => {
  try {
    const teacherId = req.auth!.userId;
    const content = await prisma.generatedContent.findFirst({
      where: { id: req.params.id, teacherId, deletedAt: null },
      include: { versions: { orderBy: { versionNumber: 'desc' } } },
    });
    if (!content) {
      throw new AppError(404, 'NOT_FOUND', 'Generated content not found.');
    }

    const target = content.versions.find((v) => v.id === req.params.versionId);
    if (!target) {
      throw new AppError(404, 'NOT_FOUND', 'Target version not found.');
    }

    const nextNum = (content.versions[0]?.versionNumber ?? 0) + 1;
    const restored = await prisma.$transaction(async (tx) => {
      const ver = await tx.generationVersion.create({
        data: {
          contentId: content.id,
          versionNumber: nextNum,
          createdBy: teacherId,
          origin: VersionOrigin.RESTORED,
          changeNote: `Restored from version ${target.versionNumber}`,
          payload: target.payload as Prisma.InputJsonValue,
          sourceReferences: target.sourceReferences as Prisma.InputJsonValue,
          validationReport: target.validationReport as Prisma.InputJsonValue,
        },
      });
      await tx.generatedContent.update({
        where: { id: content.id },
        data: { currentVersionId: ver.id, status: ContentStatus.IN_REVIEW },
      });
      return ver;
    });

    sendSuccess(req, res, restored);
  } catch (err) {
    next(err);
  }
});

contentsRouter.post('/:id/approve', async (req, res, next) => {
  try {
    const teacherId = req.auth!.userId;
    const content = await prisma.generatedContent.findFirst({
      where: { id: req.params.id, teacherId, deletedAt: null },
    });
    if (!content || !content.currentVersionId) {
      throw new AppError(404, 'NOT_FOUND', 'Generated content not found or has no versions.');
    }

    const approved = await prisma.generatedContent.update({
      where: { id: content.id },
      data: {
        status: ContentStatus.APPROVED,
        approvedVersionId: content.currentVersionId,
        approvedBy: teacherId,
        approvedAt: new Date(),
      },
    });

    await recordAuditLog({
      actorUserId: teacherId,
      action: 'CONTENT_APPROVED',
      entityType: 'GENERATED_CONTENT',
      entityId: content.id,
      requestId: req.requestId,
      metadata: { versionId: content.currentVersionId },
    });

    sendSuccess(req, res, approved);
  } catch (err) {
    next(err);
  }
});

contentsRouter.post('/:id/export/pptx', async (req, res, next) => {
  try {
    const teacherId = req.auth!.userId;
    const content = await prisma.generatedContent.findFirst({
      where: { id: req.params.id, teacherId, deletedAt: null },
      include: { versions: { orderBy: { versionNumber: 'desc' } } },
    });
    if (!content) {
      throw new AppError(404, 'NOT_FOUND', 'Presentation content not found.');
    }
    if (content.contentType !== ContentType.PRESENTATION) {
      throw new AppError(400, 'VALIDATION_ERROR', 'PPTX export is only supported for PRESENTATION content.');
    }

    const activeVersion =
      content.versions.find((v) => v.id === (content.approvedVersionId ?? content.currentVersionId)) ??
      content.versions[0];
    if (!activeVersion) {
      throw new AppError(404, 'NOT_FOUND', 'No presentation version available to export.');
    }

    const exportKey = `teachers/${teacherId}/exports/${content.id}/v${activeVersion.versionNumber}.pptx`;
    const uploadUrl = await storageService.getSignedUploadUrl(
      exportKey,
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      300,
    );

    const exportMeta = await pythonAiClient.exportPptx(
      {
        presentation: activeVersion.payload as Record<string, unknown>,
        upload_url: uploadUrl,
      },
      req.requestId,
    );

    await prisma.generatedContent.update({
      where: { id: content.id },
      data: {
        exportStorageKey: exportKey,
        exportGeneratedAt: new Date(),
      },
    });

    const downloadUrl = await storageService.getSignedDownloadUrl(exportKey, 300, false);
    sendSuccess(req, res, {
      downloadUrl,
      expiresInSeconds: 300,
      slideCount: exportMeta.slide_count,
      sizeBytes: exportMeta.size_bytes,
    });
  } catch (err) {
    next(err);
  }
});

contentsRouter.delete('/:id', async (req, res, next) => {
  try {
    const content = await prisma.generatedContent.findFirst({
      where: { id: req.params.id, teacherId: req.auth!.userId, deletedAt: null },
    });
    if (!content) {
      throw new AppError(404, 'NOT_FOUND', 'Generated content not found.');
    }
    await prisma.generatedContent.update({
      where: { id: content.id },
      data: { deletedAt: new Date(), status: ContentStatus.ARCHIVED },
    });
    sendSuccess(req, res, { deleted: true });
  } catch (err) {
    next(err);
  }
});
