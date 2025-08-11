-- Migration script to upgrade database for CLIP ViT-L/14 (768 dimensions)
-- This updates the embedding column from VECTOR(512) to VECTOR(768)

-- Begin transaction
BEGIN;

-- 1. Update path_waypoints table to support 768-dimensional embeddings
ALTER TABLE path_waypoints 
ALTER COLUMN embedding TYPE VECTOR(768);

-- 2. Drop and recreate the vector similarity index with new dimensions
DROP INDEX IF EXISTS idx_path_waypoints_embedding_cosine;
CREATE INDEX idx_path_waypoints_embedding_cosine ON path_waypoints 
USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- 3. Update column comment
COMMENT ON COLUMN path_waypoints.embedding IS 'CLIP ViT-L/14 visual embedding vector (768 dimensions)';

-- 4. Verify the change
SELECT 
    column_name, 
    data_type, 
    character_maximum_length,
    column_default
FROM information_schema.columns 
WHERE table_name = 'path_waypoints' AND column_name = 'embedding';

-- Commit the transaction
COMMIT;

-- Display success message
SELECT 'Database successfully upgraded for CLIP ViT-L/14 (768 dimensions)' AS status;
