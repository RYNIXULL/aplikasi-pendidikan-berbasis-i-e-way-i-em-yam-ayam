import { Queue } from 'bullmq';
import { env } from '../../config/env';
import { getRedisConnection } from '../../config/redis';
import { logger } from '../../config/logger';

export const DOC_PROCESSING_QUEUE = 'doc-processing';
export const AI_GENERATION_QUEUE = 'ai-generation';

let docQueue: Queue | null = null;
let aiQueue: Queue | null = null;

function getDocQueue(): Queue {
  if (!docQueue) {
    docQueue = new Queue(DOC_PROCESSING_QUEUE, {
      connection: getRedisConnection(),
      defaultJobOptions: {
        attempts: 3,
        backoff: { type: 'exponential', delay: 3000 },
        removeOnComplete: 200,
        removeOnFail: 500,
      },
    });
  }
  return docQueue;
}

function getAiQueue(): Queue {
  if (!aiQueue) {
    aiQueue = new Queue(AI_GENERATION_QUEUE, {
      connection: getRedisConnection(),
      defaultJobOptions: {
        attempts: 3,
        backoff: { type: 'exponential', delay: 4000 },
        removeOnComplete: 200,
        removeOnFail: 500,
      },
    });
  }
  return aiQueue;
}

export async function enqueueDocumentProcessingJob(data: {
  documentId: string;
  teacherId: string;
  requestId?: string;
}): Promise<string | null> {
  if (env.NODE_ENV === 'test') {
    return `test-doc-job-${data.documentId}`;
  }
  try {
    const job = await getDocQueue().add('process-document', data, {
      jobId: `doc-${data.documentId}-${Date.now()}`,
    });
    return job.id ?? null;
  } catch (err) {
    logger.warn({ err, documentId: data.documentId }, 'Unable to enqueue doc-processing job (Redis offline?)');
    return null;
  }
}

export async function enqueueAiGenerationJob(data: {
  jobId: string;
  teacherId: string;
  documentId: string;
  requestId?: string;
}): Promise<string | null> {
  if (env.NODE_ENV === 'test') {
    return `test-ai-job-${data.jobId}`;
  }
  try {
    const job = await getAiQueue().add('generate-content', data, {
      jobId: `gen-${data.jobId}`,
    });
    return job.id ?? null;
  } catch (err) {
    logger.warn({ err, jobId: data.jobId }, 'Unable to enqueue ai-generation job (Redis offline?)');
    return null;
  }
}

export async function closeQueues(): Promise<void> {
  await Promise.all([
    docQueue?.close().catch(() => undefined),
    aiQueue?.close().catch(() => undefined),
  ]);
  docQueue = null;
  aiQueue = null;
}
