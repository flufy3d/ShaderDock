// Created by David Bargo - davidbargo/2016
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0


// rendering

const vec2 txP1PosDir    = vec2(124.0,1.0);
const vec2 txState       = vec2(124.0,3.0);
const vec2 txWins        = vec2(124.0,5.0);
const vec2 txBoosts      = vec2(124.0,7.0);
const vec2 txP2PosDir    = vec2(124.0,9.0);
const vec4 txCells       = vec4(0.0,0.0,108.0,124.0);

const vec3 p1Color       = vec3(1.,0.9,0.2);
const vec3 p2Color       = vec3(.0,0.9,1.);

//============================================================

float sdBox( vec2 p, vec2 b )
{
  vec2 d = abs(p) - b;
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}

float sdCircle( in vec2 p, in float r )
{
    return length( p ) - r;
}

float sdDonut(vec2 pos, float radius, float width)
{
    return abs(length(pos)-radius)-width;   
}

vec2 rot(vec2 p, float a)
{
    float c = cos(a);
    float s = sin(a);
	return p * mat2(c, -s, s, c);
}

float merge(float d1, float d2)
{
	return min(d1, d2);
}

float substract(float d1, float d2)
{
	return max(-d1, d2);
}

float intersect(float d1, float d2)
{
	return max(d1, d2);
}

float fillMask(float dist)
{
	return clamp(-(dist+0.01)*100.0, 0.0, 1.0);
}

float innerBorderMask(float dist, float width)
{
	float alpha1 = clamp(dist + width, 0.0, 1.0);
	float alpha2 = clamp(dist, 0.0, 1.0);
	return alpha1 - alpha2;
}


//============================================================

vec4 loadValue( in vec2 re )
{
    return texture( iChannel0, (0.5+re) / iChannelResolution[0].xy, -100.0 );
}

//============================================================

float IsGridLine(vec2 fragCoord)
{
	vec2 vPixelsPerGridSquare = vec2(32.0, 32.0);
	
	vec2 vScreenPixelCoordinate = fragCoord.xy;
	
	vec2 vGridSquareCoords = fract(vScreenPixelCoordinate / vPixelsPerGridSquare);

	vec2 vGridSquarePixelCoords = vGridSquareCoords * vPixelsPerGridSquare;

	vec2 vIsGridLine = step(vGridSquarePixelCoords, vec2(2.3));
	
	float fIsGridLine = max(vIsGridLine.x, vIsGridLine.y);

	return fIsGridLine;
}

vec3 drawMap( vec3 col, in vec2 fragCoord )
{
    vec2 uv = fragCoord.xy /iResolution.xy;
    float xCells = txCells.w*(iResolution.x / iResolution.y);
    vec2 p = uv-vec2(0.5-txCells.z/(xCells*2.), 0.); // center
    p.x *= iResolution.x / iResolution.y;
    
    vec2 q = floor(p*txCells.w);
    vec2 r = fract(p*txCells.w);

    vec2 l = vec2((15.*fragCoord-iResolution.xy)/iResolution.y);
    l.x -= 0.55; l.y -= 0.5;
    l = abs(fract(l) - 0.5) - 0.25;
    l = step(0.0, l)*l*4.0;
    l *= l; l *= l; l *= l;
    l = 1. - l;
    float val = 1.0 - l.x*l.y;
    
    vec3 bg = mix(vec3(0., 0.1, 0.15), vec3(1.), val);
    col += bg*step(0., p.x)*step(p.x, txCells.z/txCells.w);
    if( q.x>=0.0 && q.x<=txCells.z )
    {
        float c = texture( iChannel0, (q+0.5)/iResolution.xy, -100.0 ).x;
        if( c>0.5 )
        {            
            float d = sdBox(r-0.5, vec2(1.));
            float f = 1.0 - smoothstep( -0.01, 0.01, d );
            
            vec3 wco = c > 2.5 ? p2Color :
            		   c > 1.5 ? p1Color : vec3(0.25);
            col = mix( col, wco, f );
            //col += 0.15*vec3(1.0,0.8,0.0)*exp(-1500.0*d*d);
        }
    }
    return col;
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


vec2 cell2ndc( vec2 c )
{
	c = (c+0.5) / txCells.w;
    return c;
}


vec3 drawPlayer( vec3 col, in vec2 fragCoord, float player, in vec4 playerPosDir, bool dead )
{
    vec2 off = dir2dis(playerPosDir.w);    
    vec2 mPlayerPos = playerPosDir.xy + off*playerPosDir.z;

    vec2 uv = fragCoord.xy /iResolution.xy;
    float xCells = txCells.w*(iResolution.x / iResolution.y);
    vec2 p = uv-vec2(0.5-txCells.z/(xCells*2.), 0.); // center
    p.x *= iResolution.x / iResolution.y;
    
    vec2 q = p - cell2ndc( mPlayerPos );

    float c = sdCircle(q, 0.023);

    vec3 color = mix(p1Color, p2Color, player - 1.);
    
    float phase = 0.5+0.5*sin(2.0*6.2831*iTime);
    if (dead) color = mix(color, vec3(1., 0., 0.), phase);
    col += 0.1*color*exp((-100.0 - (dead ? 50.*phase : 0.))*c);

    return col;
}


#define PI 3.141592
vec3 drawMainTitle(vec3 col, vec2 fragCoord)
{    
    vec2 uv = fragCoord.xy /iResolution.xy;
    vec2 p = -1. + 2.*uv;
    p.x *= iResolution.x / iResolution.y;
    
    p *= 120.;
    
    // green lines
    float f = abs((p.x)-32.);
    f = min(f, abs((p.y)-48.));
    col += vec3(0.,0.8,0.3)*exp(-1.5*f);
    
    p += vec2(130, -80);

    // T
    float d = sdBox(p + vec2(-32, 8), vec2(32, 8));
    d = merge(d,  sdBox(p + vec2(-32, 32), vec2(16, 32)));
    
    // R
    p.x -= 65.;
    d = merge(d,  sdBox(p + vec2(-8, 16+32), vec2(8, 16)));
    float r = sdBox(p + vec2(-26-16, 16+32), vec2(26, 16));
    r = intersect(r, sdBox(rot(p + vec2(-30-12, 12+36), PI/3.7), vec2(30, 8)));
	d = merge(d, r);
    
    d = merge(d, sdBox(p + vec2(-12 -8, 8),     vec2(12, 8)));
    d = merge(d, sdCircle(p + vec2(-12. -19., 8),     8.));
    d = merge(d, sdCircle(p + vec2(-12. -21., 8),     8.));
        
    r = sdDonut(p + vec2(-32, 32), 24., 8.);
    r = intersect(r, sdBox(p + vec2(-32 - 16, 16),         vec2(16, 16)));
        
    d = merge(d, r);
    
    // O
    p.x -= 65.;
    d = merge(d, sdDonut(p - vec2(32, -32), 24., 8.));
    
    // N
    p.x -= 65.;
    float nc = sdBox(rot(p + vec2(-32-13, 0), PI/4.), vec2(64, 32));
    float nd = sdBox(p + vec2(-32 , 32),         vec2(32, 32));
    r = substract(sdBox(p + vec2(-32-16 , 32+18), vec2(32, 18)), substract(nc, nd));
    d = merge(d, r);
    r = substract(sdBox(p, vec2(32+16, 32)), intersect(nc, nd));
    d = merge(d, r);
    
    
    vec3 fontColor = mix(vec3(0., 0., 0.02), vec3(0., 0.5, 0.7), smoothstep(-32., -48., p.y));
    fontColor = mix(fontColor, vec3(1.), smoothstep(-40., -56., p.y));
	col = mix(col, fontColor, fillMask(d));
	col = mix(col, vec3(.9,0,0), innerBorderMask(d, 2.));
    
    return col;
}

//============================================================

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    //------------------------
    // load game state
    //------------------------
       
    vec4  p1PosDir  = loadValue( txP1PosDir );
    vec4  p2PosDir  = loadValue( txP2PosDir );
    float state     = loadValue( txState ).x;
    vec2  wins      = loadValue( txWins ).xy;
	vec2  boosts    = loadValue( txBoosts ).xz;

    //------------------------
    // render
    //------------------------
    vec3 col = vec3(0.0);
    
    if (state < -9.)
    {
        col = drawMainTitle(col, fragCoord);
    }
    else 
    {
        // map
        col = drawMap( col, fragCoord );

        // players
        col = drawPlayer( col, fragCoord, 1., p1PosDir, (state > 1.5 && state < 2.5) || state > 3.5 );
        col = drawPlayer( col, fragCoord, 2., p2PosDir, state > 2.5 );
    }
    
	fragColor = vec4( col, 1.0 );
}
