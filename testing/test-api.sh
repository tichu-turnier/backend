#!/bin/bash

# Configuration
BASE_URL="http://localhost:54321"
ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

# Check if JWT_TOKEN is set, if not get a fresh one
if [ -z "$JWT_TOKEN" ]; then
  echo "No JWT_TOKEN found, getting fresh token..."
  source ./testing/login-test-user.sh
fi

echo "=== Tichu Tournament API Tests ==="

# Test 1: Create Tournament
echo -e "\n1. Creating Tournament..."
TOURNAMENT_RESPONSE=$(curl -s -X POST "$BASE_URL/functions/v1/create-tournament" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Turnier",
    "description": "Mein erstes Turnier",
    "max_teams": 8
  }')
echo $TOURNAMENT_RESPONSE | jq .
TOURNAMENT_ID=$(echo $TOURNAMENT_RESPONSE | jq -r '.id')

# Test 1.1: Create Players (8 players for 4 teams)
echo -e "\n1.1 Creating Players..."
curl -s -X POST "$BASE_URL/rest/v1/players" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '[{"name": "Alice"}, {"name": "Bob"}, {"name": "Charlie"}, {"name": "Diana"}, {"name": "Eve"}, {"name": "Frank"}, {"name": "Grace"}, {"name": "Henry"}]' | jq .

# Test 1.2: Create Teams (4 teams)
echo -e "\n1.2 Creating Teams..."
PLAYER1_ID=$(curl -s -X GET "$BASE_URL/rest/v1/players?name=eq.Alice&select=id" -H "Authorization: Bearer $JWT_TOKEN" -H "apikey: $ANON_KEY" | jq -r '.[0].id')
PLAYER2_ID=$(curl -s -X GET "$BASE_URL/rest/v1/players?name=eq.Bob&select=id" -H "Authorization: Bearer $JWT_TOKEN" -H "apikey: $ANON_KEY" | jq -r '.[0].id')
PLAYER3_ID=$(curl -s -X GET "$BASE_URL/rest/v1/players?name=eq.Charlie&select=id" -H "Authorization: Bearer $JWT_TOKEN" -H "apikey: $ANON_KEY" | jq -r '.[0].id')
PLAYER4_ID=$(curl -s -X GET "$BASE_URL/rest/v1/players?name=eq.Diana&select=id" -H "Authorization: Bearer $JWT_TOKEN" -H "apikey: $ANON_KEY" | jq -r '.[0].id')
PLAYER5_ID=$(curl -s -X GET "$BASE_URL/rest/v1/players?name=eq.Eve&select=id" -H "Authorization: Bearer $JWT_TOKEN" -H "apikey: $ANON_KEY" | jq -r '.[0].id')
PLAYER6_ID=$(curl -s -X GET "$BASE_URL/rest/v1/players?name=eq.Frank&select=id" -H "Authorization: Bearer $JWT_TOKEN" -H "apikey: $ANON_KEY" | jq -r '.[0].id')
PLAYER7_ID=$(curl -s -X GET "$BASE_URL/rest/v1/players?name=eq.Grace&select=id" -H "Authorization: Bearer $JWT_TOKEN" -H "apikey: $ANON_KEY" | jq -r '.[0].id')
PLAYER8_ID=$(curl -s -X GET "$BASE_URL/rest/v1/players?name=eq.Henry&select=id" -H "Authorization: Bearer $JWT_TOKEN" -H "apikey: $ANON_KEY" | jq -r '.[0].id')

TEAM_RESPONSE=$(curl -s -X POST "$BASE_URL/rest/v1/teams" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d "[{\"tournament_id\": \"$TOURNAMENT_ID\", \"team_name\": \"Team Alpha\", \"player1_id\": \"$PLAYER1_ID\", \"player2_id\": \"$PLAYER2_ID\"}, {\"tournament_id\": \"$TOURNAMENT_ID\", \"team_name\": \"Team Beta\", \"player1_id\": \"$PLAYER3_ID\", \"player2_id\": \"$PLAYER4_ID\"}, {\"tournament_id\": \"$TOURNAMENT_ID\", \"team_name\": \"Team Gamma\", \"player1_id\": \"$PLAYER5_ID\", \"player2_id\": \"$PLAYER6_ID\"}, {\"tournament_id\": \"$TOURNAMENT_ID\", \"team_name\": \"Team Delta\", \"player1_id\": \"$PLAYER7_ID\", \"player2_id\": \"$PLAYER8_ID\"}]")
echo $TEAM_RESPONSE | jq .

# Extract all team tokens and IDs
TEAM_ALPHA_ID=$(echo $TEAM_RESPONSE | jq -r '.[0].id')
TEAM_BETA_ID=$(echo $TEAM_RESPONSE | jq -r '.[1].id')
TEAM_GAMMA_ID=$(echo $TEAM_RESPONSE | jq -r '.[2].id')
TEAM_DELTA_ID=$(echo $TEAM_RESPONSE | jq -r '.[3].id')

TEAM_ALPHA_TOKEN=$(echo $TEAM_RESPONSE | jq -r '.[0].access_token')
TEAM_BETA_TOKEN=$(echo $TEAM_RESPONSE | jq -r '.[1].access_token')
TEAM_GAMMA_TOKEN=$(echo $TEAM_RESPONSE | jq -r '.[2].access_token')
TEAM_DELTA_TOKEN=$(echo $TEAM_RESPONSE | jq -r '.[3].access_token')

echo "Team Tokens:"
echo "Alpha: $TEAM_ALPHA_TOKEN"
echo "Beta: $TEAM_BETA_TOKEN"
echo "Gamma: $TEAM_GAMMA_TOKEN"
echo "Delta: $TEAM_DELTA_TOKEN"

# Test 1.3: Start Tournament (generates pairings)
echo -e "\n1.3 Starting Tournament..."
START_RESPONSE=$(curl -s -X POST "$BASE_URL/functions/v1/start-tournament" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"tournament_id\": \"$TOURNAMENT_ID\"}")
echo $START_RESPONSE | jq .

# Helper function to get team token by team ID
get_team_token() {
  local team_id=$1
  if [ "$team_id" = "$TEAM_ALPHA_ID" ]; then echo "$TEAM_ALPHA_TOKEN"
  elif [ "$team_id" = "$TEAM_BETA_ID" ]; then echo "$TEAM_BETA_TOKEN"
  elif [ "$team_id" = "$TEAM_GAMMA_ID" ]; then echo "$TEAM_GAMMA_TOKEN"
  elif [ "$team_id" = "$TEAM_DELTA_ID" ]; then echo "$TEAM_DELTA_TOKEN"
  fi
}

# Test 1.4: Complete all matches in round 1
echo -e "\n1.4 Completing all matches in round 1..."
echo $START_RESPONSE | jq -c '.matches[]' | while read match; do
  match_id=$(echo $match | jq -r '.id')
  team1_id=$(echo $match | jq -r '.team1_id')
  team2_id=$(echo $match | jq -r '.team2_id')
  team1_token=$(get_team_token $team1_id)
  team2_token=$(get_team_token $team2_id)
  
  echo "Completing match $match_id (Team1: $team1_id, Team2: $team2_id)..."
  
  # Get player IDs for this match
  team1_player1=$(curl -s -X GET "$BASE_URL/rest/v1/teams?id=eq.$team1_id&select=player1_id" -H "Authorization: Bearer $ANON_KEY" | jq -r '.[0].player1_id')
  team1_player2=$(curl -s -X GET "$BASE_URL/rest/v1/teams?id=eq.$team1_id&select=player2_id" -H "Authorization: Bearer $ANON_KEY" | jq -r '.[0].player2_id')
  team2_player1=$(curl -s -X GET "$BASE_URL/rest/v1/teams?id=eq.$team2_id&select=player1_id" -H "Authorization: Bearer $ANON_KEY" | jq -r '.[0].player1_id')
  team2_player2=$(curl -s -X GET "$BASE_URL/rest/v1/teams?id=eq.$team2_id&select=player2_id" -H "Authorization: Bearer $ANON_KEY" | jq -r '.[0].player2_id')
  
  # Play 4 games
  for i in {1..4}; do
    curl -s -X POST "$BASE_URL/functions/v1/submit-scores" \
      -H "Authorization: Bearer $ANON_KEY" \
      -H "team-token: $team1_token" \
      -H "Content-Type: application/json" \
      -d "{
        \"match_id\": \"$match_id\",
        \"game_number\": $i,
        \"team1_score\": 60,
        \"team2_score\": 40,
        \"team1_total_score\": 60,
        \"team2_total_score\": 40,
        \"participants\": [
          {\"player_id\": \"$team1_player1\", \"team\": 1, \"position\": 1, \"bomb_count\": 0},
          {\"player_id\": \"$team1_player2\", \"team\": 1, \"position\": 3, \"bomb_count\": 0},
          {\"player_id\": \"$team2_player1\", \"team\": 2, \"position\": 2, \"bomb_count\": 0},
          {\"player_id\": \"$team2_player2\", \"team\": 2, \"position\": 4, \"bomb_count\": 0}
        ]
      }" > /dev/null
  done
  
  # Confirm match (both teams)
  curl -s -X POST "$BASE_URL/functions/v1/confirm-match" \
    -H "Authorization: Bearer $ANON_KEY" \
    -H "team-token: $team1_token" \
    -H "Content-Type: application/json" \
    -d "{\"match_id\": \"$match_id\"}" > /dev/null
  curl -s -X POST "$BASE_URL/functions/v1/confirm-match" \
    -H "Authorization: Bearer $ANON_KEY" \
    -H "team-token: $team2_token" \
    -H "Content-Type: application/json" \
    -d "{\"match_id\": \"$match_id\"}" > /dev/null
done

# Test 2: Team Access
echo -e "\n2. Testing Team Access..."
curl -X GET "$BASE_URL/functions/v1/team-access" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "team-token: $TEAM_ALPHA_TOKEN" | jq .

# Test 3: Start next round
echo -e "\n3. Starting next round..."
NEXT_ROUND_RESPONSE=$(curl -s -X POST "$BASE_URL/functions/v1/start-next-round" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"tournament_id\": \"$TOURNAMENT_ID\"}")
echo $NEXT_ROUND_RESPONSE | jq .

# Test 4: Complete all matches in round 2
echo -e "\n4. Completing all matches in round 2..."
echo $NEXT_ROUND_RESPONSE | jq -c '.matches[]' | while read match; do
  match_id=$(echo $match | jq -r '.id')
  team1_id=$(echo $match | jq -r '.team1_id')
  team2_id=$(echo $match | jq -r '.team2_id')
  team1_token=$(get_team_token $team1_id)
  team2_token=$(get_team_token $team2_id)
  
  echo "Completing match $match_id (Team1: $team1_id, Team2: $team2_id)..."
  
  # Get player IDs for this match
  team1_player1=$(curl -s -X GET "$BASE_URL/rest/v1/teams?id=eq.$team1_id&select=player1_id" -H "Authorization: Bearer $ANON_KEY" | jq -r '.[0].player1_id')
  team1_player2=$(curl -s -X GET "$BASE_URL/rest/v1/teams?id=eq.$team1_id&select=player2_id" -H "Authorization: Bearer $ANON_KEY" | jq -r '.[0].player2_id')
  team2_player1=$(curl -s -X GET "$BASE_URL/rest/v1/teams?id=eq.$team2_id&select=player1_id" -H "Authorization: Bearer $ANON_KEY" | jq -r '.[0].player1_id')
  team2_player2=$(curl -s -X GET "$BASE_URL/rest/v1/teams?id=eq.$team2_id&select=player2_id" -H "Authorization: Bearer $ANON_KEY" | jq -r '.[0].player2_id')
  
  # Play 4 games
  for i in {1..4}; do
    curl -s -X POST "$BASE_URL/functions/v1/submit-scores" \
      -H "Authorization: Bearer $ANON_KEY" \
      -H "team-token: $team1_token" \
      -H "Content-Type: application/json" \
      -d "{
        \"match_id\": \"$match_id\",
        \"game_number\": $i,
        \"team1_score\": 60,
        \"team2_score\": 40,
        \"team1_total_score\": 60,
        \"team2_total_score\": 40,
        \"participants\": [
          {\"player_id\": \"$team1_player1\", \"team\": 1, \"position\": 1, \"bomb_count\": 0},
          {\"player_id\": \"$team1_player2\", \"team\": 1, \"position\": 3, \"bomb_count\": 0},
          {\"player_id\": \"$team2_player1\", \"team\": 2, \"position\": 2, \"bomb_count\": 0},
          {\"player_id\": \"$team2_player2\", \"team\": 2, \"position\": 4, \"bomb_count\": 0}
        ]
      }" > /dev/null
  done
  
  # Confirm match (both teams)
  curl -s -X POST "$BASE_URL/functions/v1/confirm-match" \
    -H "Authorization: Bearer $ANON_KEY" \
    -H "team-token: $team1_token" \
    -H "Content-Type: application/json" \
    -d "{\"match_id\": \"$match_id\"}" > /dev/null
  curl -s -X POST "$BASE_URL/functions/v1/confirm-match" \
    -H "Authorization: Bearer $ANON_KEY" \
    -H "team-token: $team2_token" \
    -H "Content-Type: application/json" \
    -d "{\"match_id\": \"$match_id\"}" > /dev/null
done

# Test 5: Finish Tournament
echo -e "\n5. Finishing Tournament..."
curl -X POST "$BASE_URL/functions/v1/finish-tournament" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"tournament_id\": \"$TOURNAMENT_ID\"}" | jq .

echo -e "\nDone!"