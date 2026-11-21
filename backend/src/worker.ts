import { Worker } from 'bullmq';
import { getRedisConnection, closeRedisConnection } from './config/redis';
import { logger } from './config/logger';
import { prisma } from './config/prisma';
import {
  AI_GENERATION_QUEUE,
  DOC_PROCESSING_QUEUE,
} from './modules/ai-orchestration/queues';
import { processDocumentPipeline } from './modules/ai-orchestration/docProcessing.worker';
import { processAiGenerationJob } from './modules/ai-orchestration/aiGeneration.worker';

const connection = getRedisConnection();

const docWorker = new Worker(
  DOC_PROCESSING_QUEUE,
  async (job) => {
    logger.info({ jobId: job.id, documentId: job.data.documentId }, 'Starting document processing job');
    await processDocumentPipeline(job.data);
  },
  { connection, concurrency: 3 },
);

const aiWorker = new Worker(
  AI_GENERATION_QUEUE,
  async (job) => {
    logger.info({ jobId: job.id, genJobId: job.data.jobId }, 'Starting AI generation job');
    await processAiGenerationJob(job.data);
  },
  { connection, concurrency: 4 },
);

docWorker.on('failed', (job, err) => {
  logger.error({ jobId: job?.id, err: err.message }, 'doc-processing job failed');
});

aiWorker.on('failed', (job, err) => {
  logger.error({ jobId: job?.id, err: err.message }, 'ai-generation job failed');
});

logger.info('EduAI BullMQ workers started');

async function shutdown(signal: string) {
  logger.info({ signal }, 'Shutting down BullMQ workers');
  await Promise.all([docWorker.close(), aiWorker.close()]);
  await closeRedisConnection();
  await prisma.$disconnect();
  process.exit(0);
}

process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
