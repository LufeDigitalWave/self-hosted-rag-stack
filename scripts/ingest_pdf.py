#!/usr/bin/env python3
"""
ingest_pdf.py — Send a PDF file to the self-hosted RAG API for ingestion.

Usage:
    python ingest_pdf.py --file path/to/doc.pdf --api-url http://localhost:8000

Requirements (install separately, not in services/api):
    pip install pypdf httpx rich

The script reads the PDF with pypdf, extracts text page by page, and sends
a single /ingest request to the RAG API.  The API handles chunking and
embedding internally.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    import httpx
    from pypdf import PdfReader
    from rich.console import Console
    from rich.progress import Progress, SpinnerColumn, TextColumn
except ImportError as exc:
    print(f"Missing dependency: {exc}")
    print("Install with: pip install pypdf httpx rich")
    sys.exit(1)

console = Console()


def extract_text(pdf_path: Path) -> tuple[str, int]:
    """Return (full_text, page_count) from a PDF file."""
    reader = PdfReader(str(pdf_path))
    pages: list[str] = []
    for page in reader.pages:
        text = page.extract_text() or ""
        pages.append(text.strip())
    return "\n\n".join(p for p in pages if p), len(reader.pages)


def ingest(
    pdf_path: Path,
    api_url: str,
    source: str | None,
    metadata: dict,
    timeout: float = 120.0,
) -> dict:
    api_url = api_url.rstrip("/")
    src = source or pdf_path.name

    with Progress(
        SpinnerColumn(),
        TextColumn("[bold cyan]{task.description}"),
        console=console,
    ) as progress:
        task = progress.add_task("Extracting text from PDF...", total=None)
        text, n_pages = extract_text(pdf_path)
        progress.update(task, description=f"Extracted {n_pages} pages ({len(text):,} chars)")

        if not text.strip():
            console.print("[red]No extractable text found in PDF.[/red]")
            sys.exit(1)

        progress.update(task, description="Sending to RAG API for ingestion...")
        payload = {
            "text": text,
            "source": src,
            "metadata": {**metadata, "pages": n_pages, "filename": pdf_path.name},
        }

        try:
            resp = httpx.post(
                f"{api_url}/ingest",
                json=payload,
                timeout=timeout,
            )
            resp.raise_for_status()
        except httpx.HTTPStatusError as exc:
            console.print(f"[red]API error {exc.response.status_code}: {exc.response.text}[/red]")
            sys.exit(1)
        except httpx.ConnectError:
            console.print(f"[red]Cannot connect to {api_url}. Is the stack running?[/red]")
            sys.exit(1)

    return resp.json()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Ingest a PDF into the self-hosted RAG stack"
    )
    parser.add_argument("--file", required=True, help="Path to PDF file")
    parser.add_argument(
        "--api-url", default="http://localhost:8000", help="Base URL of the RAG API"
    )
    parser.add_argument("--source", help="Document source label (defaults to filename)")
    parser.add_argument(
        "--metadata",
        default="{}",
        help='Extra metadata as JSON string, e.g. \'{"author": "Alice"}\'',
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=120.0,
        help="Request timeout in seconds (default: 120)",
    )
    args = parser.parse_args()

    pdf_path = Path(args.file)
    if not pdf_path.exists():
        console.print(f"[red]File not found: {pdf_path}[/red]")
        sys.exit(1)
    if pdf_path.suffix.lower() != ".pdf":
        console.print("[yellow]Warning: file does not have a .pdf extension.[/yellow]")

    try:
        meta: dict = json.loads(args.metadata)
    except json.JSONDecodeError:
        console.print("[red]--metadata must be valid JSON[/red]")
        sys.exit(1)

    result = ingest(
        pdf_path=pdf_path,
        api_url=args.api_url,
        source=args.source,
        metadata=meta,
        timeout=args.timeout,
    )

    console.print()
    console.print(f"[bold green]Ingestion successful![/bold green]")
    console.print(f"  doc_id        : [cyan]{result['doc_id']}[/cyan]")
    console.print(f"  source        : {result['source']}")
    console.print(f"  chunks_created: [bold]{result['chunks_created']}[/bold]")
    console.print()
    console.print(
        "Query with:\n"
        f"  curl -s -X POST {args.api_url}/query \\\n"
        "       -H 'Content-Type: application/json' \\\n"
        "       -d '{\"question\": \"What is this document about?\"}' | python -m json.tool"
    )


if __name__ == "__main__":
    main()
