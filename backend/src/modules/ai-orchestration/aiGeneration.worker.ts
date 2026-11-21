import { ContentStatus, ContentType, JobStatus, Prisma, VersionOrigin } from '@prisma/client';
import { prisma } from '../../config/prisma';
import { logger } from '../../config/logger';
import { pythonAiClient } from './aiClient';

const CONTENT_TYPE_SLUG: Record<
  ContentType,
  'summary' | 'quiz' | 'presentation' | 'flashcards' | 'mind-map' | 'worksheet' | 'game'
> = {
  SUMMARY: 'summary',
  QUIZ: 'quiz',
  PRESENTATION: 'presentation',
  FLASHCARDS: 'flashcards',
  MIND_MAP: 'mind-map',
  WORKSHEET: 'worksheet',
  GAME: 'game',
};

export async function processAiGenerationJob(params: {
  jobId: string;
  teacherId: string;
  documentId: string;
  requestId?: string;
}): Promise<void> {
  const { jobId, teacherId, documentId, requestId } = params;

  const job = await prisma.generationJob.findFirst({
    where: { id: jobId, teacherId },
    include: { document: true },
  });
  if (!job || job.status === JobStatus.CANCELLED) {
    return;
  }

  await prisma.generationJob.update({
    where: { id: job.id },
    data: {
      status: JobStatus.RUNNING,
      progress: 15,
      attemptCount: { increment: 1 },
      startedAt: new Date(),
    },
  });

  try {
    const [analysis, chunks] = await Promise.all([
      prisma.documentAnalysis.findFirst({
        where: { documentId },
        orderBy: { createdAt: 'desc' },
      }),
      prisma.documentChunk.findMany({
        where: { documentId },
        orderBy: { chunkIndex: 'asc' },
        take: 24,
      }),
    ]);

    const requestConfig = (job.requestConfig ?? {}) as Record<string, unknown>;
    let selectedChunks = chunks;

    // Semantic pgvector retrieval if teacher requested a specific topicFocus
    const topicFocus = typeof requestConfig.topicFocus === 'string' ? requestConfig.topicFocus.trim() : '';
    if (topicFocus.length >= 3 && chunks.length > 8) {
      try {
        const queryEmb = await pythonAiClient.generateEmbeddings({ texts: [topicFocus] }, requestId);
        const vec = queryEmb.embeddings[0];
        if (vec && vec.length === 768) {
          const vectorLiteral = `[${vec.join(',')}]`;
          const ranked = await prisma.$queryRawUnsafe<
            Array<{
              chunk_index: number;
              page_start: number;
              page_end: number;
              content: string;
              chapter_title: string | null;
            }>
          >(
            `SELECT chunk_index, page_start, page_end, content, chapter_title
             FROM "document_chunks"
             WHERE "document_id" = $1::uuid AND "embedding" IS NOT NULL
             ORDER BY "embedding" <=> $2::vector
             LIMIT 12`,
            documentId,
            vectorLiteral,
          );
          if (ranked.length > 0) {
            selectedChunks = ranked.map((r) => ({
              id: '',
              documentId,
              chunkIndex: r.chunk_index,
              chapterTitle: r.chapter_title,
              sectionTitle: null,
              pageStart: r.page_start,
              pageEnd: r.page_end,
              tokenCount: 0,
              content: r.content,
              metadata: {},
              createdAt: new Date(),
            }));
          }
        }
      } catch (ragErr) {
        logger.warn({ ragErr, jobId }, 'RAG similarity lookup fell back to sequential chunks');
      }
    }

    await prisma.generationJob.update({
      where: { id: job.id },
      data: { progress: 45 },
    });

    const slug = CONTENT_TYPE_SLUG[job.contentType];
    const generated = await pythonAiClient.generateContent(
      slug,
      {
        document_id: documentId,
        document_title: job.document.title,
        subject: job.document.subject,
        page_count: job.document.pageCount ?? 1,
        game_type: job.gameType ? job.gameType.toLowerCase() : undefined,
        analysis: analysis
          ? {
              subject: analysis.detectedSubject,
              main_topic: analysis.mainTopic,
              language: analysis.language,
              chapters: analysis.chapterStructure,
              definitions: analysis.definitions,
              learning_objectives: analysis.learningObjectives,
            }
          : null,
        chunks: selectedChunks.map((c) => ({
          chunk_index: c.chunkIndex,
          chapter_title: c.chapterTitle,
          page_start: c.pageStart,
          page_end: c.pageEnd,
          content: c.content,
        })),
        config: requestConfig,
      },
      requestId,
    );

    await prisma.generationJob.update({
      where: { id: job.id },
      data: { status: JobStatus.VALIDATING, progress: 85 },
    });

    const payloadTitle =
      typeof generated.payload.title === 'string' && generated.payload.title.trim().length > 0
        ? generated.payload.title.trim()
        : `${job.contentType}: ${job.document.title}`;

    await prisma.$transaction(async (tx) => {
      const content = await tx.generatedContent.create({
        data: {
          teacherId,
          documentId,
          generationJobId: job.id,
          contentType: job.contentType,
          gameType: job.gameType,
          title: payloadTitle.slice(0, 255),
          subject: job.document.subject,
          status: ContentStatus.DRAFT,
        },
      });

      const version = await tx.generationVersion.create({
        data: {
          contentId: content.id,
          versionNumber: 1,
          createdBy: teacherId,
          origin: VersionOrigin.AI_GENERATED,
          changeNote: 'Initial AI generated draft',
          payload: generated.payload as Prisma.InputJsonValue,
          sourceReferences: generated.source_references as Prisma.InputJsonValue,
          validationReport: generated.validation_report as Prisma.InputJsonValue,
        },
      });

      await tx.generatedContent.update({
        where: { id: content.id },
        data: { currentVersionId: version.id },
      });

      await tx.aiUsageLog.create({
        data: {
          userId: teacherId,
          documentId,
          generationJobId: job.id,
          operation: `GENERATE_${job.contentType}`,
          provider: generated.usage.provider,
          model: generated.usage.model,
          promptTokens: generated.usage.prompt_tokens,
          completionTokens: generated.usage.completion_tokens,
          totalTokens: generated.usage.total_tokens,
          estimatedCostUsd: generated.usage.estimated_cost_usd,
          latencyMs: generated.usage.latency_ms,
          success: true,
        },
      });

      await tx.generationJob.update({
        where: { id: job.id },
        data: {
          status: JobStatus.SUCCEEDED,
          progress: 100,
          completedAt: new Date(),
        },
      });
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : 'AI generation failed';
    logger.error({ err, jobId, requestId }, 'AI generation job failed');
    await prisma.generationJob.update({
      where: { id: job.id },
      data: {
        status: JobStatus.FAILED,
        errorCode: 'AI_GENERATION_FAILED',
        errorMessage: message.slice(0, 500),
        completedAt: new Date(),
      },
    });
    throw err;
  }
}
