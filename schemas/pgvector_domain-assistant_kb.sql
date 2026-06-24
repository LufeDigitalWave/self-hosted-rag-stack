--
-- PostgreSQL database dump
--

\restrict GulMZVne0btARnvRhIsmNyCWlhKQeJuOq0Yu9R09nGzUfVBbHNdhT5USTEqc9R6

-- Dumped from database version 16.13 (Debian 16.13-1.pgdg12+1)
-- Dumped by pg_dump version 16.13 (Debian 16.13-1.pgdg12+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;


--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';


--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


--
-- Name: immutable_unaccent(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.immutable_unaccent(text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE
    AS $_$
BEGIN
  RETURN unaccent('unaccent', $1);
END;
$_$;


ALTER FUNCTION public.immutable_unaccent(text) OWNER TO postgres;

--
-- Name: kb_chunks_homologacao_update_tsv(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.kb_chunks_homologacao_update_tsv() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.content_tsv := to_tsvector('portuguese',
    unaccent(
      coalesce(NEW.title, '') || ' ' ||
      coalesce(NEW.content, '') || ' ' ||
      coalesce(array_to_string(NEW.keywords, ' '), '') || ' ' ||
      coalesce(array_to_string(NEW.aliases, ' '), '')
    )
  );
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.kb_chunks_homologacao_update_tsv() OWNER TO postgres;

--
-- Name: kb_chunks_update_tsv(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.kb_chunks_update_tsv() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.content_tsv := to_tsvector('portuguese',
    unaccent(
      coalesce(NEW.title, '') || ' ' ||
      coalesce(NEW.content, '') || ' ' ||
      coalesce(array_to_string(NEW.keywords, ' '), '') || ' ' ||
      coalesce(array_to_string(NEW.aliases, ' '), '')
    )
  );
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.kb_chunks_update_tsv() OWNER TO postgres;

--
-- Name: kb_hybrid_search(public.vector, text, text, text, text, integer, integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.kb_hybrid_search(p_query_emb public.vector, p_query_text text, p_topic text DEFAULT NULL::text, p_subtopic text DEFAULT NULL::text, p_categoria text DEFAULT NULL::text, p_top_k integer DEFAULT 20, p_rrf_k integer DEFAULT 60, p_navio text DEFAULT NULL::text) RETURNS TABLE(chunk_id text, doc_id text, topic text, subtopic text, title text, content text, keywords text[], aliases text[], categoria_cabine text, fonte text, score real)
    LANGUAGE sql STABLE
    AS $$
WITH
vec AS (
  SELECT chunk_id,
         ROW_NUMBER() OVER (ORDER BY embedding <=> p_query_emb) AS rnk
  FROM kb_chunks
  WHERE (p_topic     IS NULL OR kb_chunks.topic = p_topic)
    AND (p_subtopic  IS NULL OR kb_chunks.subtopic = p_subtopic)
    AND (p_categoria IS NULL OR kb_chunks.categoria_cabine = p_categoria)
    AND (p_navio     IS NULL
         OR p_navio = ANY(kb_chunks.navio)
         OR cardinality(kb_chunks.navio) = 0)
  ORDER BY embedding <=> p_query_emb
  LIMIT p_top_k * 3
),
lex AS (
  SELECT chunk_id,
         ROW_NUMBER() OVER (
           ORDER BY ts_rank_cd(content_tsv,
                               plainto_tsquery('portuguese', unaccent(p_query_text))) DESC
         ) AS rnk
  FROM kb_chunks
  WHERE content_tsv @@ plainto_tsquery('portuguese', unaccent(p_query_text))
    AND (p_topic     IS NULL OR kb_chunks.topic = p_topic)
    AND (p_subtopic  IS NULL OR kb_chunks.subtopic = p_subtopic)
    AND (p_categoria IS NULL OR kb_chunks.categoria_cabine = p_categoria)
    AND (p_navio     IS NULL
         OR p_navio = ANY(kb_chunks.navio)
         OR cardinality(kb_chunks.navio) = 0)
  ORDER BY rnk
  LIMIT p_top_k * 3
),
fused AS (
  SELECT chunk_id,
         SUM(1.0 / (p_rrf_k + rnk))::real AS score
  FROM (
    SELECT chunk_id, rnk FROM vec
    UNION ALL
    SELECT chunk_id, rnk FROM lex
  ) u
  GROUP BY chunk_id
  ORDER BY score DESC
  LIMIT p_top_k
)
SELECT c.chunk_id, c.doc_id, c.topic, c.subtopic, c.title, c.content,
       c.keywords, c.aliases, c.categoria_cabine, c.fonte, f.score
FROM fused f JOIN kb_chunks c USING (chunk_id)
ORDER BY f.score DESC;
$$;


ALTER FUNCTION public.kb_hybrid_search(p_query_emb public.vector, p_query_text text, p_topic text, p_subtopic text, p_categoria text, p_top_k integer, p_rrf_k integer, p_navio text) OWNER TO postgres;

--
-- Name: kb_hybrid_search_homologacao(public.vector, text, text, text, text, integer, integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.kb_hybrid_search_homologacao(p_query_emb public.vector, p_query_text text, p_topic text DEFAULT NULL::text, p_subtopic text DEFAULT NULL::text, p_categoria text DEFAULT NULL::text, p_top_k integer DEFAULT 20, p_rrf_k integer DEFAULT 60, p_navio text DEFAULT NULL::text) RETURNS TABLE(chunk_id text, doc_id text, topic text, subtopic text, title text, content text, keywords text[], aliases text[], categoria_cabine text, fonte text, score real)
    LANGUAGE sql STABLE
    AS $$
WITH
vec AS (
  SELECT chunk_id,
         ROW_NUMBER() OVER (ORDER BY embedding <=> p_query_emb) AS rnk
  FROM kb_chunks_homologacao
  WHERE (p_topic     IS NULL OR kb_chunks_homologacao.topic = p_topic)
    AND (p_subtopic  IS NULL OR kb_chunks_homologacao.subtopic = p_subtopic)
    AND (p_categoria IS NULL OR kb_chunks_homologacao.categoria_cabine = p_categoria)
    AND (p_navio     IS NULL
         OR p_navio = ANY(kb_chunks_homologacao.navio)
         OR cardinality(kb_chunks_homologacao.navio) = 0)
  ORDER BY embedding <=> p_query_emb
  LIMIT p_top_k * 3
),
lex AS (
  SELECT chunk_id,
         ROW_NUMBER() OVER (
           ORDER BY ts_rank_cd(content_tsv,
                               plainto_tsquery('portuguese', unaccent(p_query_text))) DESC
         ) AS rnk
  FROM kb_chunks_homologacao
  WHERE content_tsv @@ plainto_tsquery('portuguese', unaccent(p_query_text))
    AND (p_topic     IS NULL OR kb_chunks_homologacao.topic = p_topic)
    AND (p_subtopic  IS NULL OR kb_chunks_homologacao.subtopic = p_subtopic)
    AND (p_categoria IS NULL OR kb_chunks_homologacao.categoria_cabine = p_categoria)
    AND (p_navio     IS NULL
         OR p_navio = ANY(kb_chunks_homologacao.navio)
         OR cardinality(kb_chunks_homologacao.navio) = 0)
  ORDER BY rnk
  LIMIT p_top_k * 3
),
fused AS (
  SELECT chunk_id,
         SUM(1.0 / (p_rrf_k + rnk))::real AS score
  FROM (
    SELECT chunk_id, rnk FROM vec
    UNION ALL
    SELECT chunk_id, rnk FROM lex
  ) u
  GROUP BY chunk_id
  ORDER BY score DESC
  LIMIT p_top_k
)
SELECT c.chunk_id, c.doc_id, c.topic, c.subtopic, c.title, c.content,
       c.keywords, c.aliases, c.categoria_cabine, c.fonte, f.score
FROM fused f JOIN kb_chunks_homologacao c USING (chunk_id)
ORDER BY f.score DESC;
$$;


ALTER FUNCTION public.kb_hybrid_search_homologacao(p_query_emb public.vector, p_query_text text, p_topic text, p_subtopic text, p_categoria text, p_top_k integer, p_rrf_k integer, p_navio text) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: cabin_media; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cabin_media (
    id text NOT NULL,
    categoria text NOT NULL,
    variante text,
    label text NOT NULL,
    asset_url text NOT NULL,
    whatsapp_id text,
    created_at timestamp with time zone DEFAULT now(),
    tag_chatwoot text
);


ALTER TABLE public.cabin_media OWNER TO postgres;

--
-- Name: kb_chunks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.kb_chunks (
    chunk_id text NOT NULL,
    doc_id text NOT NULL,
    topic text NOT NULL,
    subtopic text,
    title text NOT NULL,
    content text NOT NULL,
    keywords text[] DEFAULT '{}'::text[],
    aliases text[] DEFAULT '{}'::text[],
    navio text[] DEFAULT '{}'::text[],
    temporada text,
    categoria_cabine text,
    fonte text,
    versao text,
    embedding public.vector(1024) NOT NULL,
    content_tsv tsvector,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.kb_chunks OWNER TO postgres;

--
-- Name: kb_chunks_homologacao; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.kb_chunks_homologacao (
    chunk_id text NOT NULL,
    doc_id text NOT NULL,
    topic text NOT NULL,
    subtopic text,
    title text NOT NULL,
    content text NOT NULL,
    keywords text[] DEFAULT '{}'::text[],
    aliases text[] DEFAULT '{}'::text[],
    navio text[] DEFAULT '{}'::text[],
    temporada text,
    categoria_cabine text,
    fonte text,
    versao text,
    embedding public.vector(1024) NOT NULL,
    content_tsv tsvector,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.kb_chunks_homologacao OWNER TO postgres;

--
-- Name: kb_queries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.kb_queries (
    id bigint NOT NULL,
    session_id text,
    query text,
    topic_filter text,
    top_chunk_id text,
    top_score real,
    has_result boolean,
    latency_ms integer,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.kb_queries OWNER TO postgres;

--
-- Name: kb_queries_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.kb_queries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.kb_queries_id_seq OWNER TO postgres;

--
-- Name: kb_queries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.kb_queries_id_seq OWNED BY public.kb_queries.id;


--
-- Name: kb_queries id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kb_queries ALTER COLUMN id SET DEFAULT nextval('public.kb_queries_id_seq'::regclass);


--
-- Name: cabin_media cabin_media_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cabin_media
    ADD CONSTRAINT cabin_media_pkey PRIMARY KEY (id);


--
-- Name: kb_chunks_homologacao kb_chunks_homologacao_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kb_chunks_homologacao
    ADD CONSTRAINT kb_chunks_homologacao_pkey PRIMARY KEY (chunk_id);


--
-- Name: kb_chunks kb_chunks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kb_chunks
    ADD CONSTRAINT kb_chunks_pkey PRIMARY KEY (chunk_id);


--
-- Name: kb_queries kb_queries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kb_queries
    ADD CONSTRAINT kb_queries_pkey PRIMARY KEY (id);


--
-- Name: cabin_media_cat_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX cabin_media_cat_idx ON public.cabin_media USING btree (categoria);


--
-- Name: cabin_media_tag_chatwoot_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX cabin_media_tag_chatwoot_idx ON public.cabin_media USING btree (tag_chatwoot);


--
-- Name: kb_aliases_gin; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX kb_aliases_gin ON public.kb_chunks USING gin (aliases);


--
-- Name: kb_aliases_gin_homologacao; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX kb_aliases_gin_homologacao ON public.kb_chunks_homologacao USING gin (aliases) WITH (fastupdate='true', gin_pending_list_limit='4194304');


--
-- Name: kb_categoria_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX kb_categoria_idx ON public.kb_chunks USING btree (categoria_cabine);


--
-- Name: kb_categoria_idx_homologacao; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX kb_categoria_idx_homologacao ON public.kb_chunks_homologacao USING btree (categoria_cabine) WITH (fillfactor='100', deduplicate_items='true');


--
-- Name: kb_hnsw_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX kb_hnsw_idx ON public.kb_chunks USING hnsw (embedding public.vector_cosine_ops) WITH (m='16', ef_construction='64');


--
-- Name: kb_hnsw_idx_homologacao; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX kb_hnsw_idx_homologacao ON public.kb_chunks_homologacao USING hnsw (embedding public.vector_cosine_ops);


--
-- Name: kb_keywords_gin; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX kb_keywords_gin ON public.kb_chunks USING gin (keywords);


--
-- Name: kb_keywords_gin_homologacao; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX kb_keywords_gin_homologacao ON public.kb_chunks_homologacao USING gin (keywords) WITH (fastupdate='true', gin_pending_list_limit='4194304');


--
-- Name: kb_navio_gin; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX kb_navio_gin ON public.kb_chunks USING gin (navio);


--
-- Name: kb_navio_gin_homologacao; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX kb_navio_gin_homologacao ON public.kb_chunks_homologacao USING gin (navio) WITH (fastupdate='true', gin_pending_list_limit='4194304');


--
-- Name: kb_subtopic_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX kb_subtopic_idx ON public.kb_chunks USING btree (subtopic);


--
-- Name: kb_subtopic_idx_homologacao; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX kb_subtopic_idx_homologacao ON public.kb_chunks_homologacao USING btree (subtopic) WITH (fillfactor='100', deduplicate_items='true');


--
-- Name: kb_topic_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX kb_topic_idx ON public.kb_chunks USING btree (topic);


--
-- Name: kb_topic_idx_homologacao; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX kb_topic_idx_homologacao ON public.kb_chunks_homologacao USING btree (topic) WITH (fillfactor='100', deduplicate_items='true');


--
-- Name: kb_tsv_gin; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX kb_tsv_gin ON public.kb_chunks USING gin (content_tsv);


--
-- Name: kb_tsv_gin_homologacao; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX kb_tsv_gin_homologacao ON public.kb_chunks_homologacao USING gin (content_tsv) WITH (fastupdate='true', gin_pending_list_limit='4194304');


--
-- Name: kb_chunks_homologacao kb_chunks_homologacao_update_tsv; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER kb_chunks_homologacao_update_tsv BEFORE INSERT OR UPDATE ON public.kb_chunks_homologacao FOR EACH ROW EXECUTE FUNCTION public.kb_chunks_homologacao_update_tsv();


--
-- Name: kb_chunks kb_chunks_tsv_trg; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER kb_chunks_tsv_trg BEFORE INSERT OR UPDATE ON public.kb_chunks FOR EACH ROW EXECUTE FUNCTION public.kb_chunks_update_tsv();


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO rag_reader;


--
-- Name: FUNCTION immutable_unaccent(text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.immutable_unaccent(text) TO rag_reader;


--
-- Name: FUNCTION kb_hybrid_search(p_query_emb public.vector, p_query_text text, p_topic text, p_subtopic text, p_categoria text, p_top_k integer, p_rrf_k integer, p_navio text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.kb_hybrid_search(p_query_emb public.vector, p_query_text text, p_topic text, p_subtopic text, p_categoria text, p_top_k integer, p_rrf_k integer, p_navio text) TO rag_reader;


--
-- Name: FUNCTION kb_hybrid_search_homologacao(p_query_emb public.vector, p_query_text text, p_topic text, p_subtopic text, p_categoria text, p_top_k integer, p_rrf_k integer, p_navio text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.kb_hybrid_search_homologacao(p_query_emb public.vector, p_query_text text, p_topic text, p_subtopic text, p_categoria text, p_top_k integer, p_rrf_k integer, p_navio text) TO rag_reader;


--
-- Name: TABLE cabin_media; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.cabin_media TO rag_reader;


--
-- Name: TABLE kb_chunks; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.kb_chunks TO rag_reader;


--
-- Name: TABLE kb_chunks_homologacao; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.kb_chunks_homologacao TO rag_reader;


--
-- Name: TABLE kb_queries; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT ON TABLE public.kb_queries TO rag_reader;


--
-- Name: SEQUENCE kb_queries_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.kb_queries_id_seq TO rag_reader;


--
-- PostgreSQL database dump complete
--

\unrestrict GulMZVne0btARnvRhIsmNyCWlhKQeJuOq0Yu9R09nGzUfVBbHNdhT5USTEqc9R6

