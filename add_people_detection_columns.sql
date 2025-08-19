-- Add people detection columns to path_waypoints table
-- Run this in your Supabase SQL editor

ALTER TABLE path_waypoints 
ADD COLUMN IF NOT EXISTS people_detected BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS people_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS people_confidence_scores JSONB DEFAULT '[]'::jsonb;

-- Add index for efficient querying by people presence
CREATE INDEX IF NOT EXISTS idx_path_waypoints_people_detected 
ON path_waypoints(people_detected);

-- Update existing records to have default values (they will remain FALSE until re-recorded)
UPDATE path_waypoints 
SET 
  people_detected = FALSE,
  people_count = 0,
  people_confidence_scores = '[]'::jsonb
WHERE 
  people_detected IS NULL;

-- Add comments for documentation
COMMENT ON COLUMN path_waypoints.people_detected IS 'Whether people were detected in this waypoint during recording';
COMMENT ON COLUMN path_waypoints.people_count IS 'Number of people detected in this waypoint during recording';
COMMENT ON COLUMN path_waypoints.people_confidence_scores IS 'YOLO confidence scores for detected people (JSON array)';

-- Verify the changes
SELECT column_name, data_type, is_nullable, column_default 
FROM information_schema.columns 
WHERE table_name = 'path_waypoints' 
  AND column_name IN ('people_detected', 'people_count', 'people_confidence_scores');
