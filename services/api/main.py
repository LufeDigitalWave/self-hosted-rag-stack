from __future__ import annotations

import hashlib
import json
import logging
import os
from contextlib import asynccontextmanager
from typing import Any

import httpx
import redis.asyncio as aioredis
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from db import (
    close_db,
    delete_document,
    get_pool,
    init_db,
    insert_chunk,
    insert_document,
    similarity_search,
)

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "info").upper(),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("api")

EMBEDDER_URL: str = os.getenv("EMBEDDER_URL", "http://embedder:8001")
REDIS_URL: str = os.getenv("REDIS_URL", "redis://redis:6379")
CACHE_TTL: int = int(os.getenv("CACHE_TTL_SECONDS", "300"))
CHUNK_SIZE: int = int(os.getenv("CHUNK_SIZE", "512"))
CHUNK_OVERLAP: int = int(os.getenv("CHUNK_OVERLAP", "50"))

_redis: aioredis.Redis | None = None
_http: httpx.AsyncClient | None = None


# ---------- lifespan ----------

@asynccontextmanager
async def lifespan(app: FastAPI):
    global _redis, _http

    await init_db()

    _redis = aioredis.from_url(REDIS_URL, encoding="utf-8", decode_responses=True)
    _http = httpx.AsyncClient(base_url=EMBEDDER_URL, timeout=60.0)
    logger.info("RAG API ready — embedder=%s, redis=%s", EMBEDDER_URL, REDIS_URL)

    yield

    await close_db()
    if _redis:
        await _redis.aclose()
    if _http:
        await _http.aclose()


app = FastAPI(
    title="Self-Hosted RAG API",
    description="Ingest documents, embed with local models, query with pgvector",
    version="1.0.0",
    lifespan=lifespan,
)


# ---------- helpers ----------

def chunk_text(text: str, size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> list[str]:
    """Split text into overlapping character-level chunks."""
    if not text.strip():
        return []
    chunks: list[str] = []
    start = 0
    while start < len(text):
        end = start + size
        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)
        start += size - overlap
    return chunks


async def embed(texts: list[str]) -> list[list[float]]:
    if _http is None:
        raise HTTPException(status_code=503, detail="HTTP client not ready")
    try:
        resp = await _http.post("/embed", json={"texts": texts})
        resp.raise_for_status()
    except httpx.HTTPError as exc:
        logger.exception("Embedder call failed")
        raise HTTPException(status_code=502, detail=f"Embedder error: {exc}") from exc
    return resp.json()["embeddings"]


def cache_key(question: str, top_k: int, threshold: float) -> str:
    raw = f"{question}|{top_k}|{threshold}"
    return "rag:query:" + hashlib.sha256(raw.encode()).hexdigest()


# ---------- schemas ----------

class IngestTextRequest(BaseModel):
    text: str = Field(..., min_length=1)
    source: str = Field("unknown")
    metadata: dict[str, Any] = Field(default_factory=dict)


class IngestResponse(BaseModel):
    doc_id: str
    chunks_created: int
    source: str


class QueryRequest(BaseModel):
    question: str = Field(..., min_length=1)
    top_k: int = Field(5, ge=1, le=50)
    threshold: float = Field(0.7, ge=0.0, le=1.0)


class QueryResult(BaseModel):
    chunk_id: str
    content: str
    source: str
    score: float
    metadata: dict[str, Any]
    doc_id: str


class QueryResponse(BaseModel):
    results: list[QueryResult]
    cached: bool
    question: str


class HealthResponse(BaseModel):
    status: str
    embedder: str
    cache: str


# ---------- endpoints ----------

@app.post("/ingest", response_model=IngestResponse, status_code=201)
async def ingest_text(req: IngestTextRequest) -> IngestResponse:
    """Ingest plain text: chunk -> embed -> store in pgvector."""
    pool = await get_pool()

    chunks = chunk_text(req.text, CHUNK_SIZE, CHUNK_OVERLAP)
    if not chunks:
        raise HTTPException(status_code=422, detail="Text produced no usable chunks")

    doc_id = await insert_document(pool, req.source, req.metadata)

    embeddings = await embed(chunks)
    for content, embedding in zip(chunks, embeddings):
        await insert_chunk(pool, doc_id, content, embedding)

    logger.info("Ingested doc_id=%s source=%s chunks=%d", doc_id, req.source, len(chunks))
    return IngestResponse(doc_id=doc_id, chunks_created=len(chunks), source=req.source)


@app.post("/ingest/file", response_model=IngestResponse, status_code=201)
async def ingest_file(
    file: UploadFile = File(...),
    source: str = Form(""),
    metadata: str = Form("{}"),
) -> IngestResponse:
    """Ingest a plain-text file (UTF-8). For PDFs use scripts/ingest_pdf.py."""
    raw = await file.read()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise HTTPException(status_code=422, detail="File must be UTF-8 encoded text")

    try:
        meta: dict[str, Any] = json.loads(metadata)
    except json.JSONDecodeError:
        meta = {}

    src = source or file.filename or "upload"
    req = IngestTextRequest(text=text, source=src, metadata=meta)
    return await ingest_text(req)


@app.post("/query", response_model=QueryResponse)
async def query(req: QueryRequest) -> QueryResponse:
    """Embed question, search pgvector, return top-K chunks (with Redis cache)."""
    key = cache_key(req.question, req.top_k, req.threshold)

    # Check cache
    if _redis:
        cached_raw = await _redis.get(key)
        if cached_raw:
            results = json.loads(cached_raw)
            return QueryResponse(results=results, cached=True, question=req.question)

    # Embed question
    q_embeddings = await embed([req.question])
    q_vec = q_embeddings[0]

    pool = await get_pool()
    rows = await similarity_search(pool, q_vec, req.top_k, req.threshold)

    results = [
        QueryResult(
            chunk_id=r["chunk_id"],
            content=r["content"],
            source=r["source"],
            score=round(float(r["score"]), 4),
            metadata=r["metadata"] or {},
            doc_id=r["doc_id"],
        )
        for r in rows
    ]

    # Store in cache
    if _redis:
        payload = [r.model_dump() for r in results]
        await _redis.setex(key, CACHE_TTL, json.dumps(payload))

    return QueryResponse(results=results, cached=False, question=req.question)


@app.delete("/documents/{doc_id}", status_code=200)
async def remove_document(doc_id: str) -> dict[str, str]:
    """Delete a document and all its chunks (CASCADE)."""
    pool = await get_pool()
    deleted = await delete_document(pool, doc_id)
    if not deleted:
        raise HTTPException(status_code=404, detail=f"Document {doc_id} not found")

    # Invalidate cache entries — broad flush with prefix pattern
    if _redis:
        async for k in _redis.scan_iter("rag:query:*"):
            await _redis.delete(k)

    return {"deleted": doc_id}


@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    embedder_status = "unreachable"
    if _http:
        try:
            r = await _http.get("/health", timeout=5.0)
            embedder_status = "ok" if r.status_code == 200 else f"http_{r.status_code}"
        except Exception:
            pass

    cache_status = "unreachable"
    if _redis:
        try:
            await _redis.ping()
            cache_status = "ok"
        except Exception:
            pass

    return HealthResponse(
        status="ok",
        embedder=embedder_status,
        cache=cache_status,
    )
