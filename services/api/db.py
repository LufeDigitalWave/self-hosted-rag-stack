from __future__ import annotations

import logging
import os
from typing import Any

import asyncpg

logger = logging.getLogger("api.db")

POSTGRES_USER = os.getenv("POSTGRES_USER", "rag")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "CHANGE_ME")
POSTGRES_DB = os.getenv("POSTGRES_DB", "rag_db")
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "postgres")
POSTGRES_PORT = int(os.getenv("POSTGRES_PORT", "5432"))
EMBEDDING_DIM = int(os.getenv("EMBEDDING_DIM", "768"))

DSN = (
    f"postgresql://{POSTGRES_USER}:{POSTGRES_PASSWORD}"
    f"@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}"
)

_pool: asyncpg.Pool | None = None


async def get_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        raise RuntimeError("DB pool not initialised — call init_db() first")
    return _pool


async def init_db() -> None:
    global _pool
    logger.info("Connecting to PostgreSQL at %s:%d/%s", POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB)
    _pool = await asyncpg.create_pool(DSN, min_size=2, max_size=10)
    await create_tables()
    logger.info("DB pool ready")


async def close_db() -> None:
    global _pool
    if _pool:
        await _pool.close()
        _pool = None


async def create_tables() -> None:
    pool = await get_pool()
    async with pool.acquire() as conn:
        await conn.execute("CREATE EXTENSION IF NOT EXISTS vector;")
        await conn.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";")

        await conn.execute(
            """
            CREATE TABLE IF NOT EXISTS documents (
                id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                source      TEXT NOT NULL,
                metadata    JSONB NOT NULL DEFAULT '{}',
                created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
            );
            """
        )

        await conn.execute(
            f"""
            CREATE TABLE IF NOT EXISTS chunks (
                id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                doc_id      UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
                content     TEXT NOT NULL,
                embedding   vector({EMBEDDING_DIM}),
                created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
            );
            """
        )

        # IVFFlat index for approximate nearest-neighbour search
        # lists=100 is a safe default; increase for datasets >1M rows
        await conn.execute(
            """
            CREATE INDEX IF NOT EXISTS chunks_embedding_idx
            ON chunks
            USING ivfflat (embedding vector_cosine_ops)
            WITH (lists = 100);
            """
        )

        await conn.execute(
            """
            CREATE INDEX IF NOT EXISTS chunks_doc_id_idx ON chunks (doc_id);
            """
        )

    logger.info(
        "Tables ready — documents, chunks (vector dim=%d, ivfflat index)", EMBEDDING_DIM
    )


async def insert_document(
    pool: asyncpg.Pool,
    source: str,
    metadata: dict[str, Any],
) -> str:
    row = await pool.fetchrow(
        "INSERT INTO documents (source, metadata) VALUES ($1, $2) RETURNING id::text",
        source,
        metadata,
    )
    return row["id"]


async def insert_chunk(
    pool: asyncpg.Pool,
    doc_id: str,
    content: str,
    embedding: list[float],
) -> str:
    vector_literal = "[" + ",".join(str(v) for v in embedding) + "]"
    row = await pool.fetchrow(
        """
        INSERT INTO chunks (doc_id, content, embedding)
        VALUES ($1::uuid, $2, $3::vector)
        RETURNING id::text
        """,
        doc_id,
        content,
        vector_literal,
    )
    return row["id"]


async def similarity_search(
    pool: asyncpg.Pool,
    embedding: list[float],
    top_k: int = 5,
    threshold: float = 0.7,
) -> list[dict[str, Any]]:
    vector_literal = "[" + ",".join(str(v) for v in embedding) + "]"
    rows = await pool.fetch(
        """
        SELECT
            c.id::text        AS chunk_id,
            c.content,
            c.doc_id::text    AS doc_id,
            d.source,
            d.metadata,
            1 - (c.embedding <=> $1::vector) AS score
        FROM chunks c
        JOIN documents d ON d.id = c.doc_id
        WHERE 1 - (c.embedding <=> $1::vector) >= $2
        ORDER BY c.embedding <=> $1::vector
        LIMIT $3;
        """,
        vector_literal,
        threshold,
        top_k,
    )
    return [dict(r) for r in rows]


async def delete_document(pool: asyncpg.Pool, doc_id: str) -> bool:
    result = await pool.execute(
        "DELETE FROM documents WHERE id = $1::uuid", doc_id
    )
    # result is like "DELETE N"
    return result.split()[-1] != "0"
