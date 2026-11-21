import { QuestionType } from '@prisma/client';

export interface GradeableQuestion {
  id: string;
  questionType: QuestionType;
  correctAnswer: string;
  points: number;
}

export interface GradeableAnswer {
  questionId: string;
  studentAnswer: string | null;
}

export interface GradedAnswerResult {
  questionId: string;
  isCorrect: boolean | null;
  awardedPoints: number;
  requiresManualGrading: boolean;
}

export function normalizeObjectiveText(value: string | null | undefined): string {
  return (value ?? '').trim().toLowerCase().replace(/\s+/g, ' ');
}

export function gradeObjectiveAnswers(
  questions: GradeableQuestion[],
  answers: GradeableAnswer[],
): {
  results: GradedAnswerResult[];
  autoScore: number;
  maxScore: number;
  hasPendingManualGrading: boolean;
} {
  const answerMap = new Map(answers.map((a) => [a.questionId, a.studentAnswer]));
  let autoScore = 0;
  let maxScore = 0;
  let hasPendingManualGrading = false;

  const results: GradedAnswerResult[] = questions.map((q) => {
    maxScore += q.points;
    const rawAnswer = answerMap.get(q.id) ?? null;

    if (q.questionType === QuestionType.MULTIPLE_CHOICE || q.questionType === QuestionType.TRUE_FALSE) {
      const isCorrect =
        rawAnswer !== null &&
        normalizeObjectiveText(rawAnswer) === normalizeObjectiveText(q.correctAnswer);
      const awardedPoints = isCorrect ? q.points : 0;
      autoScore += awardedPoints;
      return {
        questionId: q.id,
        isCorrect,
        awardedPoints,
        requiresManualGrading: false,
      };
    }

    hasPendingManualGrading = true;
    return {
      questionId: q.id,
      isCorrect: null,
      awardedPoints: 0,
      requiresManualGrading: true,
    };
  });

  return {
    results,
    autoScore: Number(autoScore.toFixed(2)),
    maxScore: Number(maxScore.toFixed(2)),
    hasPendingManualGrading,
  };
}

export function computeFinalScore(params: {
  autoScore: number;
  manualScore: number;
  maxScore: number;
  passingScorePercent: number;
}): { totalScore: number; percentage: number; passed: boolean } {
  const totalScore = Number((params.autoScore + params.manualScore).toFixed(2));
  const percentage =
    params.maxScore > 0 ? Number(((totalScore / params.maxScore) * 100).toFixed(2)) : 0;
  return {
    totalScore,
    percentage,
    passed: percentage >= params.passingScorePercent,
  };
}
