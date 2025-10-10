#!/bin/bash

echo "Creating test user..."
RESPONSE=$(curl -s -X POST "http://localhost:54321/auth/v1/signup" \
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
echo "Your JWT Token:"
echo $JWT_TOKEN
echo ""
echo "Copy this token to your test-api.sh file!"