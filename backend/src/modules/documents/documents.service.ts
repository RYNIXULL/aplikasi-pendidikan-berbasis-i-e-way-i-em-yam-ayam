import crypto from 'crypto';
import { DocumentStatus } from '@prisma/client';
import { prisma } from '../../config/prisma';
import { env } from '../../config/env';
import { storageService } from '../../config/storage';
import { AppError } from '../../common/errors';
import { computeSha256 } from '../../common/security/crypto';
import { validateUploadedDocument } from '../../common/security/fileValidation';
import { recordAuditLog } from '../../common/services/audit';
import { enqueueDocumentProcessingJob } from '../ai-orchestration/queues';

export function serializeDocument(doc: {
  id: string;
  teacherId: string;
  title: string;
  description: string | null;
  subject: string;
  topic: string | null;
  originalFilename: string;
  fileFormat: string;
  mimeType: string;
  fileSizeBytes: bigint;
  pageCount: number | null;
  wordCount: number | null;
  status: DocumentStatus;
  processingProgress: number;
  failureCode: string | null;
  failureMessage: string | null;
  processedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    ...doc,
    fileSizeBytes: Number(doc.fileSizeBytes),
  };
}

export class DocumentsService {
  async uploadDocument(params: {
    teacherId: string;
    file: Express.Multer.File;
    title: string;
    subject: string;
    topic?: string;
    description?: string;
    requestId?: string;
    ipAddress?: string;
  }) {
    const validated = await validateUploadedDocument({
      originalFilename: params.file.originalname,
      mimeType: params.file.mimetype,
      buffer: params.file.buffer,
    });

    const sha256Checksum = computeSha256(params.file.buffer);
    const docId = crypto.randomUUID();
    const storageKey = `teachers/${params.teacherId}/documents/${docId}/${validated.sanitizedFilename}`;

    await storageService.putObject({
      key: storageKey,
      body: params.file.buffer,
      contentType: validated.mimeType,
      metadata: {
        teacherId: params.teacherId,
        sha256: sha256Checksum,
      },
    });

    const doc = await prisma.document.create({
      data: {
        id: docId,
        teacherId: params.teacherId,
        title: params.title,
        description: params.description,
        subject: params.subject,
        topic: params.topic,
        originalFilename: validated.sanitizedFilename,
        fileFormat: validated.format,
        mimeType: validated.mimeType,
        fileSizeBytes: BigInt(validated.sizeBytes),
        sha256Checksum,
        storageBucket: env.S3_BUCKET,
        storageKey,
        status: DocumentStatus.UPLOADED,
        processingProgress: 5,
      },
    });

    await enqueueDocumentProcessingJob({
      documentId: doc.id,
      teacherId: params.teacherId,
      requestId: params.requestId,
    });

    await recordAuditLog({
      actorUserId: params.teacherId,
      action: 'DOCUMENT_UPLOADED',
      entityType: 'DOCUMENT',
      entityId: doc.id,
      requestId: params.requestId,
      ipAddress: params.ipAddress,
      metadata: { format: doc.fileFormat, sizeBytes: validated.sizeBytes },
    });

    return serializeDocument(doc);
  }

  async listDocuments(params: {
    teacherId: string;
    subject?: string;
    status?: DocumentStatus;
    q?: string;
    page: number;
    limit: number;
  }) {
    const where = {
      teacherId: params.teacherId,
      deletedAt: null,
      ...(params.subject ? { subject: { equals: params.subject, mode: 'insensitive' as const } } : {}),
      ...(params.status ? { status: params.status } : {}),
      ...(params.q
        ? {
            OR: [
              { title: { contains: params.q, mode: 'insensitive' as const } },
              { topic: { contains: params.q, mode: 'insensitive' as const } },
              { subject: { contains: params.q, mode: 'insensitive' as const } },
            ],
          }
        : {}),
    };

    const [items, total] = await Promise.all([
      prisma.document.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (params.page - 1) * params.limit,
        take: params.limit,
      }),
      prisma.document.count({ where }),
    ]);

    return { items: items.map(serializeDocument), total };
  }

  async getOwnedDocument(teacherId: string, documentId: string) {
    const doc = await prisma.document.findFirst({
      where: { id: documentId, teacherId, deletedAt: null },
    });
    if (!doc) {
      throw new AppError(404, 'NOT_FOUND', 'Document not found.');
    }
    return doc;
  }

  async updateDocument(
    teacherId: string,
    documentId: string,
    data: { title?: string; subject?: string; topic?: string | null; description?: string | null },
  ) {
    await this.getOwnedDocument(teacherId, documentId);
    const updated = await prisma.document.update({
      where: { id: documentId },
      data,
    });
    return serializeDocument(updated);
  }

  async deleteDocument(teacherId: string, documentId: string, requestId?: string) {
    const doc = await this.getOwnedDocument(teacherId, documentId);
    const linkedPublished = await prisma.generatedContent.count({
      where: { documentId, deletedAt: null },
    });

    await prisma.document.update({
      where: { id: documentId },
      data: { deletedAt: new Date() },
    });

    if (linkedPublished === 0) {
      await storageService.deleteObject(doc.storageKey).catch(() => undefined);
    }

    await recordAuditLog({
      actorUserId: teacherId,
      action: 'DOCUMENT_DELETED',
      entityType: 'DOCUMENT',
      entityId: documentId,
      requestId,
    });
  }

  async reprocessDocument(teacherId: string, documentId: string, requestId?: string) {
    const doc = await this.getOwnedDocument(teacherId, documentId);
    await prisma.document.update({
      where: { id: doc.id },
      data: {
        status: DocumentStatus.UPLOADED,
        processingProgress: 5,
        failureCode: null,
        failureMessage: null,
      },
    });
    await enqueueDocumentProcessingJob({ documentId: doc.id, teacherId, requestId });
    return { documentId: doc.id, status: DocumentStatus.UPLOADED };
  }

  async getAnalysis(teacherId: string, documentId: string) {
    const doc = await this.getOwnedDocument(teacherId, documentId);
    const analysis = await prisma.documentAnalysis.findFirst({
      where: { documentId: doc.id },
      orderBy: { createdAt: 'desc' },
    });
    if (!analysis) {
      throw new AppError(404, 'NOT_FOUND', 'Document analysis is not yet available.');
    }
    return analysis;
  }

  async getDownloadUrl(teacherId: string, documentId: string) {
    const doc = await this.getOwnedDocument(teacherId, documentId);
    const url = await storageService.getSignedDownloadUrl(doc.storageKey, 300, false);
    return { url, expiresInSeconds: 300, filename: doc.originalFilename };
  }
}

export const documentsService = new DocumentsService();
