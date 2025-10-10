import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    )

    const { tournament_id } = await req.json()

    // Get tournament and teams
    const { data: tournament, error: tournamentError } = await supabase
      .from('tournaments')
      .select(`
        *,
        teams(*)
      `)
      .eq('id', tournament_id)
      .single()

    if (tournamentError || !tournament) {
      throw new Error('Tournament not found')
    }

    if (tournament.status !== 'setup') {
      throw new Error('Tournament already started')
    }

    if (tournament.teams.length < 2) {
      throw new Error('Need at least 2 teams')
    }

    // Create round 1
    const { data: round, error: roundError } = await supabase
      .from('tournament_rounds')
      .insert({
        tournament_id,
        round_number: 1,
        status: 'active'
      })
      .select()
      .single()

    if (roundError) throw roundError

    // Random pairing for round 1
    const teams = [...tournament.teams]
    const matches = []
    
    // Shuffle teams randomly
    for (let i = teams.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [teams[i], teams[j]] = [teams[j], teams[i]];
    }
    
    // Pair teams
    for (let i = 0; i < teams.length; i += 2) {
      if (i + 1 < teams.length) {
        matches.push({
          round_id: round.id,
          tournament_id,
          team1_id: teams[i].id,
          team2_id: teams[i + 1].id,
          table_number: Math.floor(i / 2) + 1,
          status: 'playing'
        })
      }
    }

    // Insert matches
    const { data: insertedMatches, error: matchError } = await supabase
      .from('tournament_matches')
      .insert(matches)
      .select(`
        *,
        team1:teams!team1_id(team_name, player1_id, player2_id),
        team2:teams!team2_id(team_name, player1_id, player2_id)
      `)

    if (matchError) throw matchError

    // Update tournament status
    const { error: updateError } = await supabase
      .from('tournaments')
      .update({ 
        status: 'active', 
        current_round: 1,
        total_rounds: Math.ceil(tournament.teams.length / 2) * 2 // Simple estimate
      })
      .eq('id', tournament_id)

    if (updateError) throw updateError

    return new Response(JSON.stringify({ 
      tournament: { ...tournament, status: 'active', current_round: 1 },
      round,
      matches: insertedMatches 
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})