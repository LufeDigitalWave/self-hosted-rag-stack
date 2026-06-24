--
-- PostgreSQL database dump
--

\restrict GxTPlS645jiOZKlpoOd6SNskjWZno88gHglS95WHSJ0Boyr7jS2Bnwle5UbAq6J

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
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


--
-- Name: match_documents(public.vector, double precision, integer, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.match_documents(query_embedding public.vector, match_threshold double precision DEFAULT 0.2, match_count integer DEFAULT 10, filter jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(id integer, content text, metadata jsonb, similarity double precision)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    d.id,
    d.content,
    d.metadata,
    1 - (d.embedding <=> query_embedding) AS similarity
  FROM public.documentos d
  WHERE d.embedding IS NOT NULL
    AND (filter = '{}'::jsonb OR d.metadata @> filter)
    AND (1 - (d.embedding <=> query_embedding)) >= match_threshold
  ORDER BY d.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;


ALTER FUNCTION public.match_documents(query_embedding public.vector, match_threshold double precision, match_count integer, filter jsonb) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: knowledge_base; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.knowledge_base (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    text text,
    metadata jsonb,
    embedding public.vector
);


ALTER TABLE public.knowledge_base OWNER TO postgres;

--
-- Name: documentos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.documentos (
    id integer NOT NULL,
    content text,
    metadata jsonb,
    embedding public.vector(1536)
);


ALTER TABLE public.documentos OWNER TO postgres;

--
-- Name: documentos_reembed_dlq; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.documentos_reembed_dlq (
    id integer,
    error text,
    failed_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.documentos_reembed_dlq OWNER TO postgres;

--
-- Name: knowledge_base knowledge_base_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.knowledge_base
    ADD CONSTRAINT knowledge_base_pkey PRIMARY KEY (id);


--
-- Name: documentos documentos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.documentos
    ADD CONSTRAINT documentos_pkey PRIMARY KEY (id);


--
-- PostgreSQL database dump complete
--

\unrestrict GxTPlS645jiOZKlpoOd6SNskjWZno88gHglS95WHSJ0Boyr7jS2Bnwle5UbAq6J

