# Self-Hosted RAG Stack

[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.111-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![pgvector](https://img.shields.io/badge/pgvector-PostgreSQL%2016-336791?logo=postgresql&logoColor=white)](https://github.com/pgvector/pgvector)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A production-ready Retrieval-Augmented Generation stack that runs entirely on your own infrastructure. No cloud embedding API, no per-token costs, no data leaving your server.

---

## Why self-hosted?

| Concern | Cloud embeddings | This stack |
|---|---|---|
| Data privacy | Docs sent to third-party API | Stay on your server |
| Cost | Pay per million tokens | Free after hardware |
| Offline capability | Requires internet | Works air-gapped |
| Latency | Network round-trip | Sub-millisecond local |
| Model lock-in | Provider decides | Swap any HuggingFace model |

---

## Architecture

```
                          ┌─────────────────────────────────────────────────────┐
  INGEST                  │                   rag-net (Docker bridge)           │
  ──────                  │                                                     │
  PDF / Text              │  ┌─────────────┐    ┌──────────────┐               │
       │                  │  │   FastAPI   │    │  Embedder    │               │
       ▼                  │  │  RAG API    │───▶│  (BGE-M3 /   │               │
  Chunker (512 chars,     │  │  :8000      │◀───│   MiniLM)    │               │
  50 char overlap)        │  └──────┬──────┘    │  :8001       │               │
       │                  │         │            └──────────────┘               │
       ▼                  │         │                                           │
  Embedder → vector       │  ┌──────▼──────┐    ┌──────────────┐               │
       │                  │  │ PostgreSQL  │    │    Redis     │               │
       ▼                  │  │  + pgvector │    │  (cache)     │               │
  pgvector store          │  │  :5432      │    │  :6379       │               │
                          │  └─────────────┘    └──────────────┘               │
  QUERY                   └─────────────────────────────────────────────────────┘
  ─────
  Question
       │
       ▼
  Embedder → question vector
       │
       ▼
  Cosine similarity search (IVFFlat index)
       │
       ▼
  Top-K chunks → LLM → Answer
```

---

## Services

| Service | Image / Build | Port | Role |
|---|---|---|---|
| `postgres` | `pgvector/pgvector:pg16` | 5432 | Vector store — documents + chunks with cosine-similarity index |
| `embedder` | `./services/embedder` | 8001 | Loads a sentence-transformer model locally; exposes `/embed` |
| `api` | `./services/api` | 8000 | Ingest, chunk, query — the main application surface |
| `redis` | `redis:7-alpine` | 6379 | Query-result cache (TTL-based, evicts LRU on memory pressure) |

---

## Quick Start

```bash
# 1. Clone and configure
git clone https://github.com/LufeDigitalWave/self-hosted-rag-stack.git
cd self-hosted-rag-stack
cp .env.example .env
# Edit .env — at minimum set POSTGRES_PASSWORD

# 2. Start the stack
docker compose up -d

# 3. Wait for the embedder to download and load the model (~2 min on first run)
docker compose logs -f embedder
# Look for: "Model loaded in X.Xs — embedding dim=768"

# 4. Ingest a PDF
pip install pypdf httpx rich          # script deps (one-time)
python scripts/ingest_pdf.py --file your_doc.pdf

# 5. Query
curl -s -X POST http://localhost:8000/query \
     -H "Content-Type: application/json" \
     -d '{"question": "What is the main topic?", "top_k": 5}' \
     | python -m json.tool
```

Check the API is healthy:

```bash
curl http://localhost:8000/health
# {"status":"ok","embedder":"ok","cache":"ok"}
```

---

## Embedding Model Options

Change `MODEL_NAME` and `EMBEDDING_DIM` in `.env` to switch models without rebuilding.

| Model | Size | Dim | Notes |
|---|---|---|---|
| `BAAI/bge-m3` | 1.1 GB | 768 | Best quality, multilingual, recommended default |
| `all-MiniLM-L6-v2` | 90 MB | 384 | Fast startup, English-only, good for dev/testing |
| `paraphrase-multilingual-mpnet-base-v2` | 1.0 GB | 768 | Strong multilingual alternative |

> When switching models, **wipe and recreate the database** — vectors from different models are not comparable.
> ```bash
> docker compose down -v   # drops volumes
> docker compose up -d
> ```

---

## API Reference

### `POST /ingest` — Ingest plain text

```bash
curl -X POST http://localhost:8000/ingest \
     -H "Content-Type: application/json" \
     -d '{
       "text": "FastAPI is a modern web framework for building APIs with Python 3.8+...",
       "source": "fastapi-docs",
       "metadata": {"category": "framework", "lang": "en"}
     }'
```

Response:

```json
{
  "doc_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "chunks_created": 4,
  "source": "fastapi-docs"
}
```

### `POST /ingest/file` — Ingest a text file via multipart

```bash
curl -X POST http://localhost:8000/ingest/file \
     -F "file=@notes.txt" \
     -F "source=my-notes"
```

### `POST /query` — Semantic search

```bash
curl -X POST http://localhost:8000/query \
     -H "Content-Type: application/json" \
     -d '{
       "question": "How does dependency injection work?",
       "top_k": 5,
       "threshold": 0.7
     }'
```

Response:

```json
{
  "question": "How does dependency injection work?",
  "cached": false,
  "results": [
    {
      "chunk_id": "...",
      "content": "FastAPI uses a Depends() function...",
      "source": "fastapi-docs",
      "score": 0.923,
      "metadata": {"category": "framework"},
      "doc_id": "..."
    }
  ]
}
```

| Query param | Default | Description |
|---|---|---|
| `top_k` | 5 | Max results to return |
| `threshold` | 0.7 | Minimum cosine similarity score (0–1) |

### `DELETE /documents/{doc_id}` — Remove document

```bash
curl -X DELETE http://localhost:8000/documents/3fa85f64-...
```

Deletes the document and all its chunks (CASCADE). Cache is flushed automatically.

---

## Ingest PDF from the command line

```bash
python scripts/ingest_pdf.py \
    --file contracts/agreement.pdf \
    --source "contract-2024" \
    --metadata '{"department": "legal"}' \
    --api-url http://localhost:8000
```

Dependencies (not in the Docker image — install once in your local env):

```bash
pip install pypdf httpx rich
```

---

## Scaling & Customisation

**Multiple embedder replicas** — Add a load balancer (e.g. Traefik or nginx) in front of the `embedder` service and run `docker compose up --scale embedder=2`. The API service is stateless and scales horizontally.

**Swap pgvector for Qdrant** — Replace the `postgres` service with `qdrant/qdrant` and update `db.py` to use the Qdrant Python client. The chunking and embedder services are unchanged.

**Add a reranking step** — After the initial cosine retrieval, pass the top-K chunks through a cross-encoder reranker (e.g. `cross-encoder/ms-marco-MiniLM-L-6-v2`) for higher-precision results.

**LLM answer synthesis** — Set `OPENAI_API_KEY` in `.env` and call the OpenAI API (or a local Ollama instance) with the retrieved chunks as context. The API returns raw chunks; the generation step is intentionally kept outside the core service so you can wire any LLM.

**IVFFlat tuning** — The default `lists=100` works well up to ~500k chunks. For larger datasets, increase to `lists=200` or consider the HNSW index (`CREATE INDEX USING hnsw (embedding vector_cosine_ops)`).

---

## Project Structure

```
self-hosted-rag-stack/
├── docker-compose.yml          # Full stack definition
├── .env.example                # Copy to .env and fill in secrets
├── services/
│   ├── embedder/
│   │   ├── main.py             # POST /embed, GET /health
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   └── api/
│       ├── main.py             # POST /ingest, POST /query, DELETE /documents
│       ├── db.py               # asyncpg pool, pgvector table setup, queries
│       ├── requirements.txt
│       └── Dockerfile
└── scripts/
    └── ingest_pdf.py           # CLI: PDF → /ingest
```

---

## License

MIT — see [LICENSE](LICENSE).
