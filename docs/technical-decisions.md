# Technical Decision Records (ADRs)

**Version:** 1.0  
**Phase:** Phase 0 — Project Discovery & Planning

---

## ADR-001: Monorepo Directory Organization
- **Status:** Accepted
- **Context:** The ecosystem comprises three runtime codebases (Flutter, Node.js, Python), shared infrastructure definitions, and synchronized API/schema specifications.
- **Decision:** Organize the workspace as a single monorepo containing `mobile/`, `backend/`, `ai-service/`, `infra/`, and `docs/`.
- **Alternatives Considered:** Separate Git repositories per service.
- **Consequences:** Single-commit synchronization across API contracts and mobile DTOs, unified CI checks, and simpler local Docker Compose orchestration. Build caches and dependencies remain isolated per subdirectory via strict `.gitignore` rules.

---

## ADR-002: Single Database Writer Pattern (Node.js Owns PostgreSQL)
- **Status:** Accepted
- **Context:** Both Node.js and Python participate in document processing and AI workflows. Allowing two services in two ORMs to write independently to the same PostgreSQL tables causes migration drift, race conditions, and duplicated authorization logic.
- **Decision:** The Node.js backend (via Prisma ORM) is the sole owner of PostgreSQL migrations, reads, writes, and `pgvector` similarity queries. The Python FastAPI service operates as a stateless private compute service receiving signed requests from Node.js BullMQ workers and returning structured payloads, extracted pages, chunks, and embeddings.
- **Alternatives Considered:** Dual DB access from both Prisma and SQLAlchemy.
- **Consequences:** Eliminates schema drift and cross-service transaction coupling. Adds one JSON serialization hop between Python and Node.js workers, which is negligible compared to document I/O and LLM call latencies.

---

## ADR-003: Python 3.12 Runtime Pinning for AI Processing Service
- **Status:** Accepted
- **Context:** Local host inspection revealed Python `3.14.3` on default `PATH`, alongside Python `3.12.14` managed by `uv 0.12.9`. Several document/OCR libraries (`PyMuPDF`, `numpy`, OCR bindings) lag behind bleeding-edge Python 3.14 wheel availability.
- **Decision:** Pin `ai-service` to Python `3.12` (`requires-python = ">=3.12,<3.13"`) managed via `uv` locally and `python:3.12-slim` in Docker.
- **Alternatives Considered:** Running on host default Python 3.14.
- **Consequences:** Guarantees deterministic wheel builds across Windows dev and Linux containers with zero manual compilation blockers.

---

## ADR-004: Flutter Client Persistence — Drift (SQLite) & Flutter Secure Storage
- **Status:** Accepted
- **Context:** `rnd.md.txt` listed "Isar atau SQLite" for local caching. Isar v3/v4 maintenance has stalled across newer Dart/Flutter toolchains and build_runner versions (`Flutter 3.29.3 / Dart 3.7.2`), creating dependency risk.
- **Decision:** Use **Drift** (reactive, strongly typed SQLite for Dart/Flutter) for offline caching of published summaries, flashcards, mind maps, and progress sync queues, paired exclusively with **Flutter Secure Storage** for JWT/refresh tokens.
- **Alternatives Considered:** Isar, raw `sqflite`, Hive.
- **Consequences:** Long-term toolchain stability, SQL-backed migrations, predictable performance on mid-range Android devices, and strict separation of encrypted credentials from cached study data.

---

## ADR-005: UI/UX Design System, Restrained Frosted Glass & Feedback Standards
- **Status:** Accepted
- **Context:** The application must look modern and polished while running smoothly on mid-range Android devices and adhering to strict design rules (avoid excessive glassmorphism/gradients, never use native `alert()`, never use emojis/emoticons, never use sparkles icons).
- **Decision:**
  - Build a dedicated theme & reusable widget kit in `mobile/lib/core/widgets/`.
  - Apply restrained Frosted Glass (`BackdropFilter` with low blur `sigma <= 10`, translucent white/dark surface, crisp `1px` border) **only** to the floating `BottomNavigation` and sticky top navigation chrome, with a solid high-contrast fallback when reduced motion or low-performance mode is needed. Cards and data containers use clean solid surfaces.
  - Replace all `alert()` dialogs with a unified `AppToast` overlay and custom `ConfirmationDialog`.
  - Ban emojis/emoticons and sparkles icons project-wide; standardize on crisp modern vector icons (`lucide_icons_flutter` / Material Symbols Rounded).
- **Alternatives Considered:** Full-screen glassmorphic cards; standard Material unstyled Snackbars.
- **Consequences:** Smooth 60fps scrolling on mid-range hardware, accessible contrast, and unmistakable educational brand polish.

---

## ADR-006: Authentication & Refresh-Token Rotation with Reuse Detection
- **Status:** Accepted
- **Context:** Mobile sessions must persist safely across restarts without keeping long-lived unrevocable bearer tokens on device.
- **Decision:**
  - Hash passwords with **Argon2id**.
  - Issue short-lived **JWT Access Tokens (15 minutes)** signed asymmetrically or with strong rotated HMAC secret (`HS256` dev / configurable `RS256` prod) containing `sub`, `role`, and `jti`.
  - Issue **30-day opaque Refresh Tokens** stored as `SHA-256` hashes in `refresh_tokens` with a `family_id`. Every `/auth/refresh` call revokes the presented token and issues a successor in the same family; replaying any already-revoked token immediately revokes the entire `family_id` and logs a security `audit_logs` event.
- **Alternatives Considered:** Stateless long-lived JWTs; non-rotating refresh tokens.
- **Consequences:** Compromised or replayed refresh tokens are neutralized automatically while legitimate users stay seamlessly logged in via Dio's queued refresh interceptor.

---

## ADR-007: PostgreSQL 16 + `pgvector` (768-dim HNSW) & Hybrid JSONB Schema
- **Status:** Accepted
- **Context:** The system requires strict relational integrity for classrooms, users, and grades alongside semantic chunk retrieval (RAG) and evolving schemas for 7 AI content formats.
- **Decision:** Use PostgreSQL 16 with `pgvector` (`vector(768)` + HNSW cosine index on `document_chunks`) as a unified database, avoiding a separate vector DB service in MVP. Use strict relational tables for ownership/workflow states and Zod/Pydantic-validated `JSONB` columns for `document_analyses`, `generation_versions.payload`, and `game_sessions.session_summary`.
- **Alternatives Considered:** Separate Qdrant/Pinecone cluster alongside PostgreSQL.
- **Consequences:** Single-system transactional consistency (deleting/filtering chunks scoped strictly by teacher-owned `document_id` inside SQL) and drastically simpler operations.

---

## ADR-008: Asynchronous Job Processing via Redis + BullMQ
- **Status:** Accepted
- **Context:** Multi-page PDF/OCR extraction and LLM content generation take seconds to minutes and cannot run inside synchronous mobile HTTP requests.
- **Decision:** Introduce **Redis 7 + BullMQ** immediately from Phase 1/2 infrastructure setup (using Docker locally), handling `doc-processing` and `ai-generation` queues with retry/exponential backoff, concurrency caps, progress reporting, and `Idempotency-Key` deduplication.
- **Alternatives Considered:** Database polling cron table without a queue broker.
- **Consequences:** Clean backpressure, automatic retries for transient LLM rate limits, and real-time job status reporting via `GET /documents/:id/status` and `GET /ai/jobs/:jobId`.

---

## ADR-009: Private S3-Compatible Object Storage & Multi-Layer File Validation
- **Status:** Accepted
- **Context:** Uploaded textbooks and exported PPTX decks must never live on ephemeral container filesystems or public URLs.
- **Decision:** Store all raw uploads, avatars, and exported `.pptx` files in **private S3-compatible object storage** (MinIO locally via Docker, AWS S3 / GCS Interop / Cloudflare R2 in production). Enforce server-side MIME, extension, magic-byte inspection, 25 MB limit, and OOXML zip-bomb expansion limits before writing objects. Serve reads strictly through short-lived (`<= 5 min`) pre-signed URLs authorized per request.
- **Alternatives Considered:** Local disk uploads or public S3 buckets.
- **Consequences:** Zero unauthorized file URL leakage and horizontal scalability across stateless backend replicas.

---

## ADR-010: Multi-Provider LLM Abstraction & Official `google-genai` SDK
- **Status:** Accepted
- **Context:** The platform initially uses Google Gemini API but must avoid vendor lock-in per PRD/R&D.
- **Decision:** Define an internal Python `AIProvider` interface (`generate_text`, `generate_structured`, `generate_embedding`, `analyze_document`) with a primary `GeminiProvider` built on the official `google-genai` SDK (`gemini-2.5-flash` for fast structured tasks/quizzes, configurable `gemini-2.5-pro` for deep pedagogical analysis, and 768-dim `text-embedding-004`/`gemini-embedding-001` embeddings). All LLM calls return normalized token usage and estimated USD cost for `ai_usage_logs`.
- **Alternatives Considered:** Calling Gemini HTTP endpoints directly inside generators or relying on deprecated `google-generativeai`.
- **Consequences:** Future addition of OpenAI, Anthropic, or self-hosted vLLM requires implementing one adapter class without touching generators or Node.js code.

---

## ADR-011: Source Grounding, RAG Retrieval & Prompt Injection Defense
- **Status:** Accepted
- **Context:** Uploaded textbooks/modules are untrusted user-supplied text that could contain accidental formatting anomalies or malicious prompt-injection instructions, and LLMs can hallucinate beyond source material.
- **Decision:**
  1. Never allow document text into `system_instruction`. Wrap retrieved chunks in explicit `<untrusted_source_document page="X">` delimiters with instructions to ignore directives inside source text.
  2. Scope `pgvector` retrieval strictly to `WHERE document_id = $1`.
  3. Enforce `source_reference` (`page`, `chunk_index`) and `unfound_info_flags` on all structured outputs; Python post-validators reject references to nonexistent page numbers or malformed answers before returning to Node.js.
  4. Require explicit teacher approval (`POST /contents/:id/approve`) before publishing.
- **Alternatives Considered:** Trusting raw LLM JSON output or auto-publishing drafts.
- **Consequences:** High factual fidelity, verifiable page citations in the teacher editor, and strong protection against prompt injection.

---

## ADR-012: Two-Stage Presentation Generation (Structured JSON -> `python-pptx`)
- **Status:** Accepted
- **Context:** LLMs cannot reliably generate valid OpenXML binary `.pptx` archives directly.
- **Decision:** LLM generates a validated `Presentation` JSON schema (slides, layouts, bullets, speaker notes, visual recommendations, source pages). Teachers preview/edit the structured slides in Flutter; upon export (`POST /contents/:id/export/pptx`), Python renders the styled `.pptx` file deterministically with `python-pptx` and uploads it to private S3.
- **Alternatives Considered:** Asking LLM to output Python scripts or raw XML.
- **Consequences:** Zero code-execution risk, editable slide text before export, and consistent slide typography.

---

## ADR-013: Declarative Template-Based Game Engine (6 Native Flutter Renderers)
- **Status:** Accepted
- **Context:** Generating arbitrary Dart/Flutter/JS game code via AI creates severe security, stability, and layout breakage risks.
- **Decision:** AI outputs strictly validated declarative JSON configurations for 6 fixed templates (`quiz_battle`, `word_matching`, `true_false`, `memory_cards`, `crossword`, `word_puzzle`). Python includes geometric intersection validation for `crossword` grids. Flutter renders each type using purpose-built reusable widgets, and the Node.js backend validates submitted scores against `max_possible_score`.
- **Alternatives Considered:** WebView HTML/JS games generated by AI.
- **Consequences:** Zero code injection risk, native 60fps Android performance, offline play capability, and consistent UI.

---

## ADR-014: Security Governance, Secrets Hygiene & Quota Controls
- **Status:** Accepted
- **Context:** Educational platforms store minor/student learning records and invoke metered paid AI APIs.
- **Decision:**
  - Strict `.gitignore` blocking `.env*`, private keys, SQL dumps, logs, and build folders; commit only `.env.example` placeholders.
  - Sensitive security events logged to `audit_logs` without storing plaintext secrets or full student answers in logs.
  - Daily and monthly per-teacher AI token/job quotas enforced in Node.js (`GET /api/v1/ai/quota`) plus Redis rate limiting across auth, upload, and AI routes.
- **Alternatives Considered:** Unmetered AI requests and application-file logging only.
- **Consequences:** Predictable AI operating costs, clear forensic audit trail, and strong compliance posture against accidental secret leakage.
