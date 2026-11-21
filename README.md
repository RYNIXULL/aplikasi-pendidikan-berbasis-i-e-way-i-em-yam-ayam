# EduForge AI — AI-Powered Educational Learning Ecosystem

A production-oriented, modular educational learning platform built with **Flutter (Android)**, **Node.js + TypeScript + Express + Prisma**, **Python 3.12 + FastAPI**, **PostgreSQL 16 + pgvector**, **Redis + BullMQ**, and **S3-compatible private object storage**.

---

## Architecture & Documentation

All architecture, database, API, and decision records live under `docs/`:
- `docs/architecture.md` — 4-tier system architecture, security boundaries, workflows
- `docs/erd.md` — 24-table PostgreSQL + `pgvector` schema, indexes, cascades, RBAC rules
- `docs/api-contract.md` — `/api/v1` public REST contracts, `/internal/v1` HMAC AI contracts, structured JSON schemas
- `docs/implementation-roadmap.md` — Phases 0–8 execution plan, gap analysis, and acceptance criteria
- `docs/technical-decisions.md` — ADR-001 through ADR-014

---

## Repository Structure

```text
.
|-- docs/             # Architecture, ERD, API contracts, Roadmap, ADRs
|-- infra/            # Docker Compose (PostgreSQL+pgvector, Redis, MinIO, services)
|-- backend/          # Node.js + TypeScript + Express + Prisma + BullMQ workers
|-- ai-service/       # Private Python 3.12 + FastAPI + PyMuPDF/DOCX/PPTX + Gemini SDK
`-- mobile/           # Flutter + Dart Android app (Riverpod, GoRouter, Dio, SQLite)
```

---

## Quickstart (Local Development)

### 1. Environment Configuration
Never commit `.env` files. Copy templates and populate local credentials:
```powershell
Copy-Item .env.example .env
Copy-Item backend\.env.example backend\.env
Copy-Item ai-service\.env.example ai-service\.env
```
Configure `GEMINI_API_KEY` inside `ai-service/.env` for live Google Gemini calls.

### 2. Infrastructure (PostgreSQL + pgvector, Redis, MinIO)
Start Docker Desktop, then run:
```powershell
docker compose -f infra/docker-compose.yml --env-file .env up -d postgres redis minio minio-init
```

### 3. Node.js Application Backend
```powershell
cd backend
npm install
npx prisma migrate deploy
npx prisma db seed
npm run dev
# In a second terminal for async document & AI jobs:
npm run dev:worker
```

### 4. Python 3.12 AI Processing Service
```powershell
cd ai-service
uv sync --python 3.12 --extra dev
uv run uvicorn app.main:app --host 127.0.0.1 --port 8000
```

### 5. Flutter Android Application
```powershell
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

---

## Running Automated Test Suites

### Backend (Vitest + TypeScript strict check)
```powershell
cd backend
npm run typecheck
npm run build
npm test
```

### Python AI Service (Pytest + Extraction, Validation, PPTX Export, AI Evaluation)
```powershell
cd ai-service
uv run pytest -v
```

### Flutter Mobile App (Static Analyzer + Unit/Widget/Router/Game Tests)
```powershell
cd mobile
flutter analyze
flutter test
```
