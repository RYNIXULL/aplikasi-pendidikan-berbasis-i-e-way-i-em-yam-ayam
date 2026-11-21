import { describe, expect, it } from 'vitest';
import { AppError } from '../src/common/errors';
import { buildPagination } from '../src/common/response';
import { computeFinalScore, normalizeObjectiveText } from '../src/modules/assessments/grading';

describe('Backend Domain Invariants & Contract Helpers', () => {
  it('computes safe pagination metadata including empty result sets', () => {
    expect(buildPagination(1, 20, 0)).toEqual({
      page: 1,
      limit: 20,
      total: 0,
      totalPages: 1,
    });
    expect(buildPagination(2, 10, 25)).toEqual({
      page: 2,
      limit: 10,
      total: 25,
      totalPages: 3,
    });
  });

  it('normalizes objective answers deterministically across spacing and casing', () => {
    expect(normalizeObjectiveText('  Enzim   Pepsin ')).toBe('enzim pepsin');
    expect(normalizeObjectiveText(null)).toBe('');
  });

  it('computes passing boundary accurately at exact passingScorePercent threshold', () => {
    const exactPass = computeFinalScore({
      autoScore: 70,
      manualScore: 0,
      maxScore: 100,
      passingScorePercent: 70,
    });
    expect(exactPass.passed).toBe(true);
    expect(exactPass.percentage).toBe(70);

    const justBelow = computeFinalScore({
      autoScore: 69.5,
      manualScore: 0,
      maxScore: 100,
      passingScorePercent: 70,
    });
    expect(justBelow.passed).toBe(false);
  });

  it('constructs typed AppError payloads with machine-readable error codes', () => {
    const err = new AppError(429, 'AI_QUOTA_EXCEEDED', 'Daily quota reached', [
      { field: 'quota', issue: '0 remaining' },
    ]);
    expect(err.statusCode).toBe(429);
    expect(err.code).toBe('AI_QUOTA_EXCEEDED');
    expect(err.details).toHaveLength(1);
  });
});
