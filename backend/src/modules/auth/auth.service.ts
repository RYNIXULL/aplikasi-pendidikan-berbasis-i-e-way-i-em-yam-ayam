import crypto from 'crypto';
import { UserStatus } from '@prisma/client';
import { prisma } from '../../config/prisma';
import { env } from '../../config/env';
import { AppError } from '../../common/errors';
import {
  generateOpaqueToken,
  hashPassword,
  hashToken,
  signAccessToken,
  verifyPassword,
} from '../../common/security/crypto';
import { recordAuditLog } from '../../common/services/audit';
import { mailProvider } from '../../common/services/mail';
import { LoginInput, RegisterInput } from './auth.schema';

export interface AuthMeta {
  requestId?: string;
  ipAddress?: string;
  userAgent?: string;
}

function computeRefreshExpiry(): Date {
  const expires = new Date();
  expires.setDate(expires.getDate() + env.JWT_REFRESH_EXPIRES_DAYS);
  return expires;
}

export class AuthService {
  async register(input: RegisterInput, meta: AuthMeta) {
    const existing = await prisma.user.findFirst({
      where: {
        email: { equals: input.email, mode: 'insensitive' },
        deletedAt: null,
      },
    });
    if (existing) {
      throw new AppError(409, 'CONFLICT', 'An account with this email already exists.');
    }

    const passwordHash = await hashPassword(input.password);
    const rawRefreshToken = generateOpaqueToken();
    const refreshTokenHash = hashToken(rawRefreshToken);
    const familyId = crypto.randomUUID();

    const user = await prisma.$transaction(async (tx) => {
      const created = await tx.user.create({
        data: {
          email: input.email,
          passwordHash,
          role: input.role,
          status: UserStatus.ACTIVE,
          lastLoginAt: new Date(),
          profile: {
            create: {
              fullName: input.fullName,
              displayName: input.fullName.split(' ')[0],
              institutionName: input.institutionName,
              subjectSpecialty: input.subjectSpecialty,
              gradeLevel: input.gradeLevel,
              preferredLocale: input.preferredLocale,
            },
          },
        },
        include: { profile: true },
      });

      await tx.refreshToken.create({
        data: {
          userId: created.id,
          familyId,
          tokenHash: refreshTokenHash,
          deviceName: input.deviceName,
          ipAddress: meta.ipAddress,
          userAgent: meta.userAgent?.slice(0, 255),
          expiresAt: computeRefreshExpiry(),
        },
      });

      return created;
    });

    const access = signAccessToken(user.id, user.role);
    await recordAuditLog({
      actorUserId: user.id,
      action: 'AUTH_REGISTER',
      entityType: 'USER',
      entityId: user.id,
      requestId: meta.requestId,
      ipAddress: meta.ipAddress,
      metadata: { role: user.role },
    });

    return {
      user: {
        id: user.id,
        email: user.email,
        role: user.role,
        fullName: user.profile?.fullName ?? '',
        displayName: user.profile?.displayName ?? null,
        preferredLocale: user.profile?.preferredLocale ?? 'id',
      },
      tokens: {
        accessToken: access.token,
        refreshToken: rawRefreshToken,
        expiresInSeconds: access.expiresInSeconds,
      },
    };
  }

  async login(input: LoginInput, meta: AuthMeta) {
    const user = await prisma.user.findFirst({
      where: {
        email: { equals: input.email, mode: 'insensitive' },
        deletedAt: null,
      },
      include: { profile: true },
    });

    if (!user || !(await verifyPassword(user.passwordHash, input.password))) {
      throw new AppError(401, 'AUTH_INVALID_CREDENTIALS', 'Invalid email or password.');
    }

    if (user.status !== UserStatus.ACTIVE) {
      throw new AppError(403, 'FORBIDDEN', 'Account is not active.');
    }

    const rawRefreshToken = generateOpaqueToken();
    const refreshTokenHash = hashToken(rawRefreshToken);
    const familyId = crypto.randomUUID();

    await prisma.$transaction([
      prisma.user.update({
        where: { id: user.id },
        data: { lastLoginAt: new Date() },
      }),
      prisma.refreshToken.create({
        data: {
          userId: user.id,
          familyId,
          tokenHash: refreshTokenHash,
          deviceName: input.deviceName,
          ipAddress: meta.ipAddress,
          userAgent: meta.userAgent?.slice(0, 255),
          expiresAt: computeRefreshExpiry(),
        },
      }),
    ]);

    const access = signAccessToken(user.id, user.role);
    await recordAuditLog({
      actorUserId: user.id,
      action: 'AUTH_LOGIN',
      entityType: 'USER',
      entityId: user.id,
      requestId: meta.requestId,
      ipAddress: meta.ipAddress,
    });

    return {
      user: {
        id: user.id,
        email: user.email,
        role: user.role,
        fullName: user.profile?.fullName ?? '',
        displayName: user.profile?.displayName ?? null,
        preferredLocale: user.profile?.preferredLocale ?? 'id',
      },
      tokens: {
        accessToken: access.token,
        refreshToken: rawRefreshToken,
        expiresInSeconds: access.expiresInSeconds,
      },
    };
  }

  async refresh(rawRefreshToken: string, deviceName: string | undefined, meta: AuthMeta) {
    const tokenHash = hashToken(rawRefreshToken);
    const stored = await prisma.refreshToken.findUnique({
      where: { tokenHash },
      include: { user: { include: { profile: true } } },
    });

    if (!stored || stored.user.deletedAt || stored.user.status !== UserStatus.ACTIVE) {
      throw new AppError(401, 'AUTH_TOKEN_INVALID', 'Invalid refresh token.');
    }

    // Reuse detection: previously revoked refresh token replayed
    if (stored.revokedAt) {
      await prisma.refreshToken.updateMany({
        where: { familyId: stored.familyId, revokedAt: null },
        data: { revokedAt: new Date() },
      });
      await recordAuditLog({
        actorUserId: stored.userId,
        action: 'AUTH_TOKEN_REUSED',
        entityType: 'REFRESH_TOKEN',
        entityId: stored.id,
        requestId: meta.requestId,
        ipAddress: meta.ipAddress,
        metadata: { familyId: stored.familyId },
      });
      throw new AppError(
        401,
        'AUTH_TOKEN_REUSED',
        'Refresh token reuse detected. Session revoked for security.',
      );
    }

    if (stored.expiresAt.getTime() <= Date.now()) {
      throw new AppError(401, 'AUTH_TOKEN_EXPIRED', 'Refresh token has expired.');
    }

    const nextRawToken = generateOpaqueToken();
    const nextTokenHash = hashToken(nextRawToken);

    await prisma.$transaction(async (tx) => {
      const replacement = await tx.refreshToken.create({
        data: {
          userId: stored.userId,
          familyId: stored.familyId,
          tokenHash: nextTokenHash,
          deviceName: deviceName ?? stored.deviceName,
          ipAddress: meta.ipAddress,
          userAgent: meta.userAgent?.slice(0, 255),
          expiresAt: computeRefreshExpiry(),
        },
      });
      await tx.refreshToken.update({
        where: { id: stored.id },
        data: {
          revokedAt: new Date(),
          replacedByTokenId: replacement.id,
        },
      });
    });

    const access = signAccessToken(stored.user.id, stored.user.role);
    return {
      tokens: {
        accessToken: access.token,
        refreshToken: nextRawToken,
        expiresInSeconds: access.expiresInSeconds,
      },
    };
  }

  async logout(userId: string, rawRefreshToken: string, meta: AuthMeta) {
    const tokenHash = hashToken(rawRefreshToken);
    await prisma.refreshToken.updateMany({
      where: { userId, tokenHash, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    await recordAuditLog({
      actorUserId: userId,
      action: 'AUTH_LOGOUT',
      entityType: 'USER',
      entityId: userId,
      requestId: meta.requestId,
      ipAddress: meta.ipAddress,
    });
  }

  async logoutAll(userId: string, meta: AuthMeta) {
    await prisma.refreshToken.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    await recordAuditLog({
      actorUserId: userId,
      action: 'AUTH_LOGOUT_ALL',
      entityType: 'USER',
      entityId: userId,
      requestId: meta.requestId,
      ipAddress: meta.ipAddress,
    });
  }

  async forgotPassword(email: string, meta: AuthMeta) {
    const user = await prisma.user.findFirst({
      where: { email: { equals: email, mode: 'insensitive' }, deletedAt: null },
    });
    if (!user) {
      // Do not reveal account existence
      return;
    }

    const rawReset = generateOpaqueToken(32);
    const tokenHash = hashToken(rawReset);
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000);

    await prisma.passwordResetToken.create({
      data: {
        userId: user.id,
        tokenHash,
        expiresAt,
      },
    });

    await mailProvider.sendPasswordResetEmail({
      toEmail: user.email,
      resetToken: rawReset,
      expiresMinutes: 15,
    });

    await recordAuditLog({
      actorUserId: user.id,
      action: 'AUTH_PASSWORD_RESET_REQUESTED',
      entityType: 'USER',
      entityId: user.id,
      requestId: meta.requestId,
      ipAddress: meta.ipAddress,
    });
  }

  async resetPassword(resetToken: string, newPassword: string, meta: AuthMeta) {
    const tokenHash = hashToken(resetToken);
    const record = await prisma.passwordResetToken.findUnique({ where: { tokenHash } });
    if (!record || record.usedAt || record.expiresAt.getTime() <= Date.now()) {
      throw new AppError(400, 'VALIDATION_ERROR', 'Reset token is invalid or has expired.');
    }

    const passwordHash = await hashPassword(newPassword);
    await prisma.$transaction([
      prisma.user.update({
        where: { id: record.userId },
        data: { passwordHash },
      }),
      prisma.passwordResetToken.update({
        where: { id: record.id },
        data: { usedAt: new Date() },
      }),
      prisma.refreshToken.updateMany({
        where: { userId: record.userId, revokedAt: null },
        data: { revokedAt: new Date() },
      }),
    ]);

    await recordAuditLog({
      actorUserId: record.userId,
      action: 'AUTH_PASSWORD_RESET_COMPLETED',
      entityType: 'USER',
      entityId: record.userId,
      requestId: meta.requestId,
      ipAddress: meta.ipAddress,
    });
  }

  async getMe(userId: string) {
    const user = await prisma.user.findFirst({
      where: { id: userId, deletedAt: null },
      include: { profile: true },
    });
    if (!user) {
      throw new AppError(404, 'NOT_FOUND', 'User not found.');
    }
    return {
      id: user.id,
      email: user.email,
      role: user.role,
      status: user.status,
      lastLoginAt: user.lastLoginAt,
      profile: user.profile,
    };
  }
}

export const authService = new AuthService();
