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
    if (!teamToken) {
      throw new Error('Team token required')
    }

    // Verify team token and get team data
    const { data: team, error } = await supabase
      .from('teams')
      .select(`
        *,
        tournament:tournaments(*)
      `)
      .eq('access_token', teamToken)
      .single()

    if (error || !team) {
      throw new Error('Invalid team token')
    }

    return new Response(JSON.stringify(team), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})