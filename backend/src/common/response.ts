import { Request, Response } from 'express';
import { ErrorCode, ErrorDetail } from './errors';

export interface PaginationMeta {
  page: number;
  limit: number;
  total: number;
  totalPages: number;
}

export function sendSuccess<T>(
  req: Request,
  res: Response,
  data: T,
  statusCode = 200,
  pagination?: PaginationMeta,
): Response {
  return res.status(statusCode).json({
    success: true,
    data,
    meta: {
      requestId: req.requestId,
      timestamp: new Date().toISOString(),
      ...(pagination ? { pagination } : {}),
    },
  });
}

export function sendError(
  req: Request,
  res: Response,
  statusCode: number,
  code: ErrorCode,
  message: string,
  details: ErrorDetail[] = [],
): Response {
  return res.status(statusCode).json({
    success: false,
    error: {
      code,
      message,
      details,
    },
    meta: {
      requestId: req.requestId,
      timestamp: new Date().toISOString(),
    },
  });
}

export function buildPagination(page: number, limit: number, total: number): PaginationMeta {
  return {
    page,
    limit,
    total,
    totalPages: Math.max(1, Math.ceil(total / limit)),
  };
}
