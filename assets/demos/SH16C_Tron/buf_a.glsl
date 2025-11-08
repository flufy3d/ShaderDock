// Created by David Bargo - davidbargo/2016
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0


// gameplay

//----------------------------------------------------------------------------------------------


const vec2 txP1PosDir        = vec2(124.0,1.0);
const vec2 txState           = vec2(124.0,3.0);
const vec2 txWins            = vec2(124.0,5.0);
const vec2 txBoosts          = vec2(124.0,7.0);
const vec2 txP2PosDir        = vec2(124.0,9.0);
const vec2 txOptions         = vec2(124.0,11.0);
const vec4 txCells           = vec4(0.0,0.0,108.0,124.0);


const float KEY_ENTER = 13.5/256.0;
const float KEY_SPACE = 32.5/256.0;
const float KEY_DEL   = 46.5/256.0;
const float KEY_LEFT  = 37.5/256.0;
const float KEY_UP    = 38.5/256.0;
const float KEY_RIGHT = 39.5/256.0;
const float KEY_DOWN  = 40.5/256.0;
const float KEY_SHIFT = 16.5/256.0;
const float KEY_A     = 65.5/256.0;
const float KEY_W     = 87.5/256.0;
const float KEY_D     = 68.5/256.0;
const float KEY_S     = 83.5/256.0;

const float speedPlayer = 60.0;
const float boostTime = 1.;
const float speedBoost = 150.0;

float map( in vec2 p ) 
{
    float x = abs(p.x - txCells.z*.5) - txCells.z*0.5;
    float y = abs(p.y - txCells.w*.5) - txCells.w*0.5;
	return x > -4. || y > -4. ? 1.:0.;
}

float hash(float seed)
{
    return fract(sin(seed)*158.5453 );
}

//----------------------------------------------------------------------------------------------

float isInside( vec2 p, vec2 c ) { vec2 d = abs(p-0.5-c) - 0.5; return -max(d.x,d.y); }
float isInside( vec2 p, vec4 c ) { vec2 d = abs(p-0.5-c.xy-c.zw*0.5) - 0.5*c.zw - 0.5; return -max(d.x,d.y); }

vec4 loadValue( in vec2 re )
{
    return texture( iChannel0, (0.5+re) / iChannelResolution[0].xy, -100.0 );
}

void storeValue( in vec2 re, in vec4 va, inout vec4 fragColor, in vec2 fragCoord )
{
    fragColor = ( isInside(fragCoord,re) > 0.0 ) ? va : fragColor;
}

void storeValue( in vec4 re, in vec4 va, inout vec4 fragColor, in vec2 fragCoord )
{
    fragColor = ( isInside(fragCoord,re) > 0.0 ) ? va : fragColor;
}

vec2 dir2dis( float dir )
{
    vec2 off = vec2(0.0);
         if( dir<0.5 ) { off = vec2( 0.0, 0.0); }
    else if( dir<1.5 ) { off = vec2( 1.0, 0.0); }
    else if( dir<2.5 ) { off = vec2(-1.0, 0.0); }
    else if( dir<3.5 ) { off = vec2( 0.0, 1.0); }
    else               { off = vec2( 0.0,-1.0); }
    return off;
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    // don't compute gameplay outside of the data area
    if( fragCoord.x > txCells.w + 1. || fragCoord.y>txCells.w + 1. ) discard;
    
    //---------------------------------------------------------------------------------   
	// load game state
	//---------------------------------------------------------------------------------
    vec4  p1PosDir        = loadValue( txP1PosDir );
    vec4  p2PosDir        = loadValue( txP2PosDir );
    float state           = loadValue( txState ).x;
    vec2  wins            = loadValue( txWins ).xy;
    float cell            = loadValue( fragCoord-0.5 ).x;
    vec4  boosts          = loadValue( txBoosts );
	vec2  options         = loadValue( txOptions ).xy;
    
    //---------------------------------------------------------------------------------
    // reset
	//---------------------------------------------------------------------------------
    if( iFrame==0 )
    {
        state = -10.0;
        options = vec2(1, 0);
    }

    if (state < -9.)
    {
        // Main Screen
        float pressEnter = texture( iChannel1, vec2(KEY_ENTER,0.25) ).x;
        if( pressEnter<0.5 && options.y > 1.5)
        {
            options.y = 0.;
        }
        else if (options.y < 1.5) 
        {
            if( pressEnter>0.5 )
            {
                state = -5.0;
            }
            else
            {

                float changeOption = texture( iChannel1, vec2(KEY_DOWN,0.25) ).x + texture( iChannel1, vec2(KEY_UP,0.25) ).x;
                if (options.y > 0.5)
                {
                    if (changeOption < 0.5) options.y = 0.;
                }
                else if( changeOption > 0.5 )
                {
                    options.x = 1. - options.x;
                    options.y = 1.;
                }
            }
        }
    }
    else
    {
        if( state<0.5 )
        {
            p1PosDir  = vec4(txCells.z/2.,13.0,0.0,3.0);
            p2PosDir  = vec4(txCells.z/2.,txCells.w - 13.0,0.0,4.0);
            boosts    = vec4(3., -1., 3., -1.);
        }

        if( state < -4. )
        {
            state          = -3.0;
            wins           =  vec2(0.);
            if( fragCoord.x<txCells.z && fragCoord.y<txCells.w ) 
                cell = map( fragCoord );

        }
        else if( state < 0.5 )
        {
            state += iTimeDelta*1.75;
            if( state >= 0. )
            {
                state = 1.0;
            }
        }
        else if( state < 1.5 ) 
        {

            // controls p1
            if( texture( iChannel1, vec2(KEY_RIGHT,0.25) ).x>0.5 && p1PosDir.w > 2.5) p1PosDir.w = 1.;
            if( texture( iChannel1, vec2(KEY_LEFT, 0.25) ).x>0.5 && p1PosDir.w > 2.5) p1PosDir.w = 2.;
            if( texture( iChannel1, vec2(KEY_UP,   0.25) ).x>0.5 && p1PosDir.w < 2.5) p1PosDir.w = 3.;
            if( texture( iChannel1, vec2(KEY_DOWN, 0.25) ).x>0.5 && p1PosDir.w < 2.5) p1PosDir.w = 4.;

            if( texture( iChannel1, vec2(KEY_SPACE, 0.25) ).x>0.5 && boosts.x > 0. && boosts.y < 0. )
            {
                boosts.x--;
                boosts.y = boostTime;
            }

			if (options.x > 0.5)
            {
                // AI
                
                float bestDir = p2PosDir.w;
                int bestCount = -1;

                for (float i = 0.; i < 4.; i++)
                {
                    float d = mod(p2PosDir.w+i - 1., 4.) + 1.;
                    vec2 destPos = p2PosDir.xy +dir2dis(d);

                    if (loadValue(destPos).x < 0.25)
                    {
                        int count = 0;
                        for (float i2 = 1.; i2 < 5.; i2++)
                        {
                            vec2 destPos2 = destPos.xy +dir2dis(i2);

                            if (loadValue(destPos2).x < 0.25)
                            {
                                for (float i3 = 1.; i3 < 5.; i3++)
                                {
                                    vec2 destPos3 = destPos2.xy +dir2dis(i3);

                                    if (loadValue(destPos3).x < 0.25)
                                    {
                                        for (float i4 = 1.; i4 < 5.; i4++)
                                        {
                                            vec2 destPos4 = destPos3.xy +dir2dis(i4);

                                            if (loadValue(destPos4).x < 0.25)
                                            {
                                                count++;
                                            }
                                        }
                                    }
                                }
                            }
                        }
						if (count == bestCount)
                        {
                            float newDist2Player = length(destPos - p1PosDir.xy);
                            float bestDist2Player = length(p2PosDir.xy +dir2dis(bestDir) - p1PosDir.xy);
                        	if (newDist2Player < bestDist2Player)
                            {
                                bestCount = count;
                            	bestDir = d;
                            }
                        }
                        else if (count > bestCount)
                        {
                            bestCount = count;
                            bestDir = d;
                        }
                    }
                }
                p2PosDir.w = bestDir;
                
                if( boosts.z > 0. && boosts.w < 0. && hash(float(iFrame)*13.1) > 0.995)
                {
                    boosts.z--;
                    boosts.w = boostTime;
                }
            }
			else
            {
                // controls p2
                if( texture( iChannel1, vec2(KEY_D    ,0.25) ).x>0.5 && p2PosDir.w > 2.5) p2PosDir.w = 1.;
                if( texture( iChannel1, vec2(KEY_A   , 0.25) ).x>0.5 && p2PosDir.w > 2.5) p2PosDir.w = 2.;
                if( texture( iChannel1, vec2(KEY_W ,   0.25) ).x>0.5 && p2PosDir.w < 2.5) p2PosDir.w = 3.;
                if( texture( iChannel1, vec2(KEY_S   , 0.25) ).x>0.5 && p2PosDir.w < 2.5) p2PosDir.w = 4.;

                if( texture( iChannel1, vec2(KEY_SHIFT, 0.25) ).x>0.5 && boosts.z > 0. && boosts.w < 0. )
                {
                    boosts.z--;
                    boosts.w = boostTime;
                }
            }

            p1PosDir.z += iTimeDelta*(boosts.y > 0. ? speedBoost : speedPlayer);
            p2PosDir.z += iTimeDelta*(boosts.w > 0. ? speedBoost : speedPlayer);
            boosts.y = max(boosts.y - iTimeDelta, -1.);
            boosts.w = max(boosts.w - iTimeDelta, -1.);

            vec2 off = dir2dis(p1PosDir.w);
            vec2 np = p1PosDir.xy + off;

            if( p1PosDir.z>=1.0 )
            {
                p1PosDir.z = 0.0;

                float c = loadValue( np ).x;
                if( c > 0.25 )
                {
                    state = 2.0;
                }
                else
                {
                    p1PosDir.xy = np;

                    float isin = isInside( fragCoord, np );
                    if( isin>0.0 ) cell = 2.;
                }
            }

            off = dir2dis(p2PosDir.w);
            np = p2PosDir.xy + off;

            if( p2PosDir.z>=1.0 )
            {
                p2PosDir.z = 0.0;

                float c = loadValue( np ).x;
                if( c > 0.25 )
                {
                    state = state > 1.5 ? 4. : 3.0;
                }
                else
                {
                    p2PosDir.xy = np;

                    float isin = isInside( fragCoord, np );
                    if( isin>0.0 ) cell = 3.;
                }
            }

            if (abs(p1PosDir.x -p2PosDir.x) < 0.5 && abs(p1PosDir.y -p2PosDir.y) < 0.5) state = 4.;

            if (state < 3.5 && state > 1.5)
            {
                if (state > 2.5) wins.x++;
                else wins.y++;
            }
        }
        else
        {
            float pressEnter = texture( iChannel1, vec2(KEY_ENTER,0.25) ).x;
            if( pressEnter>0.5 )
            {
                if (wins.x > 4.5 || wins.y > 4.5)
                {
                    options.y = 2.;
                	state = -10.;   
                }
                else
                {
                    if( fragCoord.x<txCells.z && fragCoord.y<txCells.w ) 
                        cell = map( fragCoord );
                    state = -3.0;
                }
            }
        }
        
        float pressDel = texture( iChannel1, vec2(KEY_DEL,0.25) ).x;
        if( pressDel>0.5 )
        {
            if( fragCoord.x<txCells.z && fragCoord.y<txCells.w ) 
                cell = map( fragCoord );
            state = -10.0;
            options.y = 2.;
        }
    }
  
	//---------------------------------------------------------------------------------
	// store game state
	//---------------------------------------------------------------------------------
    fragColor = vec4(0.0);
   
    storeValue( txP1PosDir,         vec4(p1PosDir),              fragColor, fragCoord );
    storeValue( txP2PosDir,         vec4(p2PosDir),              fragColor, fragCoord );
    storeValue( txState,            vec4(state,0.0,0.0,0.0),     fragColor, fragCoord );
    storeValue( txWins,             vec4(wins,0.0,0.0),          fragColor, fragCoord );
    storeValue( txCells,            vec4(cell,0.0,0.0,0.0),      fragColor, fragCoord );
    storeValue( txBoosts,           vec4(boosts),                fragColor, fragCoord );
    storeValue( txOptions,          vec4(options,0.0,0.0),       fragColor, fragCoord );
}
