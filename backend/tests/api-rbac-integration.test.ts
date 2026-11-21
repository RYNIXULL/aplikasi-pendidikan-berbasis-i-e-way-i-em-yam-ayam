import request from 'supertest';
import { describe, expect, it } from 'vitest';
import { UserRole } from '@prisma/client';
import { createApp } from '../src/app';
import { signAccessToken } from '../src/common/security/crypto';

const app = createApp();

describe('API Envelopes, Authentication & RBAC Enforcement', () => {
  const teacherToken = signAccessToken('11111111-1111-4111-8111-111111111111', UserRole.TEACHER).token;
  const studentToken = signAccessToken('22222222-2222-4222-8222-222222222222', UserRole.STUDENT).token;

  it('returns standard health envelope and echoes X-Request-Id', async () => {
    const res = await request(app)
      .get('/api/v1/health')
      .set('X-Request-Id', 'req-test-123');
    expect(res.status).toBe(200);
    expect(res.headers['x-request-id']).toBe('req-test-123');
    expect(res.body.success).toBe(true);
    expect(res.body.data.status).toBe('ok');
    expect(res.body.meta.requestId).toBe('req-test-123');
  });

  it('blocks public self-registration as ADMIN', async () => {
    const res = await request(app).post('/api/v1/auth/register').send({
      email: 'admin.attempt@example.com',
      password: 'StrongPassword123!',
      fullName: 'Test User',
      role: 'ADMIN',
    });
    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('rejects unauthenticated access to protected endpoints', async () => {
    const endpoints = [
      '/api/v1/documents',
      '/api/v1/contents',
      '/api/v1/classrooms',
      '/api/v1/student/dashboard',
      '/api/v1/teacher/dashboard',
    ];
    for (const ep of endpoints) {
      const res = await request(app).get(ep);
      expect(res.status).toBe(401);
      expect(res.body.error.code).toBe('AUTH_TOKEN_INVALID');
    }
  });

  it('blocks STUDENT role from accessing teacher-only endpoints (403 FORBIDDEN)', async () => {
    const teacherEndpoints = [
      { method: 'get' as const, path: '/api/v1/documents' },
      { method: 'get' as const, path: '/api/v1/contents' },
      { method: 'get' as const, path: '/api/v1/ai/quota' },
      { method: 'get' as const, path: '/api/v1/teacher/dashboard' },
      { method: 'post' as const, path: '/api/v1/classrooms' },
    ];
    for (const ep of teacherEndpoints) {
      const res = await request(app)[ep.method](ep.path).set('Authorization', `Bearer ${studentToken}`);
      expect(res.status).toBe(403);
      expect(res.body.error.code).toBe('FORBIDDEN');
    }
  });

  it('blocks TEACHER role from accessing student-only endpoints (403 FORBIDDEN)', async () => {
    const studentEndpoints = [
      { method: 'get' as const, path: '/api/v1/student/dashboard' },
      { method: 'get' as const, path: '/api/v1/student/assessments' },
      { method: 'post' as const, path: '/api/v1/classrooms/join' },
    ];
    for (const ep of studentEndpoints) {
      const res = await request(app)[ep.method](ep.path).set('Authorization', `Bearer ${teacherToken}`);
      expect(res.status).toBe(403);
      expect(res.body.error.code).toBe('FORBIDDEN');
    }
  });

  it('returns standardized 404 envelope for unknown routes', async () => {
    const res = await request(app).get('/api/v1/non-existent-route');
    expect(res.status).toBe(404);
    expect(res.body.success).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });
});
