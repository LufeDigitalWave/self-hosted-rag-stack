--
-- PostgreSQL database dump
--

\restrict B2MN3tWQsAamZoBf5WNeyurrtsg2aabd0M5F0pxY4i5iPZxaHyN6nijsSRqvC4d

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

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: AccessLog; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."AccessLog" (
    id text NOT NULL,
    "userId" text NOT NULL,
    "userName" text NOT NULL,
    action text NOT NULL,
    "createdAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public."AccessLog" OWNER TO postgres;

--
-- Name: FatorPConfig; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."FatorPConfig" (
    id text DEFAULT 'default'::text NOT NULL,
    "canaisAtendimento" double precision DEFAULT 50 NOT NULL,
    "automacaoIA" double precision DEFAULT 50 NOT NULL,
    "segurancaConformidade" double precision DEFAULT 50 NOT NULL,
    "experienciaAtendente" double precision DEFAULT 50 NOT NULL,
    "infraQualidade" double precision DEFAULT 50 NOT NULL,
    "updatedAt" timestamp(3) without time zone NOT NULL
);


ALTER TABLE public."FatorPConfig" OWNER TO postgres;

--
-- Name: SprintCalendar; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."SprintCalendar" (
    id text NOT NULL,
    year text NOT NULL,
    month text NOT NULL,
    sprint text NOT NULL,
    period text NOT NULL,
    "startAt" timestamp(3) without time zone NOT NULL,
    "endAt" timestamp(3) without time zone NOT NULL
);


ALTER TABLE public."SprintCalendar" OWNER TO postgres;

--
-- Name: Task; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Task" (
    id text NOT NULL,
    task text NOT NULL,
    cluster text NOT NULL,
    module text DEFAULT 'nav'::text NOT NULL,
    responsible text NOT NULL,
    priority text DEFAULT 'media'::text NOT NULL,
    status text DEFAULT 'todo'::text NOT NULL,
    horizon text NOT NULL,
    due timestamp(3) without time zone,
    obs text,
    "storyPoints" integer,
    "estimatedHours" double precision,
    recurrent boolean DEFAULT false NOT NULL,
    "totalDeliveries" integer DEFAULT 1 NOT NULL,
    "currentDelivery" integer DEFAULT 1 NOT NULL,
    frequency text DEFAULT 'sprint'::text NOT NULL,
    "deliveryHistory" text DEFAULT '[]'::text NOT NULL,
    "attachedImages" text DEFAULT '[]'::text NOT NULL,
    "githubIssueId" integer,
    "githubIssueUrl" text,
    requester text,
    "createdAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" timestamp(3) without time zone NOT NULL
);


ALTER TABLE public."Task" OWNER TO postgres;

--
-- Name: TaskAudit; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."TaskAudit" (
    id text NOT NULL,
    "taskId" text NOT NULL,
    field text NOT NULL,
    "oldValue" text,
    "newValue" text,
    origem text DEFAULT 'usuario'::text NOT NULL,
    "createdAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "userId" text,
    "userName" text
);


ALTER TABLE public."TaskAudit" OWNER TO postgres;

--
-- Name: User; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."User" (
    id text NOT NULL,
    name text NOT NULL,
    email text NOT NULL,
    "passwordHash" text NOT NULL,
    role text DEFAULT 'admin'::text NOT NULL,
    "mustChangePassword" boolean DEFAULT true NOT NULL,
    active boolean DEFAULT true NOT NULL,
    "lastLoginAt" timestamp(3) without time zone,
    "createdAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" timestamp(3) without time zone NOT NULL
);


ALTER TABLE public."User" OWNER TO postgres;

--
-- Name: AccessLog AccessLog_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."AccessLog"
    ADD CONSTRAINT "AccessLog_pkey" PRIMARY KEY (id);


--
-- Name: FatorPConfig FatorPConfig_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."FatorPConfig"
    ADD CONSTRAINT "FatorPConfig_pkey" PRIMARY KEY (id);


--
-- Name: SprintCalendar SprintCalendar_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."SprintCalendar"
    ADD CONSTRAINT "SprintCalendar_pkey" PRIMARY KEY (id);


--
-- Name: TaskAudit TaskAudit_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."TaskAudit"
    ADD CONSTRAINT "TaskAudit_pkey" PRIMARY KEY (id);


--
-- Name: Task Task_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Task"
    ADD CONSTRAINT "Task_pkey" PRIMARY KEY (id);


--
-- Name: User User_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."User"
    ADD CONSTRAINT "User_pkey" PRIMARY KEY (id);


--
-- Name: AccessLog_createdAt_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "AccessLog_createdAt_idx" ON public."AccessLog" USING btree ("createdAt");


--
-- Name: AccessLog_userId_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "AccessLog_userId_idx" ON public."AccessLog" USING btree ("userId");


--
-- Name: SprintCalendar_year_month_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "SprintCalendar_year_month_idx" ON public."SprintCalendar" USING btree (year, month);


--
-- Name: TaskAudit_createdAt_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "TaskAudit_createdAt_idx" ON public."TaskAudit" USING btree ("createdAt");


--
-- Name: TaskAudit_taskId_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "TaskAudit_taskId_idx" ON public."TaskAudit" USING btree ("taskId");


--
-- Name: Task_cluster_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "Task_cluster_idx" ON public."Task" USING btree (cluster);


--
-- Name: Task_horizon_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "Task_horizon_idx" ON public."Task" USING btree (horizon);


--
-- Name: Task_responsible_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "Task_responsible_idx" ON public."Task" USING btree (responsible);


--
-- Name: Task_status_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "Task_status_idx" ON public."Task" USING btree (status);


--
-- Name: User_email_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "User_email_idx" ON public."User" USING btree (email);


--
-- Name: User_email_key; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "User_email_key" ON public."User" USING btree (email);


--
-- PostgreSQL database dump complete
--

\unrestrict B2MN3tWQsAamZoBf5WNeyurrtsg2aabd0M5F0pxY4i5iPZxaHyN6nijsSRqvC4d

