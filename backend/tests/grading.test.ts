import { describe, expect, it } from 'vitest';
import { QuestionType } from '@prisma/client';
import { computeFinalScore, gradeObjectiveAnswers } from '../src/modules/assessments/grading';

describe('Assessment Hybrid Grading Engine', () => {
  it('auto-grades MULTIPLE_CHOICE and TRUE_FALSE ignoring case and extra whitespace', () => {
    const questions = [
      { id: 'q1', questionType: QuestionType.MULTIPLE_CHOICE, correctAnswer: 'Mencerna makanan', points: 10 },
      { id: 'q2', questionType: QuestionType.TRUE_FALSE, correctAnswer: 'Benar', points: 10 },
      { id: 'q3', questionType: QuestionType.MULTIPLE_CHOICE, correctAnswer: 'Usus halus', points: 10 },
    ];
    const answers = [
      { questionId: 'q1', studentAnswer: '  mencerna   makanan ' },
      { questionId: 'q2', studentAnswer: 'benar' },
      { questionId: 'q3', studentAnswer: 'Jantung' },
    ];

    const res = gradeObjectiveAnswers(questions, answers);
    expect(res.hasPendingManualGrading).toBe(false);
    expect(res.autoScore).toBe(20);
    expect(res.maxScore).toBe(30);
    expect(res.results[0].isCorrect).toBe(true);
    expect(res.results[1].isCorrect).toBe(true);
    expect(res.results[2].isCorrect).toBe(false);
  });

  it('flags ESSAY and SHORT_ANSWER for manual teacher grading', () => {
    const questions = [
      { id: 'q1', questionType: QuestionType.MULTIPLE_CHOICE, correctAnswer: 'Pepsin', points: 10 },
      { id: 'q2', questionType: QuestionType.ESSAY, correctAnswer: 'Rubrik penjelasan enzim', points: 20 },
    ];
    const answers = [
      { questionId: 'q1', studentAnswer: 'Pepsin' },
      { questionId: 'q2', studentAnswer: 'Pepsin memecah protein menjadi pepton di lambung.' },
    ];

    const res = gradeObjectiveAnswers(questions, answers);
    expect(res.hasPendingManualGrading).toBe(true);
    expect(res.autoScore).toBe(10);
    expect(res.results[1].requiresManualGrading).toBe(true);
    expect(res.results[1].isCorrect).toBeNull();

    const finalScore = computeFinalScore({
      autoScore: res.autoScore,
      manualScore: 18,
      maxScore: res.maxScore,
      passingScorePercent: 70,
    });
    expect(finalScore.totalScore).toBe(28);
    expect(finalScore.percentage).toBe(93.33);
    expect(finalScore.passed).toBe(true);
  });
});
