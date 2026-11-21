import { DocumentStatus, Prisma } from '@prisma/client';
import { prisma } from '../../config/prisma';
import { storageService } from '../../config/storage';
import { logger } from '../../config/logger';
import { pythonAiClient } from './aiClient';

export async function processDocumentPipeline(params: {
  documentId: string;
  teacherId: string;
  requestId?: string;
}): Promise<void> {
  const { documentId, teacherId, requestId } = params;

  const doc = await prisma.document.findFirst({
    where: { id: documentId, teacherId, deletedAt: null },
  });
  if (!doc) {
    return;
  }

  try {
    // Check unchanged document SHA-256 analysis reuse
    const existingAnalysis = await prisma.documentAnalysis.findFirst({
      where: {
        documentSha256: doc.sha256Checksum,
        document: { teacherId, deletedAt: null },
      },
      include: {
        document: {
          include: { pages: true, chunks: true },
        },
      },
    });

    if (
      existingAnalysis &&
      existingAnalysis.documentId !== doc.id &&
      existingAnalysis.document.pages.length > 0 &&
      existingAnalysis.document.chunks.length > 0
    ) {
      await prisma.$transaction(async (tx) => {
        await tx.documentPage.deleteMany({ where: { documentId: doc.id } });
        await tx.documentChunk.deleteMany({ where: { documentId: doc.id } });

        await tx.documentPage.createMany({
          data: existingAnalysis.document.pages.map((p) => ({
            documentId: doc.id,
            pageNumber: p.pageNumber,
            heading: p.heading,
            rawText: p.rawText,
            normalizedText: p.normalizedText,
            extractionMethod: p.extractionMethod,
            charCount: p.charCount,
          })),
        });

        await tx.documentChunk.createMany({
          data: existingAnalysis.document.chunks.map((c) => ({
            documentId: doc.id,
            chunkIndex: c.chunkIndex,
            chapterTitle: c.chapterTitle,
            sectionTitle: c.sectionTitle,
            pageStart: c.pageStart,
            pageEnd: c.pageEnd,
            tokenCount: c.tokenCount,
            content: c.content,
            metadata: c.metadata as Prisma.InputJsonValue,
          })),
        });

        await tx.documentAnalysis.upsert({
          where: {
            documentId_documentSha256: {
              documentId: doc.id,
              documentSha256: doc.sha256Checksum,
            },
          },
          update: {
            detectedSubject: existingAnalysis.detectedSubject,
            mainTopic: existingAnalysis.mainTopic,
            language: existingAnalysis.language,
            subtopics: existingAnalysis.subtopics as Prisma.InputJsonValue,
            keyConcepts: existingAnalysis.keyConcepts as Prisma.InputJsonValue,
            definitions: existingAnalysis.definitions as Prisma.InputJsonValue,
            learningObjectives: existingAnalysis.learningObjectives as Prisma.InputJsonValue,
            chapterStructure: existingAnalysis.chapterStructure as Prisma.InputJsonValue,
            modelName: `${existingAnalysis.modelName} (reused)`,
          },
          create: {
            documentId: doc.id,
            documentSha256: doc.sha256Checksum,
            detectedSubject: existingAnalysis.detectedSubject,
            mainTopic: existingAnalysis.mainTopic,
            language: existingAnalysis.language,
            subtopics: existingAnalysis.subtopics as Prisma.InputJsonValue,
            keyConcepts: existingAnalysis.keyConcepts as Prisma.InputJsonValue,
            definitions: existingAnalysis.definitions as Prisma.InputJsonValue,
            learningObjectives: existingAnalysis.learningObjectives as Prisma.InputJsonValue,
            chapterStructure: existingAnalysis.chapterStructure as Prisma.InputJsonValue,
            modelName: `${existingAnalysis.modelName} (reused)`,
          },
        });

        await tx.document.update({
          where: { id: doc.id },
          data: {
            pageCount: existingAnalysis.document.pageCount,
            wordCount: existingAnalysis.document.wordCount,
            status: DocumentStatus.READY,
            processingProgress: 100,
            processedAt: new Date(),
          },
        });
      });

      logger.info({ documentId, requestId }, 'Reused cached analysis for identical SHA-256 document');
      return;
    }

    await prisma.document.update({
      where: { id: doc.id },
      data: { status: DocumentStatus.EXTRACTING, processingProgress: 20 },
    });

    const signedUrl = await storageService.getSignedDownloadUrl(doc.storageKey, 600, true);
    const extracted = await pythonAiClient.extractDocument(
      {
        document_id: doc.id,
        file_url: signedUrl,
        file_format: doc.fileFormat,
        filename: doc.originalFilename,
      },
      requestId,
    );

    await prisma.$transaction(async (tx) => {
      await tx.documentPage.deleteMany({ where: { documentId: doc.id } });
      await tx.documentChunk.deleteMany({ where: { documentId: doc.id } });

      if (extracted.pages.length > 0) {
        await tx.documentPage.createMany({
          data: extracted.pages.map((p) => ({
            documentId: doc.id,
            pageNumber: p.page_number,
            heading: p.heading ?? null,
            rawText: p.raw_text,
            normalizedText: p.normalized_text,
            extractionMethod: p.extraction_method,
            charCount: p.char_count,
          })),
        });
      }

      if (extracted.chunks.length > 0) {
        await tx.documentChunk.createMany({
          data: extracted.chunks.map((c) => ({
            documentId: doc.id,
            chunkIndex: c.chunk_index,
            chapterTitle: c.chapter_title ?? null,
            sectionTitle: c.section_title ?? null,
            pageStart: c.page_start,
            pageEnd: c.page_end,
            tokenCount: c.token_count,
            content: c.content,
            metadata: c.metadata as Prisma.InputJsonValue,
          })),
        });
      }

      await tx.document.update({
        where: { id: doc.id },
        data: {
          pageCount: extracted.page_count,
          wordCount: extracted.word_count,
          status: DocumentStatus.PROCESSING,
          processingProgress: 55,
        },
      });
    });

    // Generate & store pgvector embeddings when chunks exist
    if (extracted.chunks.length > 0) {
      const embRes = await pythonAiClient.generateEmbeddings(
        { texts: extracted.chunks.map((c) => c.content) },
        requestId,
      );

      for (let i = 0; i < extracted.chunks.length; i++) {
        const vector = embRes.embeddings[i];
        if (vector && vector.length === 768) {
          const vectorLiteral = `[${vector.join(',')}]`;
          await prisma.$executeRawUnsafe(
            `UPDATE "document_chunks" SET "embedding" = $1::vector WHERE "document_id" = $2::uuid AND "chunk_index" = $3`,
            vectorLiteral,
            doc.id,
            extracted.chunks[i].chunk_index,
          );
        }
      }

      await prisma.aiUsageLog.create({
        data: {
          userId: teacherId,
          documentId: doc.id,
          operation: 'EMBEDDING',
          provider: embRes.usage.provider,
          model: embRes.usage.model,
          promptTokens: embRes.usage.prompt_tokens,
          completionTokens: embRes.usage.completion_tokens,
          totalTokens: embRes.usage.total_tokens,
          estimatedCostUsd: embRes.usage.estimated_cost_usd,
          latencyMs: embRes.usage.latency_ms,
          success: true,
        },
      });
    }

    await prisma.document.update({
      where: { id: doc.id },
      data: { processingProgress: 75 },
    });

    // Structured material analysis
    const analysisRes = await pythonAiClient.analyzeDocument(
      {
        document_id: doc.id,
        title: doc.title,
        subject: doc.subject,
        chunks: extracted.chunks.slice(0, 30).map((c) => ({
          chunk_index: c.chunk_index,
          page_start: c.page_start,
          page_end: c.page_end,
          content: c.content,
        })),
      },
      requestId,
    );

    const payload = analysisRes.payload as Record<string, unknown>;

    await prisma.$transaction([
      prisma.documentAnalysis.upsert({
        where: {
          documentId_documentSha256: {
            documentId: doc.id,
            documentSha256: doc.sha256Checksum,
          },
        },
        update: {
          detectedSubject: String(payload.subject ?? doc.subject),
          mainTopic: String(payload.main_topic ?? doc.title),
          language: String(payload.language ?? 'id'),
          subtopics: (payload.subtopics ?? []) as Prisma.InputJsonValue,
          keyConcepts: (payload.key_concepts ?? []) as Prisma.InputJsonValue,
          definitions: (payload.definitions ?? []) as Prisma.InputJsonValue,
          learningObjectives: (payload.learning_objectives ?? []) as Prisma.InputJsonValue,
          chapterStructure: (payload.chapters ?? []) as Prisma.InputJsonValue,
          modelName: analysisRes.usage.model,
        },
        create: {
          documentId: doc.id,
          documentSha256: doc.sha256Checksum,
          detectedSubject: String(payload.subject ?? doc.subject),
          mainTopic: String(payload.main_topic ?? doc.title),
          language: String(payload.language ?? 'id'),
          subtopics: (payload.subtopics ?? []) as Prisma.InputJsonValue,
          keyConcepts: (payload.key_concepts ?? []) as Prisma.InputJsonValue,
          definitions: (payload.definitions ?? []) as Prisma.InputJsonValue,
          learningObjectives: (payload.learning_objectives ?? []) as Prisma.InputJsonValue,
          chapterStructure: (payload.chapters ?? []) as Prisma.InputJsonValue,
          modelName: analysisRes.usage.model,
        },
      }),
      prisma.aiUsageLog.create({
        data: {
          userId: teacherId,
          documentId: doc.id,
          operation: 'ANALYZE_DOCUMENT',
          provider: analysisRes.usage.provider,
          model: analysisRes.usage.model,
          promptTokens: analysisRes.usage.prompt_tokens,
          completionTokens: analysisRes.usage.completion_tokens,
          totalTokens: analysisRes.usage.total_tokens,
          estimatedCostUsd: analysisRes.usage.estimated_cost_usd,
          latencyMs: analysisRes.usage.latency_ms,
          success: true,
        },
      }),
      prisma.document.update({
        where: { id: doc.id },
        data: {
          status: extracted.requires_review ? DocumentStatus.REQUIRES_REVIEW : DocumentStatus.READY,
          processingProgress: 100,
          processedAt: new Date(),
        },
      }),
    ]);
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Document processing failed';
    logger.error({ err, documentId, requestId }, 'Document processing pipeline failed');
    await prisma.document.update({
      where: { id: doc.id },
      data: {
        status: DocumentStatus.FAILED,
        failureCode: 'PROCESSING_FAILED',
        failureMessage: message.slice(0, 500),
      },
    });
    throw err;
  }
}
