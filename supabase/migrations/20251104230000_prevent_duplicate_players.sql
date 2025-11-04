-- Prevent duplicate players in tournaments

-- 1. Prevent same player being both player1 and player2 in same team
ALTER TABLE teams ADD CONSTRAINT check_different_players 
    CHECK (player1_id != player2_id);

-- 2. Prevent duplicate team names in same tournament
ALTER TABLE teams ADD CONSTRAINT unique_team_name_per_tournament
    UNIQUE (tournament_id, team_name);

-- 3. Prevent same player appearing in multiple teams in same tournament
CREATE OR REPLACE FUNCTION check_no_duplicate_players()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM teams 
        WHERE tournament_id = NEW.tournament_id 
        AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
        AND (player1_id = NEW.player1_id OR player2_id = NEW.player1_id OR player1_id = NEW.player2_id OR player2_id = NEW.player2_id)
    ) THEN
        RAISE EXCEPTION 'Player is already in another team in this tournament';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_duplicate_players
    BEFORE INSERT OR UPDATE ON teams
    FOR EACH ROW
    EXECUTE FUNCTION check_no_duplicate_players();