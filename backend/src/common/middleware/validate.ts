import { NextFunction, Request, Response } from 'express';
import { ZodError, ZodSchema } from 'zod';
import { AppError } from '../errors';

export function validateBody<T>(schema: ZodSchema<T>) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    try {
      req.body = schema.parse(req.body);
      next();
    } catch (err) {
      if (err instanceof ZodError) {
        return next(
          new AppError(
            400,
            'VALIDATION_ERROR',
            'Request body validation failed.',
            err.issues.map((i) => ({ field: i.path.join('.'), issue: i.message })),
          ),
        );
      }
      next(err);
    }
  };
}

export function validateQuery<T>(schema: ZodSchema<T>) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    try {
      req.query = schema.parse(req.query) as unknown as Request['query'];
      next();
    } catch (err) {
      if (err instanceof ZodError) {
        return next(
          new AppError(
            400,
            'VALIDATION_ERROR',
            'Query parameter validation failed.',
            err.issues.map((i) => ({ field: i.path.join('.'), issue: i.message })),
          ),
        );
      }
      next(err);
    }
  };
}
