#!/bin/bash

# Configuration
BASE_URL="http://localhost:54321"
ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

# Check if JWT_TOKEN is set, if not get a fresh one
if [ -z "$JWT_TOKEN" ]; then
  echo "No JWT_TOKEN found, getting fresh token..."
  source ./testing/login-test-user.sh
fi

echo "=== Tichu Game Validation Tests (UPSERT) ==="

# Setup: Create tournament, players, teams, match
echo -e "\n=== SETUP ==="
TOURNAMENT_RESPONSE=$(curl -s -X POST "$BASE_URL/functions/v1/create-tournament" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "UPSERT Test Tournament", "description": "Testing UPSERT validation", "max_teams": 8}')
TOURNAMENT_ID=$(echo $TOURNAMENT_RESPONSE | jq -r '.id')

curl -s -X POST "$BASE_URL/rest/v1/players" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '[{"name": "Alice"}, {"name": "Bob"}, {"name": "Charlie"}, {"name": "Diana"}]' > /dev/null

PLAYER1_ID=$(curl -s -X GET "$BASE_URL/rest/v1/players?name=eq.Alice&select=id" -H "Authorization: Bearer $JWT_TOKEN" -H "apikey: $ANON_KEY" | jq -r '.[0].id')
PLAYER2_ID=$(curl -s -X GET "$BASE_URL/rest/v1/players?name=eq.Bob&select=id" -H "Authorization: Bearer $JWT_TOKEN" -H "apikey: $ANON_KEY" | jq -r '.[0].id')
PLAYER3_ID=$(curl -s -X GET "$BASE_URL/rest/v1/players?name=eq.Charlie&select=id" -H "Authorization: Bearer $JWT_TOKEN" -H "apikey: $ANON_KEY" | jq -r '.[0].id')
PLAYER4_ID=$(curl -s -X GET "$BASE_URL/rest/v1/players?name=eq.Diana&select=id" -H "Authorization: Bearer $JWT_TOKEN" -H "apikey: $ANON_KEY" | jq -r '.[0].id')

TEAM_RESPONSE=$(curl -s -X POST "$BASE_URL/rest/v1/teams" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d "[{\"tournament_id\": \"$TOURNAMENT_ID\", \"team_name\": \"Team Alpha\", \"player1_id\": \"$PLAYER1_ID\", \"player2_id\": \"$PLAYER2_ID\"}, {\"tournament_id\": \"$TOURNAMENT_ID\", \"team_name\": \"Team Beta\", \"player1_id\": \"$PLAYER3_ID\", \"player2_id\": \"$PLAYER4_ID\"}]")
TEAM_TOKEN=$(echo $TEAM_RESPONSE | jq -r '.[0].access_token')

START_RESPONSE=$(curl -s -X POST "$BASE_URL/functions/v1/start-tournament" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"tournament_id\": \"$TOURNAMENT_ID\"}")
MATCH_ID=$(echo $START_RESPONSE | jq -r '.matches[0].id')

echo "Setup complete. Match ID: $MATCH_ID"

# Test function
test_game() {
  local test_name="$1"
  local data="$2"
  local should_succeed="$3"
  
  echo -e "\n--- $test_name ---"
  RESPONSE=$(curl -s -X POST "$BASE_URL/functions/v1/submit-scores" \
    -H "Authorization: Bearer $ANON_KEY" \
    -H "team-token: $TEAM_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$data")
  
  if [[ "$should_succeed" == "true" ]]; then
    if echo "$RESPONSE" | jq -e '.success' > /dev/null; then
      echo "✅ PASS: $test_name"
    else
      echo "❌ FAIL: $test_name - Expected success but got: $(echo $RESPONSE | jq -r '.error // "unknown error"')"
    fi
  else
    if echo "$RESPONSE" | jq -e '.error' > /dev/null; then
      echo "✅ PASS: $test_name - Correctly rejected: $(echo $RESPONSE | jq -r '.error')"
    else
      echo "❌ FAIL: $test_name - Expected error but got success"
    fi
  fi
}

echo -e "\n=== VALID GAMES (NEW CREATION) ==="

# Valid normal game
test_game "Valid Game 1 - normal game" "{
  \"match_id\": \"$MATCH_ID\",
  \"game_number\": 1,
  \"team1_score\": 60,
  \"team2_score\": 40,
  \"team1_total_score\": 160,
  \"team2_total_score\": 40,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1, \"tichu_call\": true, \"tichu_success\": true, \"bomb_count\": 2},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 3, \"bomb_count\": 1},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": 2, \"bomb_count\": 0},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": 4, \"bomb_count\": 0}
  ]
}" "true"

# Valid double win game
test_game "Valid Game 2 - Double Win" "{
  \"match_id\": \"$MATCH_ID\",
  \"game_number\": 2,
  \"team1_score\": 0,
  \"team2_score\": 0,
  \"team1_total_score\": 200,
  \"team2_total_score\": 0,
  \"team1_double_win\": true,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1, \"bomb_count\": 1},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 2, \"bomb_count\": 0},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": null, \"bomb_count\": 2},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": null, \"bomb_count\": 3}
  ]
}" "true"

# Valid: Successful Grand Tichu
test_game "Valid Game 3 - Successful Grand Tichu" "{
  \"match_id\": \"$MATCH_ID\",
  \"game_number\": 3,
  \"team1_score\": 30,
  \"team2_score\": 70,
  \"team1_total_score\": 230,
  \"team2_total_score\": 70,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1, \"grand_tichu_call\": true, \"tichu_success\": true, \"bomb_count\": 0},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 3, \"bomb_count\": 1},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": 2, \"bomb_count\": 0},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": 4, \"bomb_count\": 2}
  ]
}" "true"

# Valid: Failed Small Tichu
test_game "Valid: Game 4 - Failed Small Tichu" "{
  \"match_id\": \"$MATCH_ID\",
  \"game_number\": 4,
  \"team1_score\": 80,
  \"team2_score\": 20,
  \"team1_total_score\": -20,
  \"team2_total_score\": 20,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 2, \"tichu_call\": true, \"tichu_success\": false, \"bomb_count\": 0},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 4, \"bomb_count\": 0},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": 1, \"bomb_count\": 1},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": 3, \"bomb_count\": 0}
  ]
}" "true"

# Get Game 4 ID for update tests
GAME4_ID=$(curl -s -X GET "$BASE_URL/rest/v1/games?match_id=eq.$MATCH_ID&game_number=eq.4&select=id" -H "Authorization: Bearer $JWT_TOKEN" -H "apikey: $ANON_KEY" | jq -r '.[0].id')
echo "Game 4 ID for updates: $GAME4_ID"

echo -e "\n=== VALID GAMES (UPDATES) ==="

# Valid: Multiple Tichu Calls (different players)
test_game "Multiple Tichu Calls" "{
  \"game_id\": \"$GAME4_ID\",
  \"team1_score\": 40,
  \"team2_score\": 60,
  \"team1_total_score\": 140,
  \"team2_total_score\": -140,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1, \"tichu_call\": true, \"tichu_success\": true, \"bomb_count\": 0},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 3, \"bomb_count\": 0},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": 2, \"grand_tichu_call\": true, \"tichu_success\": false, \"bomb_count\": 1},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": 4, \"bomb_count\": 0}
  ]
}" "true"

echo -e "\n=== INVALID GAMES ==="

# Invalid: Wrong number of participants
test_game "Wrong Number of Participants" "{
  \"game_id\": \"$GAME4_ID\",
  \"team1_score\": 50,
  \"team2_score\": 50,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1}
  ]
}" "false"

# Invalid: Duplicate positions
test_game "Duplicate Positions" "{
  \"game_id\": \"$GAME4_ID\",
  \"team1_score\": 50,
  \"team2_score\": 50,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 1},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": 3},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": 4}
  ]
}" "false"

# Invalid: Wrong team distribution
test_game "Wrong Team Distribution" "{
  \"game_id\": \"$GAME4_ID\",
  \"team1_score\": 50,
  \"team2_score\": 50,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 2},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 1, \"position\": 3},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": 4}
  ]
}" "false"

# Invalid: Base scores don't sum to 100
test_game "Base Scores Don't Sum to 100" "{
  \"game_id\": \"$GAME4_ID\",
  \"team1_score\": 60,
  \"team2_score\": 50,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 3},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": 2},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": 4}
  ]
}" "false"

# Invalid: Double win with non-zero base scores
test_game "Double Win with Non-Zero Base Scores" "{
  \"game_id\": \"$GAME4_ID\",
  \"team1_score\": 50,
  \"team2_score\": 50,
  \"team1_double_win\": true,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 2},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": null},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": null}
  ]
}" "false"

# Invalid: Both tichu calls
test_game "Both Tichu Calls" "{
  \"game_id\": \"$GAME4_ID\",
  \"team1_score\": 50,
  \"team2_score\": 50,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1, \"tichu_call\": true, \"grand_tichu_call\": true},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 3},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": 2},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": 4}
  ]
}" "false"

# Invalid: Tichu success without call
test_game "Tichu Success Without Call" "{
  \"game_id\": \"$GAME4_ID\",
  \"team1_score\": 50,
  \"team2_score\": 50,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1, \"tichu_success\": true},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 3},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": 2},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": 4}
  ]
}" "false"

# Invalid: Tichu success but not 1st place
test_game "Tichu Success But Not 1st Place" "{
  \"game_id\": \"$GAME4_ID\",
  \"team1_score\": 50,
  \"team2_score\": 50,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 3, \"tichu_call\": true, \"tichu_success\": true},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": 2},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": 4}
  ]
}" "false"

# Invalid: Too many bombs
test_game "Too Many Bombs" "{
  \"game_id\": \"$GAME4_ID\",
  \"team1_score\": 50,
  \"team2_score\": 50,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1, \"bomb_count\": 5},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 3},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": 2},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": 4}
  ]
}" "false"

echo -e "\n=== INVALID BONUS POINT CALCULATIONS ==="

# Invalid: Wrong Small Tichu bonus (should be +100, not +50)
test_game "Wrong Small Tichu Bonus" "{
  \"game_id\": \"$GAME4_ID\",
  \"team1_score\": 60,
  \"team2_score\": 40,
  \"team1_total_score\": 110,
  \"team2_total_score\": 40,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1, \"tichu_call\": true, \"tichu_success\": true},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 3},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": 2},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": 4}
  ]
}" "false"

# Invalid: Wrong Grand Tichu bonus (should be +200, not +100)
test_game "Wrong Grand Tichu Bonus" "{
  \"game_id\": \"$GAME4_ID\",
  \"team1_score\": 30,
  \"team2_score\": 70,
  \"team1_total_score\": 130,
  \"team2_total_score\": 70,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1, \"grand_tichu_call\": true, \"tichu_success\": true},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 3},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": 2},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": 4}
  ]
}" "false"

# Invalid: Wrong failed Tichu penalty (should be -100, not -50)
test_game "Wrong Failed Tichu Penalty" "{
  \"game_id\": \"$GAME4_ID\",
  \"team1_score\": 80,
  \"team2_score\": 20,
  \"team1_total_score\": 30,
  \"team2_total_score\": 20,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 2, \"tichu_call\": true, \"tichu_success\": false},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 4},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": 1},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": 3}
  ]
}" "false"

# Invalid: Wrong failed Grand Tichu penalty (should be -200, not -100)
test_game "Wrong Failed Grand Tichu Penalty" "{
  \"game_id\": \"$GAME4_ID\",
  \"team1_score\": 20,
  \"team2_score\": 80,
  \"team1_total_score\": -80,
  \"team2_total_score\": 80,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 3, \"grand_tichu_call\": true, \"tichu_success\": false},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 4},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": 1},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": 2}
  ]
}" "false"

# Invalid: Wrong Double Win bonus (should be +200, not +100)
test_game "Wrong Double Win Bonus" "{
  \"game_id\": \"$GAME4_ID\",
  \"team1_score\": 0,
  \"team2_score\": 0,
  \"team1_total_score\": 100,
  \"team2_total_score\": 0,
  \"team1_double_win\": true,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 2},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": null},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": null}
  ]
}" "false"

# Invalid: Multiple bonuses calculated wrong (Small Tichu + Grand Tichu)
test_game "Multiple Bonuses Calculated Wrong" "{
  \"game_id\": \"$GAME4_ID\",
  \"team1_score\": 40,
  \"team2_score\": 60,
  \"team1_total_score\": 90,
  \"team2_total_score\": -90,
  \"participants\": [
    {\"player_id\": \"$PLAYER1_ID\", \"team\": 1, \"position\": 1, \"tichu_call\": true, \"tichu_success\": true},
    {\"player_id\": \"$PLAYER2_ID\", \"team\": 1, \"position\": 3},
    {\"player_id\": \"$PLAYER3_ID\", \"team\": 2, \"position\": 2, \"grand_tichu_call\": true, \"tichu_success\": false},
    {\"player_id\": \"$PLAYER4_ID\", \"team\": 2, \"position\": 4}
  ]
}" "false"

echo -e "\n=== Validation Tests Complete ==="