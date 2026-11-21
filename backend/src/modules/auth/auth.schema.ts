import { z } from 'zod';
import { UserRole } from '@prisma/client';

export const registerSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(255),
  password: z
    .string()
    .min(8, 'Password must be at least 8 characters')
    .max(128)
    .regex(/[A-Z]/, 'Password must include an uppercase letter')
    .regex(/[a-z]/, 'Password must include a lowercase letter')
    .regex(/[0-9]/, 'Password must include a number'),
  fullName: z.string().trim().min(2).max(150),
  role: z.enum([UserRole.TEACHER, UserRole.STUDENT]),
  institutionName: z.string().trim().max(150).optional(),
  subjectSpecialty: z.string().trim().max(120).optional(),
  gradeLevel: z.string().trim().max(60).optional(),
  preferredLocale: z.enum(['id', 'en']).default('id'),
  deviceName: z.string().trim().max(120).optional(),
});

export const loginSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  password: z.string().min(1),
  deviceName: z.string().trim().max(120).optional(),
});

export const refreshSchema = z.object({
  refreshToken: z.string().min(16),
  deviceName: z.string().trim().max(120).optional(),
});

export const logoutSchema = z.object({
  refreshToken: z.string().min(16),
});

export const forgotPasswordSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
});

export const resetPasswordSchema = z.object({
  resetToken: z.string().min(16),
  newPassword: z
    .string()
    .min(8)
    .max(128)
    .regex(/[A-Z]/)
    .regex(/[a-z]/)
    .regex(/[0-9]/),
});

export type RegisterInput = z.infer<typeof registerSchema>;
export type LoginInput = z.infer<typeof loginSchema>;
