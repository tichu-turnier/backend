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
    const { game_id, match_id, game_number, team1_score, team2_score, team1_total_score, team2_total_score, participants, team1_double_win, team2_double_win, beschiss, notes } = await req.json()

    if (!teamToken) {
      throw new Error('Team token required')
    }

    // For new games, match_id and game_number are required
    // For existing games, game_id is required
    if (!game_id && (!match_id || !game_number)) {
      throw new Error('Either game_id or both match_id and game_number are required')
    }

    if (game_number && (game_number < 1 || game_number > 4)) {
      throw new Error('Game number must be between 1 and 4')
    }

    let game, matchData
    
    if (game_id) {
      // Update existing game
      const { data: existingGame, error: gameError } = await supabase
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

      if (gameError || !existingGame) {
        throw new Error('Game not found')
      }
      
      game = existingGame
      matchData = existingGame.match
    } else {
      // Create new game - verify match access first
      const { data: match, error: matchError } = await supabase
        .from('tournament_matches')
        .select(`
          *,
          team1:team1_id(access_token),
          team2:team2_id(access_token)
        `)
        .eq('id', match_id)
        .single()

      if (matchError || !match) {
        throw new Error('Match not found')
      }
      
      matchData = match
      
      // Check for duplicate game_number
      const { data: existingGames, error: duplicateError } = await supabase
        .from('games')
        .select('id')
        .eq('match_id', match_id)
        .eq('game_number', game_number)

      if (duplicateError) throw duplicateError
      if (existingGames && existingGames.length > 0) {
        throw new Error(`Game number ${game_number} already exists for this match`)
      }
    }

    // Verify team access
    const hasAccess = matchData.team1.access_token === teamToken || 
                     matchData.team2.access_token === teamToken

    if (!hasAccess) {
      throw new Error('No access to this match')
    }

    if (matchData.team1_confirmed || matchData.team2_confirmed) {
      throw new Error('Match already confirmed')
    }

    // Validate Tichu game rules
    if (participants.length !== 4) {
      throw new Error('Exactly 4 participants required')
    }

    // Validate all participants have player_id
    participants.forEach((p: any, index: number) => {
      if (!p.player_id) {
        throw new Error(`Player ID missing for participant ${index + 1}`)
      }
    })

    const positions = participants.map((p: any) => p.position).filter((pos: any) => pos !== null)
    const uniquePositions = new Set(positions)
    
    // Check for double win scenario
    const firstPlace = participants.find((p: any) => p.position === 1)
    const secondPlace = participants.find((p: any) => p.position === 2)
    const isDoubleWin = firstPlace && secondPlace && firstPlace.team === secondPlace.team
    
    // Validate positions
    if (isDoubleWin) {
      // Double win: only positions 1 and 2 should be set
      if (positions.length !== 2 || !uniquePositions.has(1) || !uniquePositions.has(2)) {
        throw new Error('For double win games, only positions 1 and 2 should be set')
      }
      // Positions 3 and 4 should be null
      const nullPositions = participants.filter((p: any) => p.position === null)
      if (nullPositions.length !== 2) {
        throw new Error('For double win games, positions 3 and 4 must be null')
      }
    } else {
      // Normal game: all positions 1-4 must be set and unique
      if (positions.length !== 4 || uniquePositions.size !== 4 || ![1, 2, 3, 4].every(n => uniquePositions.has(n))) {
        throw new Error('For normal games, positions must be unique and between 1 and 4')
      }
    }

    // Validate team assignments (2 players per team)
    const team1Players = participants.filter((p: any) => p.team === 1)
    const team2Players = participants.filter((p: any) => p.team === 2)
    if (team1Players.length !== 2 || team2Players.length !== 2) {
      throw new Error('Each team must have exactly 2 players')
    }
    
    if (isDoubleWin) {
      // Double win: base scores should be 0, only bonus points count
      if (team1_score !== 0 || team2_score !== 0) {
        throw new Error('Base scores must be 0 for double win games')
      }
      // Verify double win flags match the positions
      const winningTeam = firstPlace.team
      if ((winningTeam === 1 && !team1_double_win) || (winningTeam === 2 && !team2_double_win)) {
        throw new Error('Double win flag does not match positions')
      }
    } else {
      // No double win: base scores should sum to 100
      if (team1_score + team2_score !== 100) {
        throw new Error('Base scores must sum to 100 for non-double-win games')
      }
      if (team1_double_win || team2_double_win) {
        throw new Error('No double win occurred but double win flag is set')
      }
    }

    // Validate Tichu calls and bomb counts
    participants.forEach((p: any) => {
      // Player can only call either small OR grand tichu, not both
      if (p.tichu_call && p.grand_tichu_call) {
        throw new Error('Player cannot call both small and grand tichu')
      }
      // Tichu success validation
      if (p.tichu_success && !p.tichu_call && !p.grand_tichu_call) {
        throw new Error('Tichu success flag set but no tichu call made')
      }
      if ((p.tichu_call || p.grand_tichu_call) && p.tichu_success && p.position !== 1) {
        throw new Error('Tichu can only be successful if player finished 1st')
      }
      // Validate bomb count
      const bombCount = p.bomb_count || 0
      if (bombCount < 0 || bombCount > 3) {
        throw new Error('Bomb count must be between 0 and 3')
      }
    })

    // Validate bonus point calculations
    let expectedTeam1Bonus = 0
    let expectedTeam2Bonus = 0

    // Calculate expected tichu bonuses
    participants.forEach((p: any) => {
      const team = p.team
      if (p.tichu_call && p.tichu_success) {
        if (team === 1) expectedTeam1Bonus += 100
        else expectedTeam2Bonus += 100
      } else if (p.tichu_call && !p.tichu_success) {
        if (team === 1) expectedTeam1Bonus -= 100
        else expectedTeam2Bonus -= 100
      }
      
      if (p.grand_tichu_call && p.tichu_success) {
        if (team === 1) expectedTeam1Bonus += 200
        else expectedTeam2Bonus += 200
      } else if (p.grand_tichu_call && !p.tichu_success) {
        if (team === 1) expectedTeam1Bonus -= 200
        else expectedTeam2Bonus -= 200
      }
    })

    // Add double win bonus
    if (isDoubleWin) {
      const winningTeam = firstPlace.team
      if (winningTeam === 1) expectedTeam1Bonus += 200
      else expectedTeam2Bonus += 200
    }

    // Calculate expected total scores
    const expectedTeam1Total = (isDoubleWin ? 0 : team1_score) + expectedTeam1Bonus
    const expectedTeam2Total = (isDoubleWin ? 0 : team2_score) + expectedTeam2Bonus

    // Validate total scores match expected calculations
    if (team1_total_score !== expectedTeam1Total) {
      throw new Error(`Team 1 total score incorrect. Expected ${expectedTeam1Total}, got ${team1_total_score}`)
    }
    if (team2_total_score !== expectedTeam2Total) {
      throw new Error(`Team 2 total score incorrect. Expected ${expectedTeam2Total}, got ${team2_total_score}`)
    }

    // Upsert game scores
    const gameData = {
      team1_score,
      team2_score,
      team1_total_score,
      team2_total_score,
      team1_double_win: team1_double_win || false,
      team2_double_win: team2_double_win || false,
      beschiss: beschiss || false,
      notes: notes || null
    }
    
    if (game_id) {
      gameData.id = game_id
      // For updates, also include match_id and game_number to avoid null constraint violations
      gameData.match_id = game.match_id
      gameData.game_number = game.game_number
    } else {
      gameData.match_id = match_id
      gameData.game_number = game_number
    }

    const { data: upsertedGame, error: gameUpsertError } = await supabase
      .from('games')
      .upsert(gameData)
      .select('id')
      .single()

    if (gameUpsertError) throw gameUpsertError
    
    const finalGameId = game_id || upsertedGame.id

    // Update game participants (for detailed tracking)
    if (game_id) {
      // For updates, delete existing participants first to avoid conflicts
      await supabase
        .from('game_participants')
        .delete()
        .eq('game_id', finalGameId)
    }
    
    const participantUpdates = participants.map((p: any) => 
      supabase
        .from('game_participants')
        .insert({
          game_id: finalGameId,
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
    console.error('Submit scores error:', error)
    const errorMessage = error?.message || error?.toString() || 'Unknown error occurred'
    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})