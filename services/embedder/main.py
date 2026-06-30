from __future__ import annotations

import logging
import os
import time
from contextlib import asynccontextmanager
from typing import Any

import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("embedder")

MODEL_NAME: str = os.getenv("MODEL_NAME", "BAAI/bge-m3")
EMBEDDING_DIM: int = int(os.getenv("EMBEDDING_DIM", "768"))

# Global model state
_model: Any = None
_actual_dim: int = EMBEDDING_DIM
_load_time: float = 0.0


def load_model() -> Any:
    """Load sentence-transformers model, downloading if necessary."""
    from sentence_transformers import SentenceTransformer  # type: ignore

    logger.info("Loading model: %s — this may take a few minutes on first run", MODEL_NAME)
    t0 = time.monotonic()
    model = SentenceTransformer(MODEL_NAME)
    elapsed = time.monotonic() - t0

    # Detect actual embedding dimension
    sample = model.encode(["ping"])
    dim = int(np.array(sample).shape[1])
    logger.info("Model loaded in %.1fs — embedding dim=%d", elapsed, dim)
    return model, dim, elapsed


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _model, _actual_dim, _load_time
    _model, _actual_dim, _load_time = load_model()
    yield
    logger.info("Shutting down embedder")


app = FastAPI(
    title="RAG Embedder",
    description="Local sentence-transformer embedding service",
    version="1.0.0",
    lifespan=lifespan,
)


# ---------- schemas ----------

class EmbedRequest(BaseModel):
    texts: list[str] = Field(..., min_length=1, description="Texts to embed")
    normalize: bool = Field(True, description="L2-normalize embeddings (recommended for cosine similarity)")
    batch_size: int = Field(32, ge=1, le=256, description="Encoding batch size")


class EmbedResponse(BaseModel):
    embeddings: list[list[float]]
    model: str
    dim: int
    count: int


class HealthResponse(BaseModel):
    model: str
    status: str
    dim: int
    load_time_seconds: float


# ---------- endpoints ----------

@app.post("/embed", response_model=EmbedResponse)
async def embed(req: EmbedRequest) -> EmbedResponse:
    if _model is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet")

    if not req.texts:
        raise HTTPException(status_code=422, detail="texts list is empty")

    try:
        vectors = _model.encode(
            req.texts,
            batch_size=req.batch_size,
            normalize_embeddings=req.normalize,
            show_progress_bar=False,
        )
        embeddings: list[list[float]] = np.array(vectors).tolist()
    except Exception as exc:
        logger.exception("Encoding failed")
        raise HTTPException(status_code=500, detail=f"Encoding error: {exc}") from exc

    return EmbedResponse(
        embeddings=embeddings,
        model=MODEL_NAME,
        dim=_actual_dim,
        count=len(embeddings),
    )


@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    if _model is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet")
    return HealthResponse(
        model=MODEL_NAME,
        status="ok",
        dim=_actual_dim,
        load_time_seconds=round(_load_time, 2),
    )
