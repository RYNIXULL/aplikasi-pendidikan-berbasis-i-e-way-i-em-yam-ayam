import { prisma } from '../../config/prisma';
import { env } from '../../config/env';
import { AppError } from '../../common/errors';

export async function getTeacherAiQuotaStatus(teacherId: string) {
  const startOfDay = new Date();
  startOfDay.setUTCHours(0, 0, 0, 0);

  const [jobsToday, usageAgg] = await Promise.all([
    prisma.generationJob.count({
      where: {
        teacherId,
        createdAt: { gte: startOfDay },
      },
    }),
    prisma.aiUsageLog.aggregate({
      where: {
        userId: teacherId,
        createdAt: { gte: startOfDay },
      },
      _sum: {
        totalTokens: true,
        estimatedCostUsd: true,
      },
    }),
  ]);

  const tokensUsedToday = usageAgg._sum.totalTokens ?? 0;
  const estimatedCostTodayUsd = Number(usageAgg._sum.estimatedCostUsd ?? 0);

  return {
    dailyJobLimit: env.AI_DAILY_JOB_QUOTA,
    jobsUsedToday: jobsToday,
    jobsRemainingToday: Math.max(0, env.AI_DAILY_JOB_QUOTA - jobsToday),
    dailyTokenLimit: env.AI_DAILY_TOKEN_QUOTA,
    tokensUsedToday,
    tokensRemainingToday: Math.max(0, env.AI_DAILY_TOKEN_QUOTA - tokensUsedToday),
    estimatedCostTodayUsd,
  };
}

export async function enforceTeacherAiQuota(teacherId: string): Promise<void> {
  const quota = await getTeacherAiQuotaStatus(teacherId);
  if (quota.jobsRemainingToday <= 0 || quota.tokensRemainingToday <= 0) {
    throw new AppError(
      429,
      'AI_QUOTA_EXCEEDED',
      'Daily AI generation quota reached. Please try again tomorrow.',
    );
  }
}
