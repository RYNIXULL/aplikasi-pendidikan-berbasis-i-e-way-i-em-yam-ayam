import { z } from 'zod';
import { DocumentStatus } from '@prisma/client';

export const uploadDocumentMetadataSchema = z.object({
  title: z.string().trim().min(2).max(200),
  subject: z.string().trim().min(2).max(100),
  topic: z.string().trim().max(150).optional(),
  description: z.string().trim().max(2000).optional(),
});

export const updateDocumentSchema = z.object({
  title: z.string().trim().min(2).max(200).optional(),
  subject: z.string().trim().min(2).max(100).optional(),
  topic: z.string().trim().max(150).nullable().optional(),
  description: z.string().trim().max(2000).nullable().optional(),
});

export const listDocumentsQuerySchema = z.object({
  subject: z.string().trim().optional(),
  status: z.nativeEnum(DocumentStatus).optional(),
  q: z.string().trim().optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});
