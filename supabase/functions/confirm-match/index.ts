import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, team-token',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!serviceRoleKey) {
      throw new Error('SUPABASE_SERVICE_ROLE_KEY not found')
    }
    
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      serviceRoleKey,
      {
        global: {
          headers: {
            Authorization: `Bearer ${serviceRoleKey}`
          }
        }
      }
    )

    const teamToken = req.headers.get('team-token')
    const { match_id, unconfirm } = await req.json()

    if (!teamToken) {
      throw new Error('Team token required')
    }

    if (!match_id) {
      throw new Error('Match ID required')
    }

    // Get match with team info and games count
    const { data: match, error: matchError } = await supabase
      .from('tournament_matches')
      .select(`
        *,
        team1:team1_id(access_token),
        team2:team2_id(access_token),
        games(id)
      `)
      .eq('id', match_id)
      .single()

    if (matchError || !match) {
      throw new Error('Match not found')
    }

    // Verify team access
    const isTeam1 = match.team1.access_token === teamToken
    const isTeam2 = match.team2.access_token === teamToken
    
    if (!isTeam1 && !isTeam2) {
      throw new Error('No access to this match')
    }

    let updateData = {}
    
    if (unconfirm) {
      // Unconfirm: Remove confirmation and reopen match
      updateData.status = 'playing'
      updateData.completed_at = null
      if (isTeam1) {
        updateData.team1_confirmed = false
      } else {
        updateData.team2_confirmed = false
      }
    } else {
      // Check if all 4 games are played
      if (match.games.length !== 4) {
        throw new Error('All 4 games must be completed before confirmation')
      }

      // Update confirmation status
      if (isTeam1) {
        updateData.team1_confirmed = true
      } else {
        updateData.team2_confirmed = true
      }

      // Check if both teams will be confirmed after this update
      const team1WillBeConfirmed = isTeam1 ? true : match.team1_confirmed
      const team2WillBeConfirmed = isTeam2 ? true : match.team2_confirmed
      
      if (team1WillBeConfirmed && team2WillBeConfirmed) {
        updateData.status = 'completed'
        updateData.completed_at = new Date().toISOString()
      }
    }

    const { error: updateError } = await supabase
      .from('tournament_matches')
      .update(updateData)
      .eq('id', match_id)

    if (updateError) throw updateError

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Confirm match error:', error)
    const errorMessage = error?.message || error?.toString() || 'Unknown error occurred'
    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})