import { NextFunction, Request, Response } from 'express';
import multer from 'multer';
import { logger } from '../../config/logger';
import { AppError } from '../errors';
import { sendError } from '../response';

export function errorHandler(err: unknown, req: Request, res: Response, _next: NextFunction): void {
  if (err instanceof AppError) {
    sendError(req, res, err.statusCode, err.code, err.message, err.details);
    return;
  }

  if (err instanceof multer.MulterError) {
    if (err.code === 'LIMIT_FILE_SIZE') {
      sendError(req, res, 413, 'FILE_TOO_LARGE', 'Uploaded file exceeds maximum allowed size.');
      return;
    }
    sendError(req, res, 400, 'VALIDATION_ERROR', err.message);
    return;
  }

  logger.error({ err, requestId: req.requestId }, 'Unhandled error');
  sendError(req, res, 500, 'INTERNAL_ERROR', 'An unexpected internal error occurred.');
}

export function notFoundHandler(req: Request, res: Response): void {
  sendError(req, res, 404, 'NOT_FOUND', `Route ${req.method} ${req.path} not found.`);
}
