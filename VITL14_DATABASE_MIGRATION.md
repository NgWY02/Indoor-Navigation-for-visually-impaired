# ViT-L/14 Database Migration Instructions

## Issue
Your database is configured for **512-dimensional embeddings** (ViT-B/32), but **ViT-L/14 produces 768-dimensional embeddings**. This causes the error: `expected 512 dimensions, not 768`.

## Solution
Update the database schema to support 768-dimensional embeddings.

## Option 1: Supabase Dashboard (Recommended)

1. **Open Supabase Dashboard**:
   - Go to your Supabase project dashboard
   - Navigate to **SQL Editor**

2. **Run Migration Script**:
   Copy and paste this SQL script:

```sql
-- Migration script to upgrade database for CLIP ViT-L/14 (768 dimensions)
BEGIN;

-- Update path_waypoints table to support 768-dimensional embeddings
ALTER TABLE path_waypoints 
ALTER COLUMN embedding TYPE VECTOR(768);

-- Drop and recreate the vector similarity index with new dimensions
DROP INDEX IF EXISTS idx_path_waypoints_embedding_cosine;
CREATE INDEX idx_path_waypoints_embedding_cosine ON path_waypoints 
USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- Update column comment
COMMENT ON COLUMN path_waypoints.embedding IS 'CLIP ViT-L/14 visual embedding vector (768 dimensions)';

COMMIT;

-- Verify the change
SELECT 
    column_name, 
    data_type, 
    character_maximum_length
FROM information_schema.columns 
WHERE table_name = 'path_waypoints' AND column_name = 'embedding';
```

3. **Execute the Script**:
   - Click **Run** to execute the migration
   - Verify the output shows the embedding column now supports 768 dimensions

## Option 2: Local PostgreSQL (If Available)

If you have PostgreSQL tools installed locally:

```bash
psql -h your-supabase-host -U postgres -d postgres -f vitl14_migration.sql
```

## Option 3: Temporary Workaround (Quick Test)

If you want to test immediately without database changes, you can temporarily modify the ViT-L/14 server to output 512 dimensions by adding dimensionality reduction:

1. Edit `clip_server_vitl14.py`
2. Add PCA or truncation to reduce 768 → 512 dimensions
3. This is not recommended long-term as it loses information

## Verification

After running the migration, test by:

1. **Recording a new path** in your Flutter app
2. **Check for errors** - should no longer see dimension mismatch
3. **Verify embeddings** are being saved correctly

## Expected Results

- ✅ No more "expected 512 dimensions, not 768" errors
- ✅ Path recording works with ViT-L/14 embeddings
- ✅ Better hallway navigation discrimination
- ✅ All existing paths remain compatible

## Rollback (If Needed)

If you need to rollback to 512 dimensions:

```sql
ALTER TABLE path_waypoints 
ALTER COLUMN embedding TYPE VECTOR(512);
```

And switch back to the original CLIP server.
