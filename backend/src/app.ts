import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import pinoHttp from 'pino-http';
import { env } from './config/env';
import { logger } from './config/logger';
import { prisma } from './config/prisma';
import { requestIdMiddleware } from './common/middleware/requestId';
import { generalRateLimiter } from './common/middleware/rateLimit';
import { errorHandler, notFoundHandler } from './common/middleware/errorHandler';
import { sendSuccess } from './common/response';
import { authRouter } from './modules/auth/auth.routes';
import { usersRouter } from './modules/users/users.routes';
import { documentsRouter } from './modules/documents/documents.routes';
import { aiRouter } from './modules/ai-orchestration/ai.routes';
import { contentsRouter } from './modules/contents/contents.routes';
import { classroomsRouter } from './modules/classrooms/classrooms.routes';
import { assessmentsRouter } from './modules/assessments/assessments.routes';
import { gamesRouter } from './modules/games/games.routes';
import { analyticsRouter } from './modules/analytics/analytics.routes';

export function createApp() {
  const app = express();

  app.disable('x-powered-by');
  app.use(requestIdMiddleware);
  app.use(helmet());

  const allowedOrigins = env.CORS_ORIGINS.split(',')
    .map((o) => o.trim())
    .filter(Boolean);

  app.use(
    cors({
      origin: (origin, callback) => {
        if (!origin || allowedOrigins.includes('*') || allowedOrigins.includes(origin)) {
          callback(null, true);
          return;
        }
        callback(new Error('Not allowed by CORS'));
      },
      credentials: true,
    }),
  );

  app.use(express.json({ limit: '2mb' }));
  app.use(express.urlencoded({ extended: false, limit: '2mb' }));

  if (env.NODE_ENV !== 'test') {
    app.use(
      pinoHttp({
        logger,
        genReqId: (req) => (req as express.Request).requestId,
      }),
    );
  }

  app.use('/api/v1', generalRateLimiter);

  app.get('/api/v1/health', (req, res) => {
    sendSuccess(req, res, {
      status: 'ok',
      service: 'edu-ai-backend',
      uptimeSeconds: Math.round(process.uptime()),
    });
  });

  app.get('/api/v1/ready', async (req, res, next) => {
    try {
      await prisma.$queryRaw`SELECT 1`;
      sendSuccess(req, res, { status: 'ready', database: 'connected' });
    } catch (err) {
      next(err);
    }
  });

  app.use('/api/v1/auth', authRouter);
  app.use('/api/v1/users', usersRouter);
  app.use('/api/v1/documents', documentsRouter);
  app.use('/api/v1/ai', aiRouter);
  app.use('/api/v1/contents', contentsRouter);
  app.use('/api/v1/classrooms', classroomsRouter);
  app.use('/api/v1', assessmentsRouter);
  app.use('/api/v1', gamesRouter);
  app.use('/api/v1', analyticsRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
