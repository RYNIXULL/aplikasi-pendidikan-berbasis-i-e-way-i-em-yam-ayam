export type ErrorCode =
  | 'VALIDATION_ERROR'
  | 'FILE_INTEGRITY_FAILED'
  | 'DOCUMENT_NOT_READY'
  | 'CONTENT_NOT_APPROVED'
  | 'AUTH_INVALID_CREDENTIALS'
  | 'AUTH_TOKEN_EXPIRED'
  | 'AUTH_TOKEN_INVALID'
  | 'AUTH_TOKEN_REUSED'
  | 'FORBIDDEN'
  | 'NOT_FOUND'
  | 'CLASSROOM_CODE_INVALID'
  | 'CONFLICT'
  | 'DUPLICATE_SUBMISSION'
  | 'ASSESSMENT_CLOSED'
  | 'FILE_TOO_LARGE'
  | 'UNSUPPORTED_MEDIA_TYPE'
  | 'RATE_LIMIT_EXCEEDED'
  | 'AI_QUOTA_EXCEEDED'
  | 'AI_GENERATION_FAILED'
  | 'INTERNAL_ERROR';

export interface ErrorDetail {
  field?: string;
  issue: string;
}

export class AppError extends Error {
  public readonly statusCode: number;
  public readonly code: ErrorCode;
  public readonly details: ErrorDetail[];

  constructor(statusCode: number, code: ErrorCode, message: string, details: ErrorDetail[] = []) {
    super(message);
    this.name = 'AppError';
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
    Object.setPrototypeOf(this, AppError.prototype);
  }
}
