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

    // Check if current round is completed
    const { data: currentRound, error: roundError } = await supabase
      .from('tournament_rounds')
      .select(`
        *,
        matches:tournament_matches(id, status)
      `)
      .eq('tournament_id', tournament_id)
      .eq('round_number', tournament.current_round)
      .single()

    if (roundError && tournament.current_round > 0) {
      throw new Error('Current round not found')
    }

    // For rounds > 0, check if all matches are completed
    if (tournament.current_round > 0) {
      const incompleteMatches = currentRound.matches.filter(m => m.status !== 'completed')
      if (incompleteMatches.length > 0) {
        throw new Error('Current round not completed yet')
      }
    }

    const nextRoundNumber = tournament.current_round + 1

    // Get teams with current standings
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

    // Calculate standings
    const standings = teams.map(team => {
      let totalPoints = 0
      const playedAgainst = new Set()

      // Process matches as team1
      team.matches_as_team1.forEach(match => {
        if (match.status === 'completed') {
          playedAgainst.add(match.team2_id)
          match.games.forEach(game => {
            totalPoints += game.team1_total_score
          })
        }
      })

      // Process matches as team2
      team.matches_as_team2.forEach(match => {
        if (match.status === 'completed') {
          playedAgainst.add(match.team1_id)
          match.games.forEach(game => {
            totalPoints += game.team2_total_score
          })
        }
      })

      return {
        id: team.id,
        name: team.team_name,
        points: totalPoints,
        playedAgainst: Array.from(playedAgainst)
      }
    }).sort((a, b) => b.points - a.points)

    // Swiss system pairing
    const pairings = []
    const paired = new Set()

    for (let i = 0; i < standings.length; i++) {
      if (paired.has(standings[i].id)) continue

      const team1 = standings[i]
      let opponent = null

      // Find best opponent (closest in ranking, not played before)
      for (let j = i + 1; j < standings.length; j++) {
        const team2 = standings[j]
        if (paired.has(team2.id)) continue
        if (team1.playedAgainst.includes(team2.id)) continue

        opponent = team2
        break
      }

      if (opponent) {
        pairings.push([team1.id, opponent.id])
        paired.add(team1.id)
        paired.add(opponent.id)
      }
    }

    // Mark previous round as completed and update team points (if exists)
    if (tournament.current_round > 0) {
      const { error: updatePreviousRoundError } = await supabase
        .from('tournament_rounds')
        .update({ status: 'completed' })
        .eq('tournament_id', tournament_id)
        .eq('round_number', tournament.current_round)

      if (updatePreviousRoundError) throw updatePreviousRoundError

      // Update team total_points
      for (const team of standings) {
        const { error: updateTeamError } = await supabase
          .from('teams')
          .update({ total_points: team.points })
          .eq('id', team.id)

        if (updateTeamError) throw updateTeamError
      }
    }

    // Create new round
    const { data: newRound, error: newRoundError } = await supabase
      .from('tournament_rounds')
      .insert({
        tournament_id,
        round_number: nextRoundNumber,
        status: 'active'
      })
      .select()
      .single()

    if (newRoundError) throw newRoundError

    // Create matches
    const matches = pairings.map((pair, index) => ({
      round_id: newRound.id,
      tournament_id,
      team1_id: pair[0],
      team2_id: pair[1],
      table_number: index + 1,
      status: 'pending'
    }))

    const { data: newMatches, error: matchesError } = await supabase
      .from('tournament_matches')
      .insert(matches)
      .select()

    if (matchesError) throw matchesError

    // Update tournament current round
    const { error: updateTournamentError } = await supabase
      .from('tournaments')
      .update({ current_round: nextRoundNumber })
      .eq('id', tournament_id)

    if (updateTournamentError) throw updateTournamentError

    return new Response(JSON.stringify({ 
      success: true, 
      round: newRound,
      matches: newMatches 
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Start next round error:', error)
    const errorMessage = error?.message || error?.toString() || 'Unknown error occurred'
    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})