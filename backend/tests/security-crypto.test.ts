import { describe, expect, it } from 'vitest';
import { UserRole } from '@prisma/client';
import {
  computeSha256,
  generateClassroomJoinCode,
  generateOpaqueToken,
  hashPassword,
  hashToken,
  signAccessToken,
  signInternalRequest,
  verifyAccessToken,
  verifyPassword,
} from '../src/common/security/crypto';

describe('Security & Cryptography Utilities', () => {
  it('hashes and verifies passwords with Argon2id', async () => {
    const hash = await hashPassword('SecureEduPass123!');
    expect(hash.startsWith('$argon2id$')).toBe(true);
    expect(await verifyPassword(hash, 'SecureEduPass123!')).toBe(true);
    expect(await verifyPassword(hash, 'WrongPassword123!')).toBe(false);
  });

  it('signs and verifies JWT access tokens with role and subject claims', () => {
    const { token, expiresInSeconds } = signAccessToken('user-uuid-1', UserRole.TEACHER);
    expect(expiresInSeconds).toBe(900);
    const decoded = verifyAccessToken(token);
    expect(decoded.sub).toBe('user-uuid-1');
    expect(decoded.role).toBe(UserRole.TEACHER);
    expect(decoded.jti).toBeTruthy();
  });

  it('produces deterministic HMAC token hashes and SHA-256 checksums', () => {
    const raw = generateOpaqueToken();
    expect(raw.length).toBeGreaterThan(32);
    expect(hashToken(raw)).toHaveLength(64);
    expect(hashToken(raw)).toBe(hashToken(raw));
    expect(computeSha256(Buffer.from('hello world'))).toHaveLength(64);
  });

  it('signs internal Python AI service requests with HMAC-SHA256', () => {
    const signed = signInternalRequest('{"document_id":"123"}', '1700000000');
    expect(signed.timestamp).toBe('1700000000');
    expect(signed.signature).toHaveLength(64);
    expect(signed.token.length).toBeGreaterThanOrEqual(16);
  });

  it('generates 8-character classroom codes without ambiguous characters', () => {
    const codes = new Set<string>();
    for (let i = 0; i < 50; i++) {
      const code = generateClassroomJoinCode(8);
      expect(code).toMatch(/^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{8}$/);
      codes.add(code);
    }
    expect(codes.size).toBe(50);
  });
});
