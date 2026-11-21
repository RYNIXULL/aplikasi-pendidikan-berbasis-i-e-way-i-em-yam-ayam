import logging
from fastapi import FastAPI
from app.api.routes import router as internal_router

logging.basicConfig(
    level=logging.INFO,
    format='{"time":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","msg":"%(message)s"}',
)

app = FastAPI(
    title="EduAI Processing Service (Internal)",
    version="1.0.0",
    docs_url=None,
    redoc_url=None,
)

app.include_router(internal_router)
