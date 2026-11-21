import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../config/prisma';
import { AppError } from '../../common/errors';
import { requireAuth } from '../../common/middleware/auth';
import { validateBody } from '../../common/middleware/validate';
import { sendSuccess } from '../../common/response';
import { hashPassword, verifyPassword } from '../../common/security/crypto';
import { recordAuditLog } from '../../common/services/audit';

const updateProfileSchema = z.object({
  fullName: z.string().trim().min(2).max(150).optional(),
  displayName: z.string().trim().min(1).max(80).optional(),
  institutionName: z.string().trim().max(150).nullable().optional(),
  subjectSpecialty: z.string().trim().max(120).nullable().optional(),
  gradeLevel: z.string().trim().max(60).nullable().optional(),
  bio: z.string().trim().max(500).nullable().optional(),
  preferredLocale: z.enum(['id', 'en']).optional(),
});

const changePasswordSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: z
    .string()
    .min(8)
    .max(128)
    .regex(/[A-Z]/)
    .regex(/[a-z]/)
    .regex(/[0-9]/),
});

export const usersRouter = Router();

usersRouter.get('/me/profile', requireAuth, async (req, res, next) => {
  try {
    const profile = await prisma.userProfile.findUnique({
      where: { userId: req.auth!.userId },
      include: { user: { select: { id: true, email: true, role: true, status: true } } },
    });
    if (!profile) {
      throw new AppError(404, 'NOT_FOUND', 'Profile not found.');
    }
    sendSuccess(req, res, profile);
  } catch (err) {
    next(err);
  }
});

usersRouter.patch('/me/profile', requireAuth, validateBody(updateProfileSchema), async (req, res, next) => {
  try {
    const updated = await prisma.userProfile.update({
      where: { userId: req.auth!.userId },
      data: req.body,
    });
    sendSuccess(req, res, updated);
  } catch (err) {
    next(err);
  }
});

usersRouter.patch(
  '/me/password',
  requireAuth,
  validateBody(changePasswordSchema),
  async (req, res, next) => {
    try {
      const user = await prisma.user.findFirst({
        where: { id: req.auth!.userId, deletedAt: null },
      });
      if (!user || !(await verifyPassword(user.passwordHash, req.body.currentPassword))) {
        throw new AppError(401, 'AUTH_INVALID_CREDENTIALS', 'Current password is incorrect.');
      }

      const newHash = await hashPassword(req.body.newPassword);
      await prisma.$transaction([
        prisma.user.update({ where: { id: user.id }, data: { passwordHash: newHash } }),
        prisma.refreshToken.updateMany({
          where: { userId: user.id, revokedAt: null },
          data: { revokedAt: new Date() },
        }),
      ]);

      await recordAuditLog({
        actorUserId: user.id,
        action: 'USER_PASSWORD_CHANGED',
        entityType: 'USER',
        entityId: user.id,
        requestId: req.requestId,
        ipAddress: req.ip,
      });

      sendSuccess(req, res, { updated: true });
    } catch (err) {
      next(err);
    }
  },
);
