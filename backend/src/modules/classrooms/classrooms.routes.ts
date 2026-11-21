import { Router } from 'express';
import { z } from 'zod';
import {
  ClassroomStatus,
  ContentStatus,
  MemberStatus,
  UserRole,
} from '@prisma/client';
import { prisma } from '../../config/prisma';
import { AppError } from '../../common/errors';
import { requireAuth, requireRole } from '../../common/middleware/auth';
import { validateBody } from '../../common/middleware/validate';
import { sendSuccess } from '../../common/response';
import { generateClassroomJoinCode } from '../../common/security/crypto';
import { recordAuditLog } from '../../common/services/audit';

const createClassroomSchema = z.object({
  name: z.string().trim().min(2).max(150),
  subject: z.string().trim().min(2).max(100),
  gradeLevel: z.string().trim().max(60).optional(),
  description: z.string().trim().max(1000).optional(),
});

const updateClassroomSchema = z.object({
  name: z.string().trim().min(2).max(150).optional(),
  subject: z.string().trim().min(2).max(100).optional(),
  gradeLevel: z.string().trim().max(60).nullable().optional(),
  description: z.string().trim().max(1000).nullable().optional(),
  joinCodeEnabled: z.boolean().optional(),
});

const joinClassroomSchema = z.object({
  joinCode: z.string().trim().toUpperCase().min(6).max(12),
});

const publishMaterialSchema = z.object({
  contentId: z.string().uuid(),
  title: z.string().trim().min(2).max(255).optional(),
  description: z.string().trim().max(1000).optional(),
  displayOrder: z.number().int().min(0).default(0),
});

const updateMaterialSchema = z.object({
  title: z.string().trim().min(2).max(255).optional(),
  description: z.string().trim().max(1000).nullable().optional(),
  displayOrder: z.number().int().min(0).optional(),
  isVisible: z.boolean().optional(),
  syncLatestApprovedVersion: z.boolean().optional(),
});

async function createUniqueJoinCode(): Promise<string> {
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = generateClassroomJoinCode(8);
    const exists = await prisma.classroom.findFirst({
      where: { joinCode: code, deletedAt: null },
      select: { id: true },
    });
    if (!exists) return code;
  }
  throw new AppError(500, 'INTERNAL_ERROR', 'Unable to allocate a unique classroom code.');
}

async function assertClassroomAccess(classroomId: string, userId: string, role: UserRole) {
  const classroom = await prisma.classroom.findFirst({
    where: { id: classroomId, deletedAt: null },
  });
  if (!classroom) {
    throw new AppError(404, 'NOT_FOUND', 'Classroom not found.');
  }
  if (role === UserRole.TEACHER) {
    if (classroom.teacherId !== userId) {
      throw new AppError(403, 'FORBIDDEN', 'You do not own this classroom.');
    }
    return classroom;
  }
  if (role === UserRole.STUDENT) {
    const member = await prisma.classroomMember.findFirst({
      where: { classroomId, studentId: userId, status: MemberStatus.ACTIVE },
    });
    if (!member) {
      throw new AppError(403, 'FORBIDDEN', 'You are not enrolled in this classroom.');
    }
    return classroom;
  }
  return classroom;
}

export const classroomsRouter = Router();
classroomsRouter.use(requireAuth);

classroomsRouter.post(
  '/',
  requireRole(UserRole.TEACHER),
  validateBody(createClassroomSchema),
  async (req, res, next) => {
    try {
      const joinCode = await createUniqueJoinCode();
      const classroom = await prisma.classroom.create({
        data: {
          teacherId: req.auth!.userId,
          name: req.body.name,
          subject: req.body.subject,
          gradeLevel: req.body.gradeLevel,
          description: req.body.description,
          joinCode,
        },
      });
      await recordAuditLog({
        actorUserId: req.auth!.userId,
        action: 'CLASSROOM_CREATED',
        entityType: 'CLASSROOM',
        entityId: classroom.id,
        requestId: req.requestId,
      });
      sendSuccess(req, res, classroom, 201);
    } catch (err) {
      next(err);
    }
  },
);

classroomsRouter.post(
  '/join',
  requireRole(UserRole.STUDENT),
  validateBody(joinClassroomSchema),
  async (req, res, next) => {
    try {
      const classroom = await prisma.classroom.findFirst({
        where: {
          joinCode: req.body.joinCode,
          status: ClassroomStatus.ACTIVE,
          joinCodeEnabled: true,
          deletedAt: null,
        },
      });
      if (!classroom) {
        throw new AppError(404, 'CLASSROOM_CODE_INVALID', 'Classroom code is invalid or closed.');
      }

      const existing = await prisma.classroomMember.findUnique({
        where: {
          classroomId_studentId: {
            classroomId: classroom.id,
            studentId: req.auth!.userId,
          },
        },
      });

      if (existing && existing.status === MemberStatus.ACTIVE) {
        throw new AppError(409, 'CONFLICT', 'You are already enrolled in this classroom.');
      }

      const membership = existing
        ? await prisma.classroomMember.update({
            where: { id: existing.id },
            data: { status: MemberStatus.ACTIVE, removedAt: null, joinedAt: new Date() },
          })
        : await prisma.classroomMember.create({
            data: {
              classroomId: classroom.id,
              studentId: req.auth!.userId,
              status: MemberStatus.ACTIVE,
            },
          });

      sendSuccess(req, res, { classroom, membership }, 201);
    } catch (err) {
      next(err);
    }
  },
);

classroomsRouter.get('/', async (req, res, next) => {
  try {
    const { userId, role } = req.auth!;
    if (role === UserRole.TEACHER) {
      const classes = await prisma.classroom.findMany({
        where: { teacherId: userId, deletedAt: null },
        include: {
          _count: {
            select: {
              members: { where: { status: MemberStatus.ACTIVE } },
              materials: true,
              assessments: { where: { deletedAt: null } },
            },
          },
        },
        orderBy: { createdAt: 'desc' },
      });
      sendSuccess(req, res, classes);
      return;
    }

    const memberships = await prisma.classroomMember.findMany({
      where: {
        studentId: userId,
        status: MemberStatus.ACTIVE,
        classroom: { deletedAt: null, status: ClassroomStatus.ACTIVE },
      },
      include: {
        classroom: {
          include: {
            teacher: { select: { id: true, profile: { select: { fullName: true, displayName: true } } } },
            _count: {
              select: {
                materials: { where: { isVisible: true } },
                assessments: { where: { deletedAt: null } },
              },
            },
          },
        },
      },
      orderBy: { joinedAt: 'desc' },
    });

    sendSuccess(
      req,
      res,
      memberships.map((m) => ({
        ...m.classroom,
        joinedAt: m.joinedAt,
      })),
    );
  } catch (err) {
    next(err);
  }
});

classroomsRouter.get('/:id', async (req, res, next) => {
  try {
    const classroom = await assertClassroomAccess(req.params.id, req.auth!.userId, req.auth!.role);
    sendSuccess(req, res, classroom);
  } catch (err) {
    next(err);
  }
});

classroomsRouter.patch(
  '/:id',
  requireRole(UserRole.TEACHER),
  validateBody(updateClassroomSchema),
  async (req, res, next) => {
    try {
      await assertClassroomAccess(req.params.id, req.auth!.userId, UserRole.TEACHER);
      const updated = await prisma.classroom.update({
        where: { id: req.params.id },
        data: req.body,
      });
      sendSuccess(req, res, updated);
    } catch (err) {
      next(err);
    }
  },
);

classroomsRouter.post('/:id/archive', requireRole(UserRole.TEACHER), async (req, res, next) => {
  try {
    await assertClassroomAccess(req.params.id, req.auth!.userId, UserRole.TEACHER);
    const archived = await prisma.classroom.update({
      where: { id: req.params.id },
      data: { status: ClassroomStatus.ARCHIVED, joinCodeEnabled: false },
    });
    sendSuccess(req, res, archived);
  } catch (err) {
    next(err);
  }
});

classroomsRouter.post(
  '/:id/regenerate-code',
  requireRole(UserRole.TEACHER),
  async (req, res, next) => {
    try {
      await assertClassroomAccess(req.params.id, req.auth!.userId, UserRole.TEACHER);
      const joinCode = await createUniqueJoinCode();
      const updated = await prisma.classroom.update({
        where: { id: req.params.id },
        data: { joinCode },
      });
      sendSuccess(req, res, { id: updated.id, joinCode: updated.joinCode });
    } catch (err) {
      next(err);
    }
  },
);

classroomsRouter.get('/:id/members', requireRole(UserRole.TEACHER), async (req, res, next) => {
  try {
    await assertClassroomAccess(req.params.id, req.auth!.userId, UserRole.TEACHER);
    const members = await prisma.classroomMember.findMany({
      where: { classroomId: req.params.id, status: MemberStatus.ACTIVE },
      include: {
        student: {
          select: {
            id: true,
            email: true,
            profile: { select: { fullName: true, displayName: true, gradeLevel: true } },
          },
        },
      },
      orderBy: { joinedAt: 'asc' },
    });
    sendSuccess(req, res, members);
  } catch (err) {
    next(err);
  }
});

classroomsRouter.delete(
  '/:id/members/:studentId',
  requireRole(UserRole.TEACHER),
  async (req, res, next) => {
    try {
      await assertClassroomAccess(req.params.id, req.auth!.userId, UserRole.TEACHER);
      await prisma.classroomMember.updateMany({
        where: {
          classroomId: req.params.id,
          studentId: req.params.studentId,
          status: MemberStatus.ACTIVE,
        },
        data: { status: MemberStatus.REMOVED, removedAt: new Date() },
      });
      sendSuccess(req, res, { removed: true });
    } catch (err) {
      next(err);
    }
  },
);

classroomsRouter.post(
  '/:id/materials',
  requireRole(UserRole.TEACHER),
  validateBody(publishMaterialSchema),
  async (req, res, next) => {
    try {
      const teacherId = req.auth!.userId;
      await assertClassroomAccess(req.params.id, teacherId, UserRole.TEACHER);

      const content = await prisma.generatedContent.findFirst({
        where: { id: req.body.contentId, teacherId, deletedAt: null },
      });
      if (!content) {
        throw new AppError(404, 'NOT_FOUND', 'Generated content not found.');
      }

      // Mandatory teacher approval gate before publishing
      if (
        (content.status !== ContentStatus.APPROVED && content.status !== ContentStatus.PUBLISHED) ||
        !content.approvedVersionId
      ) {
        throw new AppError(
          400,
          'CONTENT_NOT_APPROVED',
          'Content must be explicitly reviewed and approved by the teacher before publishing.',
        );
      }

      const material = await prisma.$transaction(async (tx) => {
        const created = await tx.classroomMaterial.upsert({
          where: {
            classroomId_contentId: {
              classroomId: req.params.id,
              contentId: content.id,
            },
          },
          update: {
            publishedVersionId: content.approvedVersionId!,
            title: req.body.title ?? content.title,
            description: req.body.description,
            displayOrder: req.body.displayOrder,
            isVisible: true,
          },
          create: {
            classroomId: req.params.id,
            contentId: content.id,
            publishedVersionId: content.approvedVersionId!,
            publishedBy: teacherId,
            title: req.body.title ?? content.title,
            description: req.body.description,
            displayOrder: req.body.displayOrder,
          },
        });

        await tx.generatedContent.update({
          where: { id: content.id },
          data: { status: ContentStatus.PUBLISHED },
        });

        return created;
      });

      await recordAuditLog({
        actorUserId: teacherId,
        action: 'CONTENT_PUBLISHED',
        entityType: 'CLASSROOM_MATERIAL',
        entityId: material.id,
        requestId: req.requestId,
        metadata: { classroomId: req.params.id, contentId: content.id },
      });

      sendSuccess(req, res, material, 201);
    } catch (err) {
      next(err);
    }
  },
);

classroomsRouter.get('/:id/materials', async (req, res, next) => {
  try {
    await assertClassroomAccess(req.params.id, req.auth!.userId, req.auth!.role);
    const materials = await prisma.classroomMaterial.findMany({
      where: {
        classroomId: req.params.id,
        ...(req.auth!.role === UserRole.STUDENT ? { isVisible: true } : {}),
      },
      include: {
        content: { select: { contentType: true, gameType: true, subject: true, documentId: true } },
      },
      orderBy: [{ displayOrder: 'asc' }, { publishedAt: 'desc' }],
    });
    sendSuccess(req, res, materials);
  } catch (err) {
    next(err);
  }
});

classroomsRouter.get('/:id/materials/:materialId', async (req, res, next) => {
  try {
    await assertClassroomAccess(req.params.id, req.auth!.userId, req.auth!.role);
    const material = await prisma.classroomMaterial.findFirst({
      where: {
        id: req.params.materialId,
        classroomId: req.params.id,
        ...(req.auth!.role === UserRole.STUDENT ? { isVisible: true } : {}),
      },
      include: {
        content: { select: { contentType: true, gameType: true, subject: true, exportStorageKey: true } },
        publishedVersion: true,
      },
    });
    if (!material) {
      throw new AppError(404, 'NOT_FOUND', 'Classroom material not found.');
    }
    sendSuccess(req, res, material);
  } catch (err) {
    next(err);
  }
});

classroomsRouter.patch(
  '/:id/materials/:materialId',
  requireRole(UserRole.TEACHER),
  validateBody(updateMaterialSchema),
  async (req, res, next) => {
    try {
      await assertClassroomAccess(req.params.id, req.auth!.userId, UserRole.TEACHER);
      const existing = await prisma.classroomMaterial.findFirst({
        where: { id: req.params.materialId, classroomId: req.params.id },
        include: { content: true },
      });
      if (!existing) {
        throw new AppError(404, 'NOT_FOUND', 'Classroom material not found.');
      }

      const updated = await prisma.classroomMaterial.update({
        where: { id: existing.id },
        data: {
          title: req.body.title,
          description: req.body.description,
          displayOrder: req.body.displayOrder,
          isVisible: req.body.isVisible,
          ...(req.body.syncLatestApprovedVersion && existing.content.approvedVersionId
            ? { publishedVersionId: existing.content.approvedVersionId }
            : {}),
        },
      });
      sendSuccess(req, res, updated);
    } catch (err) {
      next(err);
    }
  },
);

classroomsRouter.delete(
  '/:id/materials/:materialId',
  requireRole(UserRole.TEACHER),
  async (req, res, next) => {
    try {
      await assertClassroomAccess(req.params.id, req.auth!.userId, UserRole.TEACHER);
      await prisma.classroomMaterial.deleteMany({
        where: { id: req.params.materialId, classroomId: req.params.id },
      });
      sendSuccess(req, res, { unpublished: true });
    } catch (err) {
      next(err);
    }
  },
);
