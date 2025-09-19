-- =============================================================================
-- INDOOR NAVIGATION SYSTEM - COMPLETE DATABASE SCHEMA
-- =============================================================================
-- Final Year Project - Supabase PostgreSQL Database
-- Comprehensive schema for all core tables
--
-- TABLES INCLUDED:
-- 1. maps - Indoor environment representations
-- 2. map_nodes - Physical locations and navigation waypoints
--
-- For complete ERD and additional tables, see:
-- - database_erd.md (Entity-Relationship Diagram)
-- - Additional table schemas as needed

-- =============================================================================
-- TABLE 1: maps
-- =============================================================================
-- Description: Indoor environment representations (building floors, campuses)
-- Purpose: Store map metadata and access control

CREATE TABLE public.maps (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  image_url text NOT NULL,
  is_public boolean NULL DEFAULT false,
  created_at timestamp with time zone NULL DEFAULT now(),
  user_id uuid NOT NULL,
  organization_id uuid NULL,
  created_by_admin_id uuid NULL,

  CONSTRAINT maps_pkey PRIMARY KEY (id),

  CONSTRAINT maps_created_by_admin_id_fkey
    FOREIGN KEY (created_by_admin_id)
    REFERENCES profiles (id)
    ON DELETE SET NULL,

  CONSTRAINT maps_organization_id_fkey
    FOREIGN KEY (organization_id)
    REFERENCES organizations (id)
    ON DELETE CASCADE,

  CONSTRAINT maps_user_id_fkey
    FOREIGN KEY (user_id)
    REFERENCES auth.users (id)
    ON DELETE CASCADE
) TABLESPACE pg_default;

-- Indexes for maps table
CREATE INDEX IF NOT EXISTS idx_maps_user_id
ON public.maps USING btree (user_id) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_maps_is_public
ON public.maps USING btree (is_public) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_maps_created_at
ON public.maps USING btree (created_at) TABLESPACE pg_default;

-- =============================================================================
-- TABLE 2: map_nodes
-- =============================================================================
-- Description: Physical locations (rooms, corridors, landmarks) within maps
-- Purpose: Define discrete navigation waypoints with spatial coordinates

CREATE TABLE public.map_nodes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  map_id uuid NOT NULL,
  name text NOT NULL,
  x_position double precision NOT NULL,
  y_position double precision NOT NULL,
  created_at timestamp with time zone NULL DEFAULT now(),
  user_id uuid NOT NULL,
  reference_direction double precision NULL,
  organization_id uuid NULL,

  CONSTRAINT map_nodes_pkey PRIMARY KEY (id),

  CONSTRAINT map_nodes_map_id_fkey
    FOREIGN KEY (map_id)
    REFERENCES maps (id)
    ON DELETE CASCADE,

  CONSTRAINT map_nodes_organization_id_fkey
    FOREIGN KEY (organization_id)
    REFERENCES organizations (id)
    ON DELETE CASCADE,

  CONSTRAINT map_nodes_user_id_fkey
    FOREIGN KEY (user_id)
    REFERENCES auth.users (id)
    ON DELETE CASCADE
) TABLESPACE pg_default;

-- Indexes for map_nodes table
CREATE INDEX IF NOT EXISTS idx_map_nodes_map_id
ON public.map_nodes USING btree (map_id) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_map_nodes_user_id
ON public.map_nodes USING btree (user_id) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_map_nodes_position
ON public.map_nodes USING btree (map_id, x_position, y_position) TABLESPACE pg_default;

-- =============================================================================
-- DEPLOYMENT INSTRUCTIONS
-- =============================================================================
--
-- SUPABASE DASHBOARD:
-- 1. Open Supabase Dashboard > SQL Editor
-- 2. Copy and paste this entire file
-- 3. Click "Run" to execute all tables
--
-- SUPABASE CLI:
-- supabase db push
--
-- VERIFICATION:
-- Check that both tables were created successfully:
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema = 'public'
-- AND table_name IN ('maps', 'map_nodes');
--
-- =============================================================================
-- TABLE RELATIONSHIPS
-- =============================================================================
--
-- maps (1) ──── (many) map_nodes
-- │
-- └── organization_id ──── organizations
-- └── user_id ──── auth.users
-- └── created_by_admin_id ──── profiles
--
-- map_nodes
-- ├── map_id ──── maps
-- ├── organization_id ──── organizations
-- └── user_id ──── auth.users
--
-- =============================================================================
-- DATA FLOW
-- =============================================================================
--
-- 1. Create maps first (parent table)
-- 2. Add map_nodes to maps (child table)
-- 3. Foreign key constraints ensure referential integrity
-- 4. CASCADE deletes remove child records when parent is deleted
--
-- =============================================================================
-- FINAL YEAR PROJECT REFERENCE
-- =============================================================================
--
-- This schema represents the core spatial data structure for the indoor
-- navigation system. See Chapter 4.6 for complete ERD documentation.
-- See database_erd.md for the full Entity-Relationship Diagram.
