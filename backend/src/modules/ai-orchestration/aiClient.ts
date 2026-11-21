import { env } from '../../config/env';
import { AppError } from '../../common/errors';
import { signInternalRequest } from '../../common/security/crypto';

export interface AiUsageMetrics {
  provider: string;
  model: string;
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
  estimated_cost_usd: number;
  latency_ms: number;
}

export interface ExtractedPageDto {
  page_number: number;
  heading?: string | null;
  raw_text: string;
  normalized_text: string;
  extraction_method: string;
  char_count: number;
}

export interface ExtractedChunkDto {
  chunk_index: number;
  chapter_title?: string | null;
  section_title?: string | null;
  page_start: number;
  page_end: number;
  token_count: number;
  content: string;
  metadata: Record<string, unknown>;
}

export interface ExtractResponseDto {
  page_count: number;
  word_count: number;
  requires_review: boolean;
  warnings: string[];
  pages: ExtractedPageDto[];
  chunks: ExtractedChunkDto[];
}

export interface InternalGenerateResponseDto<T = Record<string, unknown>> {
  payload: T;
  source_references: Array<Record<string, unknown>>;
  validation_report: Record<string, unknown>;
  usage: AiUsageMetrics;
}

export class PythonAiClient {
  private async postInternal<TResp>(
    path: string,
    payload: Record<string, unknown>,
    requestId?: string,
  ): Promise<TResp> {
    const rawBody = JSON.stringify(payload);
    const signed = signInternalRequest(rawBody);

    const response = await fetch(`${env.AI_SERVICE_BASE_URL}${path}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Internal-Service-Token': signed.token,
        'X-Internal-Timestamp': signed.timestamp,
        'X-Internal-Signature': signed.signature,
        ...(requestId ? { 'X-Request-Id': requestId } : {}),
      },
      body: rawBody,
    });

    if (!response.ok) {
      const errText = await response.text().catch(() => '');
      throw new AppError(
        502,
        'AI_GENERATION_FAILED',
        `AI service returned HTTP ${response.status}: ${errText.slice(0, 300)}`,
      );
    }

    return (await response.json()) as TResp;
  }

  async extractDocument(
    params: { document_id: string; file_url: string; file_format: string; filename: string },
    requestId?: string,
  ): Promise<ExtractResponseDto> {
    return this.postInternal<ExtractResponseDto>('/internal/v1/documents/extract', params, requestId);
  }

  async generateEmbeddings(
    params: { texts: string[] },
    requestId?: string,
  ): Promise<{ embeddings: number[][]; usage: AiUsageMetrics }> {
    return this.postInternal('/internal/v1/embeddings', params, requestId);
  }

  async analyzeDocument(
    params: {
      document_id: string;
      title: string;
      subject: string;
      chunks: Array<{ chunk_index: number; page_start: number; page_end: number; content: string }>;
    },
    requestId?: string,
  ): Promise<InternalGenerateResponseDto> {
    return this.postInternal('/internal/v1/documents/analyze', params, requestId);
  }

  async generateContent(
    endpointSlug:
      | 'summary'
      | 'quiz'
      | 'presentation'
      | 'flashcards'
      | 'mind-map'
      | 'worksheet'
      | 'game',
    params: Record<string, unknown>,
    requestId?: string,
  ): Promise<InternalGenerateResponseDto> {
    return this.postInternal(`/internal/v1/generate/${endpointSlug}`, params, requestId);
  }

  async exportPptx(
    params: { presentation: Record<string, unknown>; upload_url: string },
    requestId?: string,
  ): Promise<{ slide_count: number; size_bytes: number }> {
    return this.postInternal('/internal/v1/export/pptx', params, requestId);
  }
}

export const pythonAiClient = new PythonAiClient();
