import { Router } from 'express';
import { authRateLimiter } from '../../common/middleware/rateLimit';
import { requireAuth } from '../../common/middleware/auth';
import { validateBody } from '../../common/middleware/validate';
import { sendSuccess } from '../../common/response';
import {
  forgotPasswordSchema,
  loginSchema,
  logoutSchema,
  refreshSchema,
  registerSchema,
  resetPasswordSchema,
} from './auth.schema';
import { authService } from './auth.service';

export const authRouter = Router();

authRouter.post('/register', authRateLimiter, validateBody(registerSchema), async (req, res, next) => {
  try {
    const result = await authService.register(req.body, {
      requestId: req.requestId,
      ipAddress: req.ip,
      userAgent: req.header('user-agent'),
    });
    sendSuccess(req, res, result, 201);
  } catch (err) {
    next(err);
  }
});

authRouter.post('/login', authRateLimiter, validateBody(loginSchema), async (req, res, next) => {
  try {
    const result = await authService.login(req.body, {
      requestId: req.requestId,
      ipAddress: req.ip,
      userAgent: req.header('user-agent'),
    });
    sendSuccess(req, res, result, 200);
  } catch (err) {
    next(err);
  }
});

authRouter.post('/refresh', authRateLimiter, validateBody(refreshSchema), async (req, res, next) => {
  try {
    const result = await authService.refresh(req.body.refreshToken, req.body.deviceName, {
      requestId: req.requestId,
      ipAddress: req.ip,
      userAgent: req.header('user-agent'),
    });
    sendSuccess(req, res, result, 200);
  } catch (err) {
    next(err);
  }
});

authRouter.post('/logout', requireAuth, validateBody(logoutSchema), async (req, res, next) => {
  try {
    await authService.logout(req.auth!.userId, req.body.refreshToken, {
      requestId: req.requestId,
      ipAddress: req.ip,
    });
    sendSuccess(req, res, { loggedOut: true });
  } catch (err) {
    next(err);
  }
});

authRouter.post('/logout-all', requireAuth, async (req, res, next) => {
  try {
    await authService.logoutAll(req.auth!.userId, {
      requestId: req.requestId,
      ipAddress: req.ip,
    });
    sendSuccess(req, res, { loggedOutAll: true });
  } catch (err) {
    next(err);
  }
});

authRouter.post(
  '/forgot-password',
  authRateLimiter,
  validateBody(forgotPasswordSchema),
  async (req, res, next) => {
    try {
      await authService.forgotPassword(req.body.email, {
        requestId: req.requestId,
        ipAddress: req.ip,
      });
      sendSuccess(
        req,
        res,
        { message: 'If the email is registered, password reset instructions have been queued.' },
        202,
      );
    } catch (err) {
      next(err);
    }
  },
);

authRouter.post(
  '/reset-password',
  authRateLimiter,
  validateBody(resetPasswordSchema),
  async (req, res, next) => {
    try {
      await authService.resetPassword(req.body.resetToken, req.body.newPassword, {
        requestId: req.requestId,
        ipAddress: req.ip,
      });
      sendSuccess(req, res, { reset: true });
    } catch (err) {
      next(err);
    }
  },
);

authRouter.get('/me', requireAuth, async (req, res, next) => {
  try {
    const data = await authService.getMe(req.auth!.userId);
    sendSuccess(req, res, data);
  } catch (err) {
    next(err);
  }
});
