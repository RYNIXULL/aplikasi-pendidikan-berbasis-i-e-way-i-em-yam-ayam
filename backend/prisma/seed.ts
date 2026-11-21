import 'dotenv/config';
import { PrismaClient, UserRole } from '@prisma/client';
import argon2 from 'argon2';

const prisma = new PrismaClient();

async function main() {
  // Strictly dummy accounts for local development testing only
  const demoPassword = process.env.SEED_DEMO_PASSWORD || 'EduAiDemoPass123!';
  const hash = await argon2.hash(demoPassword, { type: argon2.argon2id });

  const teacherEmail = 'budi.guru@example.com';
  const existingTeacher = await prisma.user.findFirst({ where: { email: teacherEmail, deletedAt: null } });
  if (!existingTeacher) {
    await prisma.user.create({
      data: {
        email: teacherEmail,
        passwordHash: hash,
        role: UserRole.TEACHER,
        profile: {
          create: {
            fullName: 'Budi Santoso',
            displayName: 'Pak Budi',
            institutionName: 'SMA Negeri 1 Contoh',
            subjectSpecialty: 'Biologi',
            preferredLocale: 'id',
          },
        },
      },
    });
  }

  const studentEmail = 'siti.siswa@example.com';
  const existingStudent = await prisma.user.findFirst({ where: { email: studentEmail, deletedAt: null } });
  if (!existingStudent) {
    await prisma.user.create({
      data: {
        email: studentEmail,
        passwordHash: hash,
        role: UserRole.STUDENT,
        profile: {
          create: {
            fullName: 'Siti Rahmawati',
            displayName: 'Siti R.',
            institutionName: 'SMA Negeri 1 Contoh',
            gradeLevel: 'Kelas XI IPA',
            preferredLocale: 'id',
          },
        },
      },
    });
  }

  console.log('Seed completed with dummy development users (budi.guru@example.com, siti.siswa@example.com).');
}

main()
  .catch((err) => {
    console.error('Seed failed:', err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
