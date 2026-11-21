import dotenv from 'dotenv';
import { z } from 'zod';

dotenv.config();

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'staging', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  CORS_ORIGINS: z.string().default('http://localhost:3000'),
  DATABASE_URL: z
    .string()
    .default('postgresql://edu_ai_user:dev_placeholder@localhost:5432/edu_ai_db?schema=public'),
  REDIS_URL: z.string().default('redis://localhost:6379'),
  S3_ENDPOINT: z.string().default('http://localhost:9000'),
  S3_PUBLIC_ENDPOINT: z.string().default('http://localhost:9000'),
  S3_REGION: z.string().default('us-east-1'),
  S3_BUCKET: z.string().default('edu-ai-private'),
  S3_ACCESS_KEY_ID: z.string().default('dev_access_key'),
  S3_SECRET_ACCESS_KEY: z.string().default('dev_secret_key'),
  S3_FORCE_PATH_STYLE: z
    .string()
    .default('true')
    .transform((v) => v === 'true'),
  JWT_ACCESS_SECRET: z.string().min(16).default('dev-only-jwt-access-secret-replace-me-32chars'),
  JWT_ACCESS_EXPIRES_SECONDS: z.coerce.number().int().positive().default(900),
  JWT_REFRESH_PEPPER: z.string().min(16).default('dev-only-refresh-pepper-replace-me-32chars'),
  JWT_REFRESH_EXPIRES_DAYS: z.coerce.number().int().positive().default(30),
  AI_SERVICE_BASE_URL: z.string().default('http://localhost:8000'),
  INTERNAL_SERVICE_TOKEN: z.string().min(16).default('dev-only-internal-service-token-replace'),
  INTERNAL_HMAC_SECRET: z.string().min(16).default('dev-only-internal-hmac-secret-replace-32'),
  AI_DAILY_JOB_QUOTA: z.coerce.number().int().positive().default(50),
  AI_DAILY_TOKEN_QUOTA: z.coerce.number().int().positive().default(500000),
  MAX_UPLOAD_BYTES: z.coerce.number().int().positive().default(26214400),
  MAX_ZIP_UNCOMPRESSED_BYTES: z.coerce.number().int().positive().default(104857600),
});

export type AppEnv = z.infer<typeof envSchema>;

export const env: AppEnv = envSchema.parse(process.env);
