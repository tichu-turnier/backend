-- Initial schema for Tichu Tournament Management

-- Tournaments table
CREATE TABLE tournaments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    status VARCHAR(20) DEFAULT 'setup' CHECK (status IN ('setup', 'active', 'completed', 'cancelled')),
    max_teams INTEGER DEFAULT 16,
    current_round INTEGER DEFAULT 0,
    total_rounds INTEGER,
    created_by UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Players table
CREATE TABLE players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(name)
);

-- Teams table with access tokens
CREATE TABLE teams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id UUID REFERENCES tournaments(id) ON DELETE CASCADE,
    team_name VARCHAR(100) NOT NULL,
    player1_id UUID REFERENCES players(id) ON DELETE CASCADE,
    player2_id UUID REFERENCES players(id) ON DELETE CASCADE,
    access_token VARCHAR(50) UNIQUE NOT NULL,
    total_points INTEGER DEFAULT 0,
    victory_points INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(tournament_id, team_name)
);

-- Tournament rounds
CREATE TABLE tournament_rounds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id UUID REFERENCES tournaments(id) ON DELETE CASCADE,
    round_number INTEGER NOT NULL,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'completed')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(tournament_id, round_number)
);

-- Tournament matches with dual confirmation
CREATE TABLE tournament_matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    round_id UUID REFERENCES tournament_rounds(id) ON DELETE CASCADE,
    tournament_id UUID REFERENCES tournaments(id) ON DELETE CASCADE,
    team1_id UUID REFERENCES teams(id) ON DELETE CASCADE,
    team2_id UUID REFERENCES teams(id) ON DELETE CASCADE,
    table_number INTEGER,
    status VARCHAR(20) DEFAULT 'playing' CHECK (status IN ('playing', 'confirming', 'completed')),
    team1_confirmed BOOLEAN DEFAULT FALSE,
    team2_confirmed BOOLEAN DEFAULT FALSE,
    notes TEXT,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Individual games within matches (4 games per match)
CREATE TABLE games (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id UUID REFERENCES tournament_matches(id) ON DELETE CASCADE,
    game_number INTEGER NOT NULL CHECK (game_number BETWEEN 1 AND 4),
    team1_score INTEGER NOT NULL DEFAULT 0,
    team2_score INTEGER NOT NULL DEFAULT 0,
    team1_total_score INTEGER NOT NULL DEFAULT 0,
    team2_total_score INTEGER NOT NULL DEFAULT 0,
    team1_victory_points INTEGER DEFAULT 0,
    team2_victory_points INTEGER DEFAULT 0,
    team1_double_win BOOLEAN DEFAULT FALSE,
    team2_double_win BOOLEAN DEFAULT FALSE,
    beschiss BOOLEAN DEFAULT FALSE,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(match_id, game_number)
);

-- Game participants (detailed player tracking per game)
CREATE TABLE game_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID REFERENCES games(id) ON DELETE CASCADE,
    player_id UUID REFERENCES players(id) ON DELETE CASCADE,
    team INTEGER NOT NULL CHECK (team IN (1, 2)),
    position INTEGER CHECK (position BETWEEN 1 AND 4),
    tichu_call BOOLEAN DEFAULT FALSE,
    grand_tichu_call BOOLEAN DEFAULT FALSE,
    tichu_success BOOLEAN DEFAULT FALSE,
    bomb_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_tournaments_status ON tournaments(status);
CREATE INDEX idx_tournaments_created_by ON tournaments(created_by);
CREATE INDEX idx_players_name ON players(name);
CREATE INDEX idx_teams_tournament ON teams(tournament_id);
CREATE INDEX idx_teams_access_token ON teams(access_token);
CREATE INDEX idx_teams_players ON teams(player1_id, player2_id);
CREATE INDEX idx_rounds_tournament ON tournament_rounds(tournament_id);
CREATE INDEX idx_matches_round ON tournament_matches(round_id);
CREATE INDEX idx_matches_tournament ON tournament_matches(tournament_id);
CREATE INDEX idx_games_match ON games(match_id);
CREATE INDEX idx_game_participants_game ON game_participants(game_id);
CREATE INDEX idx_game_participants_team ON game_participants(team);
CREATE INDEX idx_game_participants_player ON game_participants(player_id);

-- Enable Row Level Security
ALTER TABLE tournaments ENABLE ROW LEVEL SECURITY;
ALTER TABLE players ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE tournament_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE tournament_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE games ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_participants ENABLE ROW LEVEL SECURITY;

-- RLS Policies for authenticated users (game masters)
CREATE POLICY "Users can manage own tournaments" ON tournaments
    FOR ALL USING (auth.uid() = created_by);

CREATE POLICY "Users can manage players" ON players
    FOR ALL USING (auth.uid() IS NOT NULL);

CREATE POLICY "Users can manage teams in own tournaments" ON teams
    FOR ALL USING (EXISTS (
        SELECT 1 FROM tournaments t 
        WHERE t.id = tournament_id AND t.created_by = auth.uid()
    ));

CREATE POLICY "Users can manage rounds in own tournaments" ON tournament_rounds
    FOR ALL USING (EXISTS (
        SELECT 1 FROM tournaments t 
        WHERE t.id = tournament_id AND t.created_by = auth.uid()
    ));

CREATE POLICY "Users can manage matches in own tournaments" ON tournament_matches
    FOR ALL USING (EXISTS (
        SELECT 1 FROM tournaments t 
        WHERE t.id = tournament_id AND t.created_by = auth.uid()
    ));

CREATE POLICY "Users can manage games in own tournaments" ON games
    FOR ALL USING (EXISTS (
        SELECT 1 FROM tournament_matches tm
        JOIN tournaments t ON t.id = tm.tournament_id
        WHERE tm.id = match_id AND t.created_by = auth.uid()
    ));

CREATE POLICY "Users can manage game participants in own tournaments" ON game_participants
    FOR ALL USING (EXISTS (
        SELECT 1 FROM games g
        JOIN tournament_matches tm ON tm.id = g.match_id
        JOIN tournaments t ON t.id = tm.tournament_id
        WHERE g.id = game_id AND t.created_by = auth.uid()
    ));

CREATE POLICY "Users can view all tournaments" ON tournaments
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- Public read access for active tournaments
CREATE POLICY "Public can view active tournaments" ON tournaments
    FOR SELECT USING (status IN ('active', 'completed'));

CREATE POLICY "Public can view players" ON players
    FOR SELECT USING (true);

CREATE POLICY "Public can view teams in active tournaments" ON teams
    FOR SELECT USING (EXISTS (
        SELECT 1 FROM tournaments t 
        WHERE t.id = tournament_id AND t.status IN ('active', 'completed')
    ));

CREATE POLICY "Public can view rounds in active tournaments" ON tournament_rounds
    FOR SELECT USING (EXISTS (
        SELECT 1 FROM tournaments t 
        WHERE t.id = tournament_id AND t.status IN ('active', 'completed')
    ));

CREATE POLICY "Public can view matches in active tournaments" ON tournament_matches
    FOR SELECT USING (EXISTS (
        SELECT 1 FROM tournaments t 
        WHERE t.id = tournament_id AND t.status IN ('active', 'completed')
    ));

CREATE POLICY "Public can view games in active tournaments" ON games
    FOR SELECT USING (EXISTS (
        SELECT 1 FROM tournament_matches tm
        JOIN tournaments t ON t.id = tm.tournament_id
        WHERE tm.id = match_id AND t.status IN ('active', 'completed')
    ));

CREATE POLICY "Public can view game participants in active tournaments" ON game_participants
    FOR SELECT USING (EXISTS (
        SELECT 1 FROM games g
        JOIN tournament_matches tm ON tm.id = g.match_id
        JOIN tournaments t ON t.id = tm.tournament_id
        WHERE g.id = game_id AND t.status IN ('active', 'completed')
    ));

-- Team access via access_token (no auth required)
CREATE POLICY "Teams can access players" ON players
    FOR SELECT USING (true);

CREATE POLICY "Teams can access via token" ON teams
    FOR SELECT USING (true);

CREATE POLICY "Teams can view their matches via token" ON tournament_matches
    FOR SELECT USING (
        team1_id IN (SELECT id FROM teams WHERE access_token IS NOT NULL) OR
        team2_id IN (SELECT id FROM teams WHERE access_token IS NOT NULL)
    );

CREATE POLICY "Teams can update match confirmation via token" ON tournament_matches
    FOR UPDATE USING (
        NOT (team1_confirmed = true AND team2_confirmed = true)
        AND (
            team1_id IN (SELECT id FROM teams WHERE access_token IS NOT NULL) OR
            team2_id IN (SELECT id FROM teams WHERE access_token IS NOT NULL)
        )
    );

CREATE POLICY "Teams can view their games via token" ON games
    FOR SELECT USING (EXISTS (
        SELECT 1 FROM tournament_matches tm
        WHERE tm.id = match_id AND (
            tm.team1_id IN (SELECT id FROM teams WHERE access_token IS NOT NULL) OR
            tm.team2_id IN (SELECT id FROM teams WHERE access_token IS NOT NULL)
        )
    ));

CREATE POLICY "Teams can view their game participants via token" ON game_participants
    FOR SELECT USING (EXISTS (
        SELECT 1 FROM games g
        JOIN tournament_matches tm ON tm.id = g.match_id
        WHERE g.id = game_id AND (
            tm.team1_id IN (SELECT id FROM teams WHERE access_token IS NOT NULL) OR
            tm.team2_id IN (SELECT id FROM teams WHERE access_token IS NOT NULL)
        )
    ));

CREATE POLICY "Teams can update their game participants via token" ON game_participants
    FOR UPDATE USING (EXISTS (
        SELECT 1 FROM games g
        JOIN tournament_matches tm ON tm.id = g.match_id
        WHERE g.id = game_id 
        AND NOT (tm.team1_confirmed = true OR tm.team2_confirmed = true)
        AND (
            tm.team1_id IN (SELECT id FROM teams WHERE access_token IS NOT NULL) OR
            tm.team2_id IN (SELECT id FROM teams WHERE access_token IS NOT NULL)
        )
    ));

CREATE POLICY "Teams can insert their game participants via token" ON game_participants
    FOR INSERT WITH CHECK (EXISTS (
        SELECT 1 FROM games g
        JOIN tournament_matches tm ON tm.id = g.match_id
        WHERE g.id = game_id 
        AND NOT (tm.team1_confirmed = true OR tm.team2_confirmed = true)
        AND (
            tm.team1_id IN (SELECT id FROM teams WHERE access_token IS NOT NULL) OR
            tm.team2_id IN (SELECT id FROM teams WHERE access_token IS NOT NULL)
        )
    ));

CREATE POLICY "Teams can update their games via token" ON games
    FOR UPDATE USING (EXISTS (
        SELECT 1 FROM tournament_matches tm
        WHERE tm.id = match_id 
        AND NOT (tm.team1_confirmed = true OR tm.team2_confirmed = true)
        AND (
            tm.team1_id IN (SELECT id FROM teams WHERE access_token IS NOT NULL) OR
            tm.team2_id IN (SELECT id FROM teams WHERE access_token IS NOT NULL)
        )
    ));

CREATE POLICY "Teams can insert their games via token" ON games
    FOR INSERT WITH CHECK (EXISTS (
        SELECT 1 FROM tournament_matches tm
        WHERE tm.id = match_id 
        AND NOT (tm.team1_confirmed = true OR tm.team2_confirmed = true)
        AND (
            tm.team1_id IN (SELECT id FROM teams WHERE access_token IS NOT NULL) OR
            tm.team2_id IN (SELECT id FROM teams WHERE access_token IS NOT NULL)
        )
    ));

-- Function to generate simple access tokens
CREATE OR REPLACE FUNCTION generate_team_access_token()
RETURNS TEXT AS $$
DECLARE
    adjectives TEXT[] := ARRAY['rot', 'blau', 'gruen', 'gelb', 'lila', 'orange', 'rosa', 'schwarz', 'weiss', 'silber', 'gold', 'hell', 'dunkel', 'schnell', 'langsam', 'gross', 'klein', 'froh', 'stark', 'wild'];
    nouns TEXT[] := ARRAY['katze', 'hund', 'vogel', 'fisch', 'loewe', 'tiger', 'baer', 'wolf', 'fuchs', 'reh', 'baum', 'stein', 'stern', 'mond', 'sonne', 'feuer', 'wasser', 'wind', 'wolke', 'berg'];
    token TEXT;
BEGIN
    token := adjectives[1 + floor(random() * array_length(adjectives, 1))] || '-' || 
             nouns[1 + floor(random() * array_length(nouns, 1))];
    
    -- Ensure uniqueness by checking if token already exists
    WHILE EXISTS (SELECT 1 FROM teams WHERE access_token = token) LOOP
        token := adjectives[1 + floor(random() * array_length(adjectives, 1))] || '-' || 
                 nouns[1 + floor(random() * array_length(nouns, 1))];
    END LOOP;
    
    RETURN token;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically generate access token for new teams
CREATE OR REPLACE FUNCTION set_team_access_token()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.access_token IS NULL OR NEW.access_token = '' THEN
        NEW.access_token := generate_team_access_token();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_team_access_token
    BEFORE INSERT ON teams
    FOR EACH ROW
    EXECUTE FUNCTION set_team_access_token();

-- Function to automatically set created_by for tournaments
CREATE OR REPLACE FUNCTION set_created_by()
RETURNS TRIGGER AS $$
BEGIN
    NEW.created_by := auth.uid();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_created_by
    BEFORE INSERT ON tournaments
    FOR EACH ROW
    EXECUTE FUNCTION set_created_by();