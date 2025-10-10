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
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization') || `Bearer ${Deno.env.get('SUPABASE_ANON_KEY')}` } } }
    )

    const teamToken = req.headers.get('team-token')
    const { game_id, team1_score, team2_score, team1_total_score, team2_total_score, participants } = await req.json()

    if (!teamToken) {
      throw new Error('Team token required')
    }

    // Verify team has access to this game
    const { data: game, error: gameError } = await supabase
      .from('games')
      .select(`
        *,
        match:tournament_matches(
          team1_id,
          team2_id,
          team1_confirmed,
          team2_confirmed,
          team1:team1_id(access_token),
          team2:team2_id(access_token)
        )
      `)
      .eq('id', game_id)
      .single()

    if (gameError || !game) {
      throw new Error('Game not found')
    }

    const hasAccess = game.match.team1.access_token === teamToken || 
                     game.match.team2.access_token === teamToken

    if (!hasAccess) {
      throw new Error('No access to this game')
    }

    if (game.match.team1_confirmed || game.match.team2_confirmed) {
      throw new Error('Match already confirmed')
    }

    // Update game scores
    const { error: gameUpdateError } = await supabase
      .from('games')
      .update({
        team1_score,
        team2_score,
        team1_total_score,
        team2_total_score
      })
      .eq('id', game_id)

    if (gameUpdateError) throw gameUpdateError

    // Update game participants (for detailed tracking)
    const participantUpdates = participants.map((p: any) => 
      supabase
        .from('game_participants')
        .upsert({
          game_id,
          player_id: p.player_id,
          team: p.team,
          position: p.position || null,
          tichu_call: p.tichu_call || false,
          grand_tichu_call: p.grand_tichu_call || false,
          tichu_success: p.tichu_success || false,
          bomb_count: p.bomb_count || 0
        })
    )

    await Promise.all(participantUpdates)

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})