import path from 'path';
import unzipper from 'unzipper';
import { DocumentFormat } from '@prisma/client';
import { env } from '../../config/env';
import { AppError } from '../errors';

export interface ValidatedUpload {
  format: DocumentFormat;
  mimeType: string;
  sanitizedFilename: string;
  sizeBytes: number;
}

const EXTENSION_MAP: Record<string, { format: DocumentFormat; allowedMimes: string[] }> = {
  '.pdf': {
    format: DocumentFormat.PDF,
    allowedMimes: ['application/pdf', 'application/octet-stream'],
  },
  '.docx': {
    format: DocumentFormat.DOCX,
    allowedMimes: [
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/zip',
      'application/octet-stream',
    ],
  },
  '.pptx': {
    format: DocumentFormat.PPTX,
    allowedMimes: [
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'application/zip',
      'application/octet-stream',
    ],
  },
};

export function sanitizeFilename(originalName: string): string {
  const base = path.basename(originalName || 'document');
  const cleaned = base.replace(/[^a-zA-Z0-9._-\s]/g, '_').trim();
  return cleaned.slice(0, 200) || 'document';
}

export async function validateUploadedDocument(params: {
  originalFilename: string;
  mimeType: string;
  buffer: Buffer;
}): Promise<ValidatedUpload> {
  const { originalFilename, mimeType, buffer } = params;

  if (!buffer || buffer.length === 0) {
    throw new AppError(400, 'FILE_INTEGRITY_FAILED', 'Uploaded file is empty.');
  }

  if (buffer.length > env.MAX_UPLOAD_BYTES) {
    throw new AppError(
      413,
      'FILE_TOO_LARGE',
      `File exceeds maximum size of ${Math.round(env.MAX_UPLOAD_BYTES / (1024 * 1024))} MB.`,
    );
  }

  const ext = path.extname(originalFilename).toLowerCase();
  const mapping = EXTENSION_MAP[ext];
  if (!mapping) {
    throw new AppError(
      415,
      'UNSUPPORTED_MEDIA_TYPE',
      'Only PDF, DOCX, and PPTX files are supported.',
    );
  }

  const normalizedMime = (mimeType || '').toLowerCase().split(';')[0].trim();
  if (normalizedMime && !mapping.allowedMimes.includes(normalizedMime)) {
    throw new AppError(
      415,
      'UNSUPPORTED_MEDIA_TYPE',
      `MIME type ${normalizedMime} does not match file extension ${ext}.`,
    );
  }

  // Magic-byte inspection
  if (mapping.format === DocumentFormat.PDF) {
    const header = buffer.subarray(0, 5).toString('ascii');
    if (header !== '%PDF-') {
      throw new AppError(400, 'FILE_INTEGRITY_FAILED', 'File header is not a valid PDF signature.');
    }
    return {
      format: DocumentFormat.PDF,
      mimeType: 'application/pdf',
      sanitizedFilename: sanitizeFilename(originalFilename),
      sizeBytes: buffer.length,
    };
  }

  // DOCX & PPTX are ZIP-based OpenXML containers starting with PK\x03\x04
  if (buffer.length < 4 || buffer[0] !== 0x50 || buffer[1] !== 0x4b || buffer[2] !== 0x03 || buffer[3] !== 0x04) {
    throw new AppError(
      400,
      'FILE_INTEGRITY_FAILED',
      `File header is not a valid ${mapping.format} archive signature.`,
    );
  }

  // Inspect ZIP central directory for zip-bomb protection & OOXML marker verification
  let totalUncompressed = 0;
  let hasExpectedEntry = false;
  const requiredPrefix = mapping.format === DocumentFormat.DOCX ? 'word/' : 'ppt/';

  try {
    const directory = await unzipper.Open.buffer(buffer);
    if (directory.files.length > 5000) {
      throw new AppError(400, 'FILE_INTEGRITY_FAILED', 'Archive contains too many entries.');
    }
    for (const file of directory.files) {
      if (file.path.includes('..') || path.isAbsolute(file.path)) {
        throw new AppError(400, 'FILE_INTEGRITY_FAILED', 'Archive contains unsafe path traversal entry.');
      }
      totalUncompressed += file.uncompressedSize || 0;
      if (totalUncompressed > env.MAX_ZIP_UNCOMPRESSED_BYTES) {
        throw new AppError(400, 'FILE_INTEGRITY_FAILED', 'Archive uncompressed size exceeds safety limit.');
      }
      if (file.path.startsWith(requiredPrefix)) {
        hasExpectedEntry = true;
      }
    }
  } catch (err) {
    if (err instanceof AppError) throw err;
    throw new AppError(400, 'FILE_INTEGRITY_FAILED', `Corrupted ${mapping.format} archive.`);
  }

  if (!hasExpectedEntry) {
    throw new AppError(
      400,
      'FILE_INTEGRITY_FAILED',
      `Archive structure does not match a valid ${mapping.format} document.`,
    );
  }

  return {
    format: mapping.format,
    mimeType:
      mapping.format === DocumentFormat.DOCX
        ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        : 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    sanitizedFilename: sanitizeFilename(originalFilename),
    sizeBytes: buffer.length,
  };
}
