import { createApp } from './app';
import { env } from './config/env';
import { logger } from './config/logger';
import { prisma } from './config/prisma';
import { closeRedisConnection } from './config/redis';
import { closeQueues } from './modules/ai-orchestration/queues';

const app = createApp();

const server = app.listen(env.PORT, '0.0.0.0', () => {
  logger.info({ port: env.PORT, host: '0.0.0.0', env: env.NODE_ENV }, 'EduAI Node.js backend listening');
});

async function shutdown(signal: string) {
  logger.info({ signal }, 'Shutting down EduAI backend gracefully');
  server.close(async () => {
    await closeQueues();
    await closeRedisConnection();
    await prisma.$disconnect();
    process.exit(0);
  });
}

process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
