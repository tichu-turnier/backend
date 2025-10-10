#!/bin/bash

echo "Logging in test user..."
RESPONSE=$(curl -s -X POST "http://localhost:54321/auth/v1/token?grant_type=password" \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "testpassword123"
  }')

echo "Response:"
echo $RESPONSE | jq .

JWT_TOKEN=$(echo $RESPONSE | jq -r '.access_token')
echo ""
echo "Exporting JWT_TOKEN environment variable..."
export JWT_TOKEN
echo "JWT_TOKEN=$JWT_TOKEN"
echo ""
echo "Run: source ./testing/login-test-user.sh"