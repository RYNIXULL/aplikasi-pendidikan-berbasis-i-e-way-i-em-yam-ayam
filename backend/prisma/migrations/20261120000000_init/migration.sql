-- EduAI Ecosystem Initial Schema Migration (24 Tables + pgvector HNSW + Partial Indexes)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";

-- Enums
CREATE TYPE "UserRole" AS ENUM ('TEACHER', 'STUDENT', 'ADMIN');
CREATE TYPE "UserStatus" AS ENUM ('ACTIVE', 'SUSPENDED', 'PENDING_VERIFICATION');
CREATE TYPE "DocumentFormat" AS ENUM ('PDF', 'DOCX', 'PPTX');
CREATE TYPE "DocumentStatus" AS ENUM ('UPLOADED', 'VALIDATING', 'EXTRACTING', 'PROCESSING', 'ANALYZED', 'READY', 'REQUIRES_REVIEW', 'FAILED');
CREATE TYPE "ContentType" AS ENUM ('SUMMARY', 'QUIZ', 'PRESENTATION', 'FLASHCARDS', 'MIND_MAP', 'WORKSHEET', 'GAME');
CREATE TYPE "GameType" AS ENUM ('QUIZ_BATTLE', 'WORD_MATCHING', 'TRUE_FALSE', 'MEMORY_CARDS', 'CROSSWORD', 'WORD_PUZZLE');
CREATE TYPE "JobStatus" AS ENUM ('QUEUED', 'RUNNING', 'VALIDATING', 'SUCCEEDED', 'FAILED', 'CANCELLED');
CREATE TYPE "ContentStatus" AS ENUM ('DRAFT', 'IN_REVIEW', 'APPROVED', 'PUBLISHED', 'ARCHIVED');
CREATE TYPE "VersionOrigin" AS ENUM ('AI_GENERATED', 'TEACHER_EDITED', 'AI_REGENERATED', 'RESTORED');
CREATE TYPE "ClassroomStatus" AS ENUM ('ACTIVE', 'ARCHIVED');
CREATE TYPE "MemberStatus" AS ENUM ('ACTIVE', 'REMOVED');
CREATE TYPE "AssessmentType" AS ENUM ('SELF_QUIZ', 'ASSIGNMENT', 'SCHEDULED_EXAM');
CREATE TYPE "AssessmentStatus" AS ENUM ('DRAFT', 'PUBLISHED', 'CLOSED', 'ARCHIVED');
CREATE TYPE "QuestionType" AS ENUM ('MULTIPLE_CHOICE', 'TRUE_FALSE', 'SHORT_ANSWER', 'ESSAY');
CREATE TYPE "DifficultyLevel" AS ENUM ('EASY', 'MEDIUM', 'HARD');
CREATE TYPE "AttemptStatus" AS ENUM ('IN_PROGRESS', 'SUBMITTED', 'GRADED');
CREATE TYPE "ProgressStatus" AS ENUM ('NOT_STARTED', 'IN_PROGRESS', 'COMPLETED');

-- Domain A: Users & Auth
CREATE TABLE "users" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "email" VARCHAR(255) NOT NULL,
    "password_hash" TEXT NOT NULL,
    "role" "UserRole" NOT NULL,
    "status" "UserStatus" NOT NULL DEFAULT 'ACTIVE',
    "last_login_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(6),
    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "uq_users_email_active" ON "users" (LOWER("email")) WHERE "deleted_at" IS NULL;
CREATE INDEX "idx_users_role" ON "users" ("role");

CREATE TABLE "user_profiles" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "full_name" VARCHAR(150) NOT NULL,
    "display_name" VARCHAR(80),
    "avatar_storage_key" VARCHAR(512),
    "institution_name" VARCHAR(150),
    "subject_specialty" VARCHAR(120),
    "grade_level" VARCHAR(60),
    "bio" TEXT,
    "preferred_locale" VARCHAR(10) NOT NULL DEFAULT 'id',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "user_profiles_user_id_key" UNIQUE ("user_id"),
    CONSTRAINT "user_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);

CREATE TABLE "refresh_tokens" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "family_id" UUID NOT NULL,
    "token_hash" CHAR(64) NOT NULL,
    "device_name" VARCHAR(120),
    "ip_address" VARCHAR(45),
    "user_agent" VARCHAR(255),
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "revoked_at" TIMESTAMPTZ(6),
    "replaced_by_token_id" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "refresh_tokens_token_hash_key" UNIQUE ("token_hash"),
    CONSTRAINT "refresh_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE,
    CONSTRAINT "refresh_tokens_replaced_by_fkey" FOREIGN KEY ("replaced_by_token_id") REFERENCES "refresh_tokens"("id") ON DELETE SET NULL
);
CREATE INDEX "idx_refresh_tokens_family" ON "refresh_tokens" ("family_id");
CREATE INDEX "idx_refresh_tokens_user_active" ON "refresh_tokens" ("user_id", "expires_at") WHERE "revoked_at" IS NULL;

CREATE TABLE "password_reset_tokens" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "token_hash" CHAR(64) NOT NULL,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "used_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "password_reset_tokens_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "password_reset_tokens_token_hash_key" UNIQUE ("token_hash"),
    CONSTRAINT "password_reset_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "idx_pwd_reset_user" ON "password_reset_tokens" ("user_id", "expires_at") WHERE "used_at" IS NULL;

CREATE TABLE "audit_logs" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "actor_user_id" UUID,
    "action" VARCHAR(80) NOT NULL,
    "entity_type" VARCHAR(60) NOT NULL,
    "entity_id" UUID,
    "request_id" VARCHAR(64),
    "ip_address" VARCHAR(45),
    "metadata" JSONB NOT NULL DEFAULT '{}'::jsonb,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "audit_logs_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "users"("id") ON DELETE SET NULL
);
CREATE INDEX "idx_audit_actor_time" ON "audit_logs" ("actor_user_id", "created_at" DESC);
CREATE INDEX "idx_audit_entity" ON "audit_logs" ("entity_type", "entity_id");

-- Domain B: Document Intelligence
CREATE TABLE "documents" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "teacher_id" UUID NOT NULL,
    "title" VARCHAR(200) NOT NULL,
    "description" TEXT,
    "subject" VARCHAR(100) NOT NULL,
    "topic" VARCHAR(150),
    "original_filename" VARCHAR(255) NOT NULL,
    "file_format" "DocumentFormat" NOT NULL,
    "mime_type" VARCHAR(120) NOT NULL,
    "file_size_bytes" BIGINT NOT NULL CHECK ("file_size_bytes" > 0),
    "sha256_checksum" CHAR(64) NOT NULL,
    "storage_bucket" VARCHAR(100) NOT NULL,
    "storage_key" VARCHAR(512) NOT NULL,
    "page_count" INTEGER,
    "word_count" INTEGER,
    "status" "DocumentStatus" NOT NULL DEFAULT 'UPLOADED',
    "processing_progress" SMALLINT NOT NULL DEFAULT 0 CHECK ("processing_progress" BETWEEN 0 AND 100),
    "failure_code" VARCHAR(60),
    "failure_message" TEXT,
    "processed_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(6),
    CONSTRAINT "documents_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "documents_storage_key_key" UNIQUE ("storage_key"),
    CONSTRAINT "documents_teacher_id_fkey" FOREIGN KEY ("teacher_id") REFERENCES "users"("id") ON DELETE RESTRICT
);
CREATE INDEX "idx_documents_teacher_active" ON "documents" ("teacher_id", "created_at" DESC) WHERE "deleted_at" IS NULL;
CREATE INDEX "idx_documents_teacher_subject" ON "documents" ("teacher_id", "subject") WHERE "deleted_at" IS NULL;
CREATE INDEX "idx_documents_sha256" ON "documents" ("teacher_id", "sha256_checksum") WHERE "deleted_at" IS NULL;

CREATE TABLE "document_pages" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "document_id" UUID NOT NULL,
    "page_number" INTEGER NOT NULL CHECK ("page_number" >= 1),
    "heading" VARCHAR(255),
    "raw_text" TEXT NOT NULL,
    "normalized_text" TEXT NOT NULL,
    "extraction_method" VARCHAR(30) NOT NULL,
    "char_count" INTEGER NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "document_pages_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "document_pages_doc_page_key" UNIQUE ("document_id", "page_number"),
    CONSTRAINT "document_pages_document_id_fkey" FOREIGN KEY ("document_id") REFERENCES "documents"("id") ON DELETE CASCADE
);

CREATE TABLE "document_chunks" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "document_id" UUID NOT NULL,
    "chunk_index" INTEGER NOT NULL CHECK ("chunk_index" >= 0),
    "chapter_title" VARCHAR(255),
    "section_title" VARCHAR(255),
    "page_start" INTEGER NOT NULL,
    "page_end" INTEGER NOT NULL,
    "token_count" INTEGER NOT NULL,
    "content" TEXT NOT NULL,
    "embedding" vector(768),
    "metadata" JSONB NOT NULL DEFAULT '{}'::jsonb,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "document_chunks_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "document_chunks_doc_chunk_key" UNIQUE ("document_id", "chunk_index"),
    CONSTRAINT "document_chunks_document_id_fkey" FOREIGN KEY ("document_id") REFERENCES "documents"("id") ON DELETE CASCADE
);
CREATE INDEX "idx_chunks_embedding_hnsw" ON "document_chunks" USING hnsw ("embedding" vector_cosine_ops) WITH (m = 16, ef_construction = 64);

CREATE TABLE "document_analyses" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "document_id" UUID NOT NULL,
    "document_sha256" CHAR(64) NOT NULL,
    "detected_subject" VARCHAR(120) NOT NULL,
    "main_topic" VARCHAR(255) NOT NULL,
    "language" VARCHAR(16) NOT NULL DEFAULT 'id',
    "subtopics" JSONB NOT NULL,
    "key_concepts" JSONB NOT NULL,
    "definitions" JSONB NOT NULL,
    "learning_objectives" JSONB NOT NULL,
    "chapter_structure" JSONB NOT NULL,
    "model_name" VARCHAR(80) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "document_analyses_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "document_analyses_doc_sha_key" UNIQUE ("document_id", "document_sha256"),
    CONSTRAINT "document_analyses_document_id_fkey" FOREIGN KEY ("document_id") REFERENCES "documents"("id") ON DELETE CASCADE
);

-- Domain C: AI Generation, Versioning & Usage
CREATE TABLE "generation_jobs" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "teacher_id" UUID NOT NULL,
    "document_id" UUID NOT NULL,
    "content_type" "ContentType" NOT NULL,
    "game_type" "GameType",
    "idempotency_key" VARCHAR(100),
    "bull_job_id" VARCHAR(100),
    "request_config" JSONB NOT NULL,
    "status" "JobStatus" NOT NULL DEFAULT 'QUEUED',
    "progress" SMALLINT NOT NULL DEFAULT 0 CHECK ("progress" BETWEEN 0 AND 100),
    "attempt_count" SMALLINT NOT NULL DEFAULT 0,
    "error_code" VARCHAR(60),
    "error_message" TEXT,
    "started_at" TIMESTAMPTZ(6),
    "completed_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "generation_jobs_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "generation_jobs_teacher_id_fkey" FOREIGN KEY ("teacher_id") REFERENCES "users"("id") ON DELETE RESTRICT,
    CONSTRAINT "generation_jobs_document_id_fkey" FOREIGN KEY ("document_id") REFERENCES "documents"("id") ON DELETE CASCADE
);
CREATE UNIQUE INDEX "uq_gen_jobs_idempotency" ON "generation_jobs" ("teacher_id", "idempotency_key") WHERE "idempotency_key" IS NOT NULL;
CREATE INDEX "idx_gen_jobs_teacher_status" ON "generation_jobs" ("teacher_id", "status", "created_at" DESC);

CREATE TABLE "generated_contents" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "teacher_id" UUID NOT NULL,
    "document_id" UUID NOT NULL,
    "generation_job_id" UUID,
    "content_type" "ContentType" NOT NULL,
    "game_type" "GameType",
    "title" VARCHAR(255) NOT NULL,
    "subject" VARCHAR(100),
    "status" "ContentStatus" NOT NULL DEFAULT 'DRAFT',
    "current_version_id" UUID,
    "approved_version_id" UUID,
    "approved_by" UUID,
    "approved_at" TIMESTAMPTZ(6),
    "export_storage_key" VARCHAR(512),
    "export_generated_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(6),
    CONSTRAINT "generated_contents_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "generated_contents_job_id_key" UNIQUE ("generation_job_id"),
    CONSTRAINT "generated_contents_teacher_id_fkey" FOREIGN KEY ("teacher_id") REFERENCES "users"("id") ON DELETE RESTRICT,
    CONSTRAINT "generated_contents_document_id_fkey" FOREIGN KEY ("document_id") REFERENCES "documents"("id") ON DELETE RESTRICT,
    CONSTRAINT "generated_contents_job_id_fkey" FOREIGN KEY ("generation_job_id") REFERENCES "generation_jobs"("id") ON DELETE SET NULL,
    CONSTRAINT "generated_contents_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "users"("id") ON DELETE SET NULL
);
CREATE INDEX "idx_contents_teacher_active" ON "generated_contents" ("teacher_id", "content_type", "status") WHERE "deleted_at" IS NULL;
CREATE INDEX "idx_contents_document" ON "generated_contents" ("document_id") WHERE "deleted_at" IS NULL;

CREATE TABLE "generation_versions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "content_id" UUID NOT NULL,
    "version_number" INTEGER NOT NULL CHECK ("version_number" >= 1),
    "created_by" UUID NOT NULL,
    "origin" "VersionOrigin" NOT NULL,
    "change_note" VARCHAR(255),
    "payload" JSONB NOT NULL,
    "source_references" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "validation_report" JSONB NOT NULL DEFAULT '{}'::jsonb,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "generation_versions_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "generation_versions_content_ver_key" UNIQUE ("content_id", "version_number"),
    CONSTRAINT "generation_versions_content_id_fkey" FOREIGN KEY ("content_id") REFERENCES "generated_contents"("id") ON DELETE CASCADE,
    CONSTRAINT "generation_versions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE RESTRICT
);

CREATE TABLE "ai_usage_logs" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "document_id" UUID,
    "generation_job_id" UUID,
    "operation" VARCHAR(60) NOT NULL,
    "provider" VARCHAR(40) NOT NULL,
    "model" VARCHAR(80) NOT NULL,
    "prompt_tokens" INTEGER NOT NULL DEFAULT 0,
    "completion_tokens" INTEGER NOT NULL DEFAULT 0,
    "total_tokens" INTEGER NOT NULL DEFAULT 0,
    "estimated_cost_usd" DECIMAL(10,6) NOT NULL DEFAULT 0,
    "latency_ms" INTEGER NOT NULL DEFAULT 0,
    "success" BOOLEAN NOT NULL,
    "error_code" VARCHAR(60),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ai_usage_logs_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "ai_usage_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT,
    CONSTRAINT "ai_usage_logs_document_id_fkey" FOREIGN KEY ("document_id") REFERENCES "documents"("id") ON DELETE SET NULL,
    CONSTRAINT "ai_usage_logs_job_id_fkey" FOREIGN KEY ("generation_job_id") REFERENCES "generation_jobs"("id") ON DELETE SET NULL
);
CREATE INDEX "idx_ai_usage_user_date" ON "ai_usage_logs" ("user_id", "created_at" DESC);

-- Domain D: Classrooms
CREATE TABLE "classrooms" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "teacher_id" UUID NOT NULL,
    "name" VARCHAR(150) NOT NULL,
    "subject" VARCHAR(100) NOT NULL,
    "grade_level" VARCHAR(60),
    "description" TEXT,
    "join_code" VARCHAR(12) NOT NULL,
    "join_code_enabled" BOOLEAN NOT NULL DEFAULT true,
    "status" "ClassroomStatus" NOT NULL DEFAULT 'ACTIVE',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(6),
    CONSTRAINT "classrooms_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "classrooms_teacher_id_fkey" FOREIGN KEY ("teacher_id") REFERENCES "users"("id") ON DELETE RESTRICT
);
CREATE UNIQUE INDEX "uq_classrooms_join_code_active" ON "classrooms" ("join_code") WHERE "deleted_at" IS NULL;
CREATE INDEX "idx_classrooms_teacher" ON "classrooms" ("teacher_id", "status") WHERE "deleted_at" IS NULL;

CREATE TABLE "classroom_members" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "classroom_id" UUID NOT NULL,
    "student_id" UUID NOT NULL,
    "status" "MemberStatus" NOT NULL DEFAULT 'ACTIVE',
    "joined_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "removed_at" TIMESTAMPTZ(6),
    CONSTRAINT "classroom_members_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "classroom_members_class_student_key" UNIQUE ("classroom_id", "student_id"),
    CONSTRAINT "classroom_members_classroom_id_fkey" FOREIGN KEY ("classroom_id") REFERENCES "classrooms"("id") ON DELETE CASCADE,
    CONSTRAINT "classroom_members_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "idx_members_student_active" ON "classroom_members" ("student_id") WHERE "status" = 'ACTIVE';

CREATE TABLE "classroom_materials" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "classroom_id" UUID NOT NULL,
    "content_id" UUID NOT NULL,
    "published_version_id" UUID NOT NULL,
    "published_by" UUID NOT NULL,
    "title" VARCHAR(255) NOT NULL,
    "description" TEXT,
    "display_order" INTEGER NOT NULL DEFAULT 0,
    "is_visible" BOOLEAN NOT NULL DEFAULT true,
    "published_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "classroom_materials_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "classroom_materials_class_content_key" UNIQUE ("classroom_id", "content_id"),
    CONSTRAINT "classroom_materials_classroom_id_fkey" FOREIGN KEY ("classroom_id") REFERENCES "classrooms"("id") ON DELETE CASCADE,
    CONSTRAINT "classroom_materials_content_id_fkey" FOREIGN KEY ("content_id") REFERENCES "generated_contents"("id") ON DELETE RESTRICT,
    CONSTRAINT "classroom_materials_version_id_fkey" FOREIGN KEY ("published_version_id") REFERENCES "generation_versions"("id") ON DELETE RESTRICT,
    CONSTRAINT "classroom_materials_published_by_fkey" FOREIGN KEY ("published_by") REFERENCES "users"("id") ON DELETE RESTRICT
);
CREATE INDEX "idx_classroom_materials_order" ON "classroom_materials" ("classroom_id", "is_visible", "display_order");

-- Domain E: Assessments
CREATE TABLE "assessments" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "classroom_id" UUID NOT NULL,
    "teacher_id" UUID NOT NULL,
    "source_content_id" UUID,
    "title" VARCHAR(255) NOT NULL,
    "instructions" TEXT,
    "assessment_type" "AssessmentType" NOT NULL,
    "status" "AssessmentStatus" NOT NULL DEFAULT 'DRAFT',
    "time_limit_seconds" INTEGER CHECK ("time_limit_seconds" > 0),
    "max_attempts" SMALLINT NOT NULL DEFAULT 1 CHECK ("max_attempts" >= 1),
    "passing_score" DECIMAL(5,2) NOT NULL DEFAULT 70.00,
    "total_points" DECIMAL(7,2) NOT NULL DEFAULT 0,
    "shuffle_questions" BOOLEAN NOT NULL DEFAULT false,
    "show_explanations" BOOLEAN NOT NULL DEFAULT true,
    "available_from" TIMESTAMPTZ(6),
    "available_until" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(6),
    CONSTRAINT "assessments_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "assessments_classroom_id_fkey" FOREIGN KEY ("classroom_id") REFERENCES "classrooms"("id") ON DELETE CASCADE,
    CONSTRAINT "assessments_teacher_id_fkey" FOREIGN KEY ("teacher_id") REFERENCES "users"("id") ON DELETE RESTRICT,
    CONSTRAINT "assessments_source_content_id_fkey" FOREIGN KEY ("source_content_id") REFERENCES "generated_contents"("id") ON DELETE SET NULL
);
CREATE INDEX "idx_assessments_classroom_status" ON "assessments" ("classroom_id", "status") WHERE "deleted_at" IS NULL;

CREATE TABLE "assessment_questions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "assessment_id" UUID NOT NULL,
    "question_order" INTEGER NOT NULL CHECK ("question_order" >= 1),
    "question_type" "QuestionType" NOT NULL,
    "difficulty" "DifficultyLevel" NOT NULL DEFAULT 'MEDIUM',
    "prompt" TEXT NOT NULL,
    "options" JSONB,
    "correct_answer" TEXT NOT NULL,
    "explanation" TEXT,
    "points" DECIMAL(6,2) NOT NULL DEFAULT 10.00 CHECK ("points" > 0),
    "source_reference" JSONB,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "assessment_questions_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "assessment_questions_order_key" UNIQUE ("assessment_id", "question_order"),
    CONSTRAINT "assessment_questions_assessment_id_fkey" FOREIGN KEY ("assessment_id") REFERENCES "assessments"("id") ON DELETE CASCADE
);

CREATE TABLE "assessment_attempts" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "assessment_id" UUID NOT NULL,
    "student_id" UUID NOT NULL,
    "attempt_number" SMALLINT NOT NULL CHECK ("attempt_number" >= 1),
    "status" "AttemptStatus" NOT NULL DEFAULT 'IN_PROGRESS',
    "started_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expires_at" TIMESTAMPTZ(6),
    "submitted_at" TIMESTAMPTZ(6),
    "graded_at" TIMESTAMPTZ(6),
    "graded_by" UUID,
    "auto_score" DECIMAL(7,2) NOT NULL DEFAULT 0,
    "manual_score" DECIMAL(7,2) NOT NULL DEFAULT 0,
    "total_score" DECIMAL(7,2) NOT NULL DEFAULT 0,
    "percentage" DECIMAL(5,2) NOT NULL DEFAULT 0,
    "passed" BOOLEAN,
    CONSTRAINT "assessment_attempts_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "assessment_attempts_unique_num" UNIQUE ("assessment_id", "student_id", "attempt_number"),
    CONSTRAINT "assessment_attempts_assessment_id_fkey" FOREIGN KEY ("assessment_id") REFERENCES "assessments"("id") ON DELETE RESTRICT,
    CONSTRAINT "assessment_attempts_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "users"("id") ON DELETE RESTRICT,
    CONSTRAINT "assessment_attempts_graded_by_fkey" FOREIGN KEY ("graded_by") REFERENCES "users"("id") ON DELETE SET NULL
);
CREATE INDEX "idx_attempts_student" ON "assessment_attempts" ("student_id", "started_at" DESC);
CREATE INDEX "idx_attempts_assessment_status" ON "assessment_attempts" ("assessment_id", "status");

CREATE TABLE "assessment_answers" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "attempt_id" UUID NOT NULL,
    "question_id" UUID NOT NULL,
    "student_answer" TEXT,
    "is_correct" BOOLEAN,
    "awarded_points" DECIMAL(6,2) NOT NULL DEFAULT 0,
    "requires_manual_grading" BOOLEAN NOT NULL DEFAULT false,
    "teacher_feedback" TEXT,
    "answered_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "assessment_answers_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "assessment_answers_unique_q" UNIQUE ("attempt_id", "question_id"),
    CONSTRAINT "assessment_answers_attempt_id_fkey" FOREIGN KEY ("attempt_id") REFERENCES "assessment_attempts"("id") ON DELETE CASCADE,
    CONSTRAINT "assessment_answers_question_id_fkey" FOREIGN KEY ("question_id") REFERENCES "assessment_questions"("id") ON DELETE RESTRICT
);

-- Domain F: Progress, Games & Analytics
CREATE TABLE "student_progress" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "student_id" UUID NOT NULL,
    "classroom_id" UUID NOT NULL,
    "material_id" UUID NOT NULL,
    "status" "ProgressStatus" NOT NULL DEFAULT 'NOT_STARTED',
    "completion_percentage" SMALLINT NOT NULL DEFAULT 0 CHECK ("completion_percentage" BETWEEN 0 AND 100),
    "time_spent_seconds" INTEGER NOT NULL DEFAULT 0,
    "last_accessed_at" TIMESTAMPTZ(6),
    "completed_at" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "student_progress_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "student_progress_unique" UNIQUE ("student_id", "material_id"),
    CONSTRAINT "student_progress_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "users"("id") ON DELETE CASCADE,
    CONSTRAINT "student_progress_classroom_id_fkey" FOREIGN KEY ("classroom_id") REFERENCES "classrooms"("id") ON DELETE CASCADE,
    CONSTRAINT "student_progress_material_id_fkey" FOREIGN KEY ("material_id") REFERENCES "classroom_materials"("id") ON DELETE CASCADE
);
CREATE INDEX "idx_progress_student_classroom" ON "student_progress" ("student_id", "classroom_id");

CREATE TABLE "game_sessions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "student_id" UUID NOT NULL,
    "classroom_id" UUID NOT NULL,
    "material_id" UUID NOT NULL,
    "game_type" "GameType" NOT NULL,
    "score" INTEGER NOT NULL CHECK ("score" >= 0),
    "max_score" INTEGER NOT NULL CHECK ("max_score" > 0),
    "accuracy_percentage" DECIMAL(5,2) NOT NULL,
    "duration_seconds" INTEGER NOT NULL CHECK ("duration_seconds" >= 0),
    "streak_max" INTEGER NOT NULL DEFAULT 0,
    "completed" BOOLEAN NOT NULL DEFAULT true,
    "session_summary" JSONB NOT NULL DEFAULT '{}'::jsonb,
    "played_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "game_sessions_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "game_sessions_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "users"("id") ON DELETE CASCADE,
    CONSTRAINT "game_sessions_classroom_id_fkey" FOREIGN KEY ("classroom_id") REFERENCES "classrooms"("id") ON DELETE CASCADE,
    CONSTRAINT "game_sessions_material_id_fkey" FOREIGN KEY ("material_id") REFERENCES "classroom_materials"("id") ON DELETE CASCADE
);
CREATE INDEX "idx_game_sessions_leaderboard" ON "game_sessions" ("material_id", "score" DESC, "duration_seconds" ASC);
CREATE INDEX "idx_game_sessions_student" ON "game_sessions" ("student_id", "played_at" DESC);

CREATE TABLE "learning_activities" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "student_id" UUID NOT NULL,
    "classroom_id" UUID,
    "activity_type" VARCHAR(60) NOT NULL,
    "reference_type" VARCHAR(40),
    "reference_id" UUID,
    "metadata" JSONB NOT NULL DEFAULT '{}'::jsonb,
    "occurred_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "learning_activities_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "learning_activities_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "users"("id") ON DELETE CASCADE,
    CONSTRAINT "learning_activities_classroom_id_fkey" FOREIGN KEY ("classroom_id") REFERENCES "classrooms"("id") ON DELETE SET NULL
);
CREATE INDEX "idx_learning_activities_student_time" ON "learning_activities" ("student_id", "occurred_at" DESC);

CREATE TABLE "learning_analytics" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "classroom_id" UUID NOT NULL,
    "assessment_id" UUID,
    "metric_scope" VARCHAR(40) NOT NULL,
    "total_students" INTEGER NOT NULL DEFAULT 0,
    "completion_rate" DECIMAL(5,2) NOT NULL DEFAULT 0,
    "average_score" DECIMAL(5,2) NOT NULL DEFAULT 0,
    "score_distribution" JSONB NOT NULL DEFAULT '{}'::jsonb,
    "question_item_stats" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "computed_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "learning_analytics_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "learning_analytics_classroom_id_fkey" FOREIGN KEY ("classroom_id") REFERENCES "classrooms"("id") ON DELETE CASCADE,
    CONSTRAINT "learning_analytics_assessment_id_fkey" FOREIGN KEY ("assessment_id") REFERENCES "assessments"("id") ON DELETE CASCADE
);
CREATE INDEX "idx_analytics_classroom_scope" ON "learning_analytics" ("classroom_id", "metric_scope", "computed_at" DESC);
