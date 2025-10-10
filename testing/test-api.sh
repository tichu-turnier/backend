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

# Test 1.1: Create Players
echo -e "\n1.1 Creating Players..."
curl -s -X POST "$BASE_URL/rest/v1/players" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
  -H "Content-Type: application/json" \
  -d '[{"name": "Alice"}, {"name": "Bob"}, {"name": "Charlie"}, {"name": "Diana"}]' | jq .

# Test 1.2: Create Team
echo -e "\n1.2 Creating Team..."
PLAYER1_ID=$(curl -s -X GET "$BASE_URL/rest/v1/players?name=eq.Alice&select=id" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" | jq -r '.[0].id')
PLAYER2_ID=$(curl -s -X GET "$BASE_URL/rest/v1/players?name=eq.Bob&select=id" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" | jq -r '.[0].id')

PLAYER3_ID=$(curl -s -X GET "$BASE_URL/rest/v1/players?name=eq.Charlie&select=id" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" | jq -r '.[0].id')
PLAYER4_ID=$(curl -s -X GET "$BASE_URL/rest/v1/players?name=eq.Diana&select=id" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXhjNni43kdQwgnWNReilDMblYTn_I0" | jq -r '.[0].id')

TEAM_RESPONSE=$(curl -s -X POST "$BASE_URL/rest/v1/teams" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d "[{\"tournament_id\": \"$TOURNAMENT_ID\", \"team_name\": \"Team Alpha\", \"player1_id\": \"$PLAYER1_ID\", \"player2_id\": \"$PLAYER2_ID\"}, {\"tournament_id\": \"$TOURNAMENT_ID\", \"team_name\": \"Team Beta\", \"player1_id\": \"$PLAYER3_ID\", \"player2_id\": \"$PLAYER4_ID\"}]")
echo $TEAM_RESPONSE | jq .
TEAM1_ID=$(echo $TEAM_RESPONSE | jq -r '.[0].id')
TEAM2_ID=$(echo $TEAM_RESPONSE | jq -r '.[1].id')
TEAM_TOKEN=$(echo $TEAM_RESPONSE | jq -r '.[0].access_token')
echo "Team 1 Token: $TEAM_TOKEN"

# Test 1.3: Start Tournament (generates pairings)
echo -e "\n1.3 Starting Tournament..."
START_RESPONSE=$(curl -s -X POST "$BASE_URL/functions/v1/start-tournament" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"tournament_id\": \"$TOURNAMENT_ID\"}")
echo $START_RESPONSE | jq .
MATCH_ID=$(echo $START_RESPONSE | jq -r '.matches[0].id')

# Test 1.4: Create Game for the match
echo -e "\n1.4 Creating Game..."
GAME_RESPONSE=$(curl -s -X POST "$BASE_URL/rest/v1/games" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d "[{\"match_id\": \"$MATCH_ID\", \"game_number\": 1}]")
echo $GAME_RESPONSE | jq .
GAME_ID=$(echo $GAME_RESPONSE | jq -r '.[0].id')



# Test 2: Team Access
echo -e "\n2. Testing Team Access..."
curl -X GET "$BASE_URL/functions/v1/team-access" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "team-token: $TEAM_TOKEN" | jq .

# Test 3: Submit Scores
echo -e "\n3. Submitting Scores..."
curl -X POST "$BASE_URL/functions/v1/submit-scores" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "team-token: $TEAM_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"game_id\": \"$GAME_ID\",
    \"team1_score\": 100,
    \"team2_score\": 80,
    \"team1_total_score\": 120,
    \"team2_total_score\": 90,
    \"participants\": [
      {
        \"player_id\": \"$PLAYER1_ID\",
        \"team\": 1,
        \"position\": 1,
        \"tichu_call\": true,
        \"tichu_success\": true,
        \"bomb_count\": 2
      },
      {
        \"player_id\": \"$PLAYER2_ID\",
        \"team\": 1,
        \"position\": 3,
        \"bomb_count\": 1
      },
      {
        \"player_id\": \"$PLAYER3_ID\",
        \"team\": 2,
        \"position\": 2,
        \"bomb_count\": 0
      },
      {
        \"player_id\": \"$PLAYER4_ID\",
        \"team\": 2,
        \"position\": 4,
        \"bomb_count\": 0
      }
    ]
  }" | jq .

echo -e "\nDone!"