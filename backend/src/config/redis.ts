import IORedis from 'ioredis';
import { env } from './env';
import { logger } from './logger';

let redisInstance: IORedis | null = null;

export function getRedisConnection(): IORedis {
  if (!redisInstance) {
    redisInstance = new IORedis(env.REDIS_URL, {
      maxRetriesPerRequest: null,
      enableReadyCheck: false,
      lazyConnect: true,
    });
    redisInstance.on('error', (err) => {
      logger.warn({ err: err.message }, 'Redis connection error');
    });
  }
  return redisInstance;
}

export async function closeRedisConnection(): Promise<void> {
  if (redisInstance) {
    await redisInstance.quit().catch(() => undefined);
    redisInstance = null;
  }
}
