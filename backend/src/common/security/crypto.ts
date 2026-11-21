import crypto from 'crypto';
import argon2 from 'argon2';
import jwt from 'jsonwebtoken';
import { UserRole } from '@prisma/client';
import { env } from '../../config/env';

export interface AccessTokenPayload {
  sub: string;
  role: UserRole;
  jti: string;
}

export async function hashPassword(plain: string): Promise<string> {
  return argon2.hash(plain, {
    type: argon2.argon2id,
    memoryCost: 65536,
    timeCost: 3,
    parallelism: 1,
  });
}

export async function verifyPassword(hash: string, plain: string): Promise<boolean> {
  try {
    return await argon2.verify(hash, plain);
  } catch {
    return false;
  }
}

export function signAccessToken(userId: string, role: UserRole): { token: string; expiresInSeconds: number } {
  const payload: AccessTokenPayload = {
    sub: userId,
    role,
    jti: crypto.randomUUID(),
  };
  const token = jwt.sign(payload, env.JWT_ACCESS_SECRET, {
    expiresIn: env.JWT_ACCESS_EXPIRES_SECONDS,
    issuer: 'edu-ai-backend',
    audience: 'edu-ai-mobile',
  });
  return { token, expiresInSeconds: env.JWT_ACCESS_EXPIRES_SECONDS };
}

export function verifyAccessToken(token: string): AccessTokenPayload {
  const decoded = jwt.verify(token, env.JWT_ACCESS_SECRET, {
    issuer: 'edu-ai-backend',
    audience: 'edu-ai-mobile',
  });
  if (typeof decoded !== 'object' || !decoded || !('sub' in decoded) || !('role' in decoded)) {
    throw new Error('Invalid token payload');
  }
  return decoded as AccessTokenPayload;
}

export function generateOpaqueToken(bytes = 48): string {
  return crypto.randomBytes(bytes).toString('base64url');
}

export function hashToken(rawToken: string): string {
  return crypto
    .createHmac('sha256', env.JWT_REFRESH_PEPPER)
    .update(rawToken)
    .digest('hex');
}

export function computeSha256(buffer: Buffer): string {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

export function signInternalRequest(rawBody: string, timestamp?: string): {
  timestamp: string;
  signature: string;
  token: string;
} {
  const ts = timestamp ?? Math.floor(Date.now() / 1000).toString();
  const signature = crypto
    .createHmac('sha256', env.INTERNAL_HMAC_SECRET)
    .update(`${ts}.${rawBody}`)
    .digest('hex');
  return {
    timestamp: ts,
    signature,
    token: env.INTERNAL_SERVICE_TOKEN,
  };
}

// Excludes visually ambiguous chars 0/O, 1/I/L
const JOIN_CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

export function generateClassroomJoinCode(length = 8): string {
  const bytes = crypto.randomBytes(length);
  let code = '';
  for (let i = 0; i < length; i++) {
    code += JOIN_CODE_ALPHABET[bytes[i] % JOIN_CODE_ALPHABET.length];
  }
  return code;
}
