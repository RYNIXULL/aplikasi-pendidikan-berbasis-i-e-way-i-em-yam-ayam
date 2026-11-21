import { Router } from 'express';
import multer from 'multer';
import { UserRole } from '@prisma/client';
import { env } from '../../config/env';
import { AppError } from '../../common/errors';
import { requireAuth, requireRole } from '../../common/middleware/auth';
import { validateBody, validateQuery } from '../../common/middleware/validate';
import { buildPagination, sendSuccess } from '../../common/response';
import {
  listDocumentsQuerySchema,
  updateDocumentSchema,
  uploadDocumentMetadataSchema,
} from './documents.schema';
import { documentsService, serializeDocument } from './documents.service';

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: env.MAX_UPLOAD_BYTES,
    files: 1,
  },
});

export const documentsRouter = Router();

documentsRouter.use(requireAuth, requireRole(UserRole.TEACHER));

documentsRouter.post('/', upload.single('file'), async (req, res, next) => {
  try {
    if (!req.file) {
      throw new AppError(400, 'VALIDATION_ERROR', 'A PDF, DOCX, or PPTX file is required.');
    }
    const parsedMeta = uploadDocumentMetadataSchema.safeParse(req.body);
    if (!parsedMeta.success) {
      throw new AppError(
        400,
        'VALIDATION_ERROR',
        'Invalid document metadata.',
        parsedMeta.error.issues.map((i) => ({ field: i.path.join('.'), issue: i.message })),
      );
    }

    const doc = await documentsService.uploadDocument({
      teacherId: req.auth!.userId,
      file: req.file,
      ...parsedMeta.data,
      requestId: req.requestId,
      ipAddress: req.ip,
    });
    sendSuccess(req, res, doc, 202);
  } catch (err) {
    next(err);
  }
});

documentsRouter.get('/', validateQuery(listDocumentsQuerySchema), async (req, res, next) => {
  try {
    const query = req.query as unknown as {
      subject?: string;
      status?: never;
      q?: string;
      page: number;
      limit: number;
    };
    const { items, total } = await documentsService.listDocuments({
      teacherId: req.auth!.userId,
      subject: query.subject,
      status: query.status,
      q: query.q,
      page: query.page,
      limit: query.limit,
    });
    sendSuccess(req, res, items, 200, buildPagination(query.page, query.limit, total));
  } catch (err) {
    next(err);
  }
});

documentsRouter.get('/:id', async (req, res, next) => {
  try {
    const doc = await documentsService.getOwnedDocument(req.auth!.userId, req.params.id);
    sendSuccess(req, res, serializeDocument(doc));
  } catch (err) {
    next(err);
  }
});

documentsRouter.patch('/:id', validateBody(updateDocumentSchema), async (req, res, next) => {
  try {
    const updated = await documentsService.updateDocument(req.auth!.userId, req.params.id, req.body);
    sendSuccess(req, res, updated);
  } catch (err) {
    next(err);
  }
});

documentsRouter.delete('/:id', async (req, res, next) => {
  try {
    await documentsService.deleteDocument(req.auth!.userId, req.params.id, req.requestId);
    sendSuccess(req, res, { deleted: true });
  } catch (err) {
    next(err);
  }
});

documentsRouter.get('/:id/status', async (req, res, next) => {
  try {
    const doc = await documentsService.getOwnedDocument(req.auth!.userId, req.params.id);
    sendSuccess(req, res, {
      id: doc.id,
      status: doc.status,
      processingProgress: doc.processingProgress,
      pageCount: doc.pageCount,
      failureCode: doc.failureCode,
      failureMessage: doc.failureMessage,
      processedAt: doc.processedAt,
    });
  } catch (err) {
    next(err);
  }
});

documentsRouter.post('/:id/reprocess', async (req, res, next) => {
  try {
    const data = await documentsService.reprocessDocument(
      req.auth!.userId,
      req.params.id,
      req.requestId,
    );
    sendSuccess(req, res, data, 202);
  } catch (err) {
    next(err);
  }
});

documentsRouter.get('/:id/analysis', async (req, res, next) => {
  try {
    const analysis = await documentsService.getAnalysis(req.auth!.userId, req.params.id);
    sendSuccess(req, res, analysis);
  } catch (err) {
    next(err);
  }
});

documentsRouter.get('/:id/download-url', async (req, res, next) => {
  try {
    const signed = await documentsService.getDownloadUrl(req.auth!.userId, req.params.id);
    sendSuccess(req, res, signed);
  } catch (err) {
    next(err);
  }
});
