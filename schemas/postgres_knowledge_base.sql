--
-- PostgreSQL database dump
--

\restrict jSYqeZSH4gDeo40rBlBefB1m5EhaaDFtZrc1roBsIesjyb7jfqzIutfF09IK2rc

-- Dumped from database version 14.22 (Debian 14.22-1.pgdg12+1)
-- Dumped by pg_dump version 14.22 (Debian 14.22-1.pgdg12+1)

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
-- Name: knowledge_base knowledge_base_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.knowledge_base
    ADD CONSTRAINT knowledge_base_pkey PRIMARY KEY (id);


--
-- PostgreSQL database dump complete
--

\unrestrict jSYqeZSH4gDeo40rBlBefB1m5EhaaDFtZrc1roBsIesjyb7jfqzIutfF09IK2rc

