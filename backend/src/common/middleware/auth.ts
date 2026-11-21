import { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { UserRole } from '@prisma/client';
import { AppError } from '../errors';
import { verifyAccessToken } from '../security/crypto';

export function requireAuth(req: Request, _res: Response, next: NextFunction): void {
  const header = req.header('authorization');
  if (!header || !header.startsWith('Bearer ')) {
    return next(new AppError(401, 'AUTH_TOKEN_INVALID', 'Missing or malformed authorization header.'));
  }

  const token = header.slice(7).trim();
  if (!token) {
    return next(new AppError(401, 'AUTH_TOKEN_INVALID', 'Empty bearer token.'));
  }

  try {
    const payload = verifyAccessToken(token);
    req.auth = {
      userId: payload.sub,
      role: payload.role,
      jti: payload.jti,
    };
    return next();
  } catch (err) {
    if (err instanceof jwt.TokenExpiredError) {
      return next(new AppError(401, 'AUTH_TOKEN_EXPIRED', 'Access token has expired.'));
    }
    return next(new AppError(401, 'AUTH_TOKEN_INVALID', 'Invalid access token.'));
  }
}

export function requireRole(...roles: UserRole[]) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    if (!req.auth) {
      return next(new AppError(401, 'AUTH_TOKEN_INVALID', 'Authentication required.'));
    }
    if (!roles.includes(req.auth.role)) {
      return next(
        new AppError(403, 'FORBIDDEN', 'You do not have permission to perform this action.'),
      );
    }
    return next();
  };
}
