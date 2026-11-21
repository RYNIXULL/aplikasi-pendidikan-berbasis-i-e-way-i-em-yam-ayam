import { logger } from '../../config/logger';

export interface MailProvider {
  sendPasswordResetEmail(params: { toEmail: string; resetToken: string; expiresMinutes: number }): Promise<void>;
}

class ConsoleDevMailProvider implements MailProvider {
  async sendPasswordResetEmail(params: {
    toEmail: string;
    resetToken: string;
    expiresMinutes: number;
  }): Promise<void> {
    // Development-only structured notice without logging raw token in production
    logger.info(
      {
        toEmail: params.toEmail,
        expiresMinutes: params.expiresMinutes,
        provider: 'console_dev',
      },
      'Password reset email queued via dev adapter (configure SMTP provider for production)',
    );
  }
}

export const mailProvider: MailProvider = new ConsoleDevMailProvider();
