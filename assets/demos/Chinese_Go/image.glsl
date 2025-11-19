#define BOARD_SIZE 19.0
#define STATE_POS vec2(20.0, 0.0)

// States
#define EMPTY 0.0
#define BLACK 1.0
#define WHITE 2.0

// Game States
#define PLAYING 0.0
#define BLACK_WINS 1.0
#define WHITE_WINS 2.0

vec4 loadValue(vec2 uv) {
    return texelFetch(iChannel0, ivec2(uv), 0);
}

// --- Font Rendering ---
vec4 drawChar(vec2 p, int c) {
    if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) return vec4(0.0);
    float cx = float(c % 16);
    float cy = float(15 - c / 16);
    vec2 uv = (vec2(cx, cy) + p) / 16.0;
    float d = texture(iChannel3, uv).x;
    return vec4(d);
}

// Procedural Stone
vec3 getStoneColor(vec2 uv, float type, vec3 lightDir) {
    float r = length(uv);
    if (r > 1.0) return vec3(0.0);
    
    float h = sqrt(max(0.0, 1.0 - r*r));
    vec3 normal = normalize(vec3(uv, h));
    
    // Pure color base
    vec3 col = (type == BLACK) ? vec3(0.05) : vec3(0.95);
    
    // Simple lighting
    float diff = max(0.0, dot(normal, lightDir));
    float spec = pow(max(0.0, dot(reflect(-lightDir, normal), vec3(0,0,1))), 30.0);
    float fresnel = pow(1.0 - max(0.0, dot(normal, vec3(0,0,1))), 4.0);
    
    if (type == BLACK) {
        col += vec3(0.3) * spec;
        col += vec3(0.1) * fresnel;
    } else {
        col *= (0.8 + 0.2 * diff);
        col += vec3(0.4) * spec;
    }
    
    return col;
}

float getShadow(vec2 uv) {
    float r = length(uv);
    return smoothstep(1.2, 0.8, r) * 0.6;
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    float minDim = min(iResolution.x, iResolution.y);
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / minDim; 
    
    vec3 lightDir = normalize(vec3(-0.5, 0.5, 1.0));
    
    // Background (Gradient Black)
    vec2 screenUV = fragCoord / iResolution.xy;
    // Radial gradient from dark gray to black
    float bgDist = length(screenUV - 0.5);
    vec3 col = mix(vec3(0.15), vec3(0.0), bgDist * 1.5);
    
    // Board Area
    float boardSize = 0.9;
    float halfBoard = boardSize * 0.5;
    
    // Board Texture (New Wood)
    vec2 boardTexUV = uv * 1.0 + 0.5;
    vec3 woodCol = texture(iChannel1, boardTexUV).rgb;
    // Adjust wood color if needed
    woodCol = pow(woodCol, vec3(1.1)); 
    
    if (abs(uv.x) < halfBoard && abs(uv.y) < halfBoard) {
        col = woodCol;
        
        vec2 boardUV = (uv + halfBoard) / boardSize; 
        vec2 gridUV = boardUV * (BOARD_SIZE - 1.0); 
        
        // Grid Lines
        vec2 gridDist = abs(fract(gridUV + 0.5) - 0.5);
        vec2 pixelDist = gridDist * (boardSize / (BOARD_SIZE - 1.0)) * minDim;
        
        float lineThickness = 1.5;
        float lineAlpha = max(
            smoothstep(lineThickness, lineThickness - 1.0, pixelDist.x),
            smoothstep(lineThickness, lineThickness - 1.0, pixelDist.y)
        );
        
        col = mix(col, vec3(0.05), lineAlpha * 0.8);
        
        // Star points
        vec2 starPoints[3];
        starPoints[0] = vec2(3, 3);
        starPoints[1] = vec2(9, 9);
        starPoints[2] = vec2(15, 15);
        
        float starDist = 100.0;
        for(int i=0; i<3; i++) {
            for(int j=0; j<3; j++) {
                vec2 p = vec2(starPoints[i].x, starPoints[j].y);
                float d = length(gridUV - p);
                starDist = min(starDist, d);
            }
        }
        float starPixelDist = starDist * (boardSize / (BOARD_SIZE - 1.0)) * minDim;
        float starMask = smoothstep(4.0, 3.0, starPixelDist);
        col = mix(col, vec3(0.0), starMask);
    }
    
    // Shadow/Edge
    vec2 d = abs(uv) - vec2(halfBoard);
    float edgeDist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    float shadow = smoothstep(0.0, 0.05, edgeDist);
    col = mix(col, col * 0.5, 1.0 - shadow); 
    
    // Stones
    vec2 boardUV = (uv + halfBoard) / boardSize;
    vec2 gridUV = boardUV * (BOARD_SIZE - 1.0);
    vec2 nearestGrid = round(gridUV);
    
    if (nearestGrid.x >= 0.0 && nearestGrid.x < BOARD_SIZE && 
        nearestGrid.y >= 0.0 && nearestGrid.y < BOARD_SIZE) {
        
        vec4 cellState = texelFetch(iChannel0, ivec2(nearestGrid), 0);
        float stone = cellState.x;
        float isLastMove = cellState.z;
        
        vec2 stonePos = (nearestGrid / (BOARD_SIZE - 1.0)) * boardSize - halfBoard;
        vec2 localUV = (uv - stonePos) / ((boardSize / (BOARD_SIZE - 1.0)) * 0.5); 
        
        if (stone != EMPTY) {
            float s = getShadow(localUV + vec2(-0.1, 0.1));
            col = mix(col, vec3(0.0), s * 0.4);
        }
        
        if (stone != EMPTY) {
            vec3 stoneCol = getStoneColor(localUV, stone, lightDir);
            float mask = smoothstep(1.0, 0.95, length(localUV));
            col = mix(col, stoneCol, mask);
            
            if (isLastMove > 0.5) {
                float r = length(localUV);
                float mark = smoothstep(0.5, 0.4, r) - smoothstep(0.3, 0.2, r);
                vec3 markCol = (stone == BLACK) ? vec3(1.0) : vec3(0.0); 
                col = mix(col, markCol, mark * mask * 0.5);
            }
        }
    }
    
    // UI
    vec4 globalState = loadValue(STATE_POS);
    float currentPlayer = globalState.x;
    float gameState = globalState.y;
    
    // Turn Indicator
    {
        // Area for Turn Indicator
        if (screenUV.x < 0.25 && screenUV.y > 0.85) {
            vec2 p = (screenUV - vec2(0.06, 0.92));
            p.x *= iResolution.x / iResolution.y;
            vec3 stoneCol = getStoneColor(p * 18.0, currentPlayer, lightDir);
            float mask = smoothstep(0.05, 0.048, length(p));
            
            float shadow = smoothstep(0.06, 0.05, length(p + vec2(0.005, -0.005)));
            col = mix(col, vec3(0.0), shadow * 0.5 * (1.0 - mask));
            col = mix(col, stoneCol, mask);
            
            vec2 textPos = screenUV - vec2(0.12, 0.905);
            textPos *= 18.0; 
            textPos.x *= iResolution.x / iResolution.y; 
            
            float txt = 0.0;
            txt += drawChar(textPos - vec2(0.0, 0.0), 84).x; 
            txt += drawChar(textPos - vec2(0.6, 0.0), 85).x; 
            txt += drawChar(textPos - vec2(1.2, 0.0), 82).x; 
            txt += drawChar(textPos - vec2(1.8, 0.0), 78).x; 
            
            float txtShadow = 0.0;
            vec2 shadowOffset = vec2(0.05, -0.05);
            txtShadow += drawChar(textPos - vec2(0.0, 0.0) - shadowOffset, 84).x;
            txtShadow += drawChar(textPos - vec2(0.6, 0.0) - shadowOffset, 85).x;
            txtShadow += drawChar(textPos - vec2(1.2, 0.0) - shadowOffset, 82).x;
            txtShadow += drawChar(textPos - vec2(1.8, 0.0) - shadowOffset, 78).x;
            
            col = mix(col, vec3(0.0), txtShadow * 0.5);
            col = mix(col, vec3(1.0), txt);
        }
    }
    
    // Resign Button
    {
        if (screenUV.x > 0.82 && screenUV.y > 0.88) {
            vec2 p = (screenUV - vec2(0.91, 0.94));
            p.x *= iResolution.x / iResolution.y;
            
            vec2 b = vec2(0.08, 0.035);
            vec2 d = abs(p) - b;
            float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 0.01;
            float btnMask = smoothstep(0.005, 0.0, dist);
            
            vec3 btnCol = mix(vec3(0.6, 0.1, 0.1), vec3(0.8, 0.2, 0.2), p.y * 10.0 + 0.5);
            col = mix(col, btnCol, btnMask);
            
            float border = smoothstep(0.0, 0.005, abs(dist));
            col = mix(col, vec3(0.9, 0.3, 0.3), btnMask * (1.0 - border));
            
            vec2 textPos = (screenUV - vec2(0.86, 0.925)) * 22.0;
            textPos.x *= iResolution.x / iResolution.y; 
            
            float txt = 0.0;
            txt += drawChar(textPos - vec2(0.0, 0.0), 82).x;
            txt += drawChar(textPos - vec2(0.6, 0.0), 69).x;
            txt += drawChar(textPos - vec2(1.2, 0.0), 83).x;
            txt += drawChar(textPos - vec2(1.8, 0.0), 73).x;
            txt += drawChar(textPos - vec2(2.2, 0.0), 71).x;
            txt += drawChar(textPos - vec2(2.8, 0.0), 78).x;
            
            col = mix(col, vec3(1.0), txt * btnMask);
        }
    }
    
    // Game Over
    if (gameState != PLAYING) {
        col = mix(col, vec3(0.0), 0.7);
        
        vec3 winCol = getStoneColor(uv * 2.0, (gameState == BLACK_WINS) ? BLACK : WHITE, lightDir);
        float mask = smoothstep(0.5, 0.49, length(uv));
        col = mix(col, winCol, mask);
        
        vec2 textPos = uv + vec2(0.2, -0.3); 
        textPos *= 8.0;
        
        float txt = 0.0;
        txt += drawChar(textPos - vec2(0,0), 87).x;
        txt += drawChar(textPos - vec2(0.8,0), 73).x;
        txt += drawChar(textPos - vec2(1.2,0), 78).x;
        txt += drawChar(textPos - vec2(2.0,0), 83).x;
        
        col = mix(col, vec3(1.0), txt);
    }

    fragColor = vec4(col, 1.0);
}
