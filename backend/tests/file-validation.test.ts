import { describe, expect, it } from 'vitest';
import { DocumentFormat } from '@prisma/client';
import { sanitizeFilename, validateUploadedDocument } from '../src/common/security/fileValidation';
import { AppError } from '../src/common/errors';

describe('Document Upload Security Validation', () => {
  it('sanitizes filenames and strips path traversal', () => {
    expect(sanitizeFilename('../../etc/passwd')).toBe('passwd');
    expect(sanitizeFilename('Modul Biologi <script>.pdf')).toBe('Modul Biologi _script_.pdf');
  });

  it('accepts a valid PDF signature', async () => {
    const pdfBuf = Buffer.from('%PDF-1.7\n1 0 obj\n<<>>\nendobj\n%%EOF', 'ascii');
    const result = await validateUploadedDocument({
      originalFilename: 'biologi-bab-1.pdf',
      mimeType: 'application/pdf',
      buffer: pdfBuf,
    });
    expect(result.format).toBe(DocumentFormat.PDF);
    expect(result.mimeType).toBe('application/pdf');
    expect(result.sizeBytes).toBe(pdfBuf.length);
  });

  it('rejects a spoofed PDF whose magic bytes are not %PDF-', async () => {
    const fakePdf = Buffer.from('<html>not a pdf</html>', 'utf8');
    await expect(
      validateUploadedDocument({
        originalFilename: 'malicious.pdf',
        mimeType: 'application/pdf',
        buffer: fakePdf,
      }),
    ).rejects.toMatchObject({
      statusCode: 400,
      code: 'FILE_INTEGRITY_FAILED',
    });
  });

  it('rejects unsupported file extensions such as .exe or .js', async () => {
    await expect(
      validateUploadedDocument({
        originalFilename: 'payload.exe',
        mimeType: 'application/octet-stream',
        buffer: Buffer.from('MZ9000'),
      }),
    ).rejects.toMatchObject({
      statusCode: 415,
      code: 'UNSUPPORTED_MEDIA_TYPE',
    });
  });

  it('rejects empty buffers', async () => {
    await expect(
      validateUploadedDocument({
        originalFilename: 'empty.pdf',
        mimeType: 'application/pdf',
        buffer: Buffer.alloc(0),
      }),
    ).rejects.toBeInstanceOf(AppError);
  });
});
