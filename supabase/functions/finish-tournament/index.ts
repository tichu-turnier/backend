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

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      throw new Error('Authorization required')
    }

    const { tournament_id } = await req.json()

    if (!tournament_id) {
      throw new Error('Tournament ID required')
    }

    // Verify tournament ownership
    const { data: tournament, error: tournamentError } = await supabase
      .from('tournaments')
      .select('*')
      .eq('id', tournament_id)
      .single()

    if (tournamentError || !tournament) {
      throw new Error('Tournament not found')
    }

    if (tournament.status === 'completed') {
      throw new Error('Tournament already completed')
    }

    // Get teams with final standings
    const { data: teams, error: teamsError } = await supabase
      .from('teams')
      .select(`
        *,
        matches_as_team1:tournament_matches!team1_id(
          id, status, team1_id, team2_id,
          games(team1_total_score, team2_total_score)
        ),
        matches_as_team2:tournament_matches!team2_id(
          id, status, team1_id, team2_id,
          games(team1_total_score, team2_total_score)
        )
      `)
      .eq('tournament_id', tournament_id)

    if (teamsError) throw teamsError

    // Calculate final standings
    const finalStandings = teams.map(team => {
      let totalPoints = 0

      // Process matches as team1
      team.matches_as_team1.forEach(match => {
        if (match.status === 'completed') {
          match.games.forEach(game => {
            totalPoints += game.team1_total_score
          })
        }
      })

      // Process matches as team2
      team.matches_as_team2.forEach(match => {
        if (match.status === 'completed') {
          match.games.forEach(game => {
            totalPoints += game.team2_total_score
          })
        }
      })

      return {
        team_id: team.id,
        team_name: team.team_name,
        total_points: totalPoints
      }
    }).sort((a, b) => b.total_points - a.total_points)
      .map((team, index) => ({ ...team, rank: index + 1 }))

    // Mark current round as completed and update team points
    if (tournament.current_round > 0) {
      const { error: updateRoundError } = await supabase
        .from('tournament_rounds')
        .update({ status: 'completed' })
        .eq('tournament_id', tournament_id)
        .eq('round_number', tournament.current_round)

      if (updateRoundError) throw updateRoundError
    }

    // Update team total_points with final standings
    for (const team of finalStandings) {
      const { error: updateTeamError } = await supabase
        .from('teams')
        .update({ total_points: team.total_points })
        .eq('id', team.team_id)

      if (updateTeamError) throw updateTeamError
    }

    // Mark tournament as completed
    const { data: updatedTournament, error: updateTournamentError } = await supabase
      .from('tournaments')
      .update({ status: 'completed' })
      .eq('id', tournament_id)
      .select()
      .single()

    if (updateTournamentError) throw updateTournamentError

    return new Response(JSON.stringify({ 
      success: true, 
      tournament: updatedTournament,
      final_standings: finalStandings
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Finish tournament error:', error)
    const errorMessage = error?.message || error?.toString() || 'Unknown error occurred'
    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})