-- Add settings column to tournaments table
ALTER TABLE tournaments ADD COLUMN settings JSONB DEFAULT '{"allow_grand_tichu": false}'::jsonb;

-- Update existing tournaments to have default settings
UPDATE tournaments SET settings = '{"allow_grand_tichu": false}'::jsonb WHERE settings IS NULL;