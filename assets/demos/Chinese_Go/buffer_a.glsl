#define BOARD_SIZE 19
#define STATE_POS vec2(20.0, 0.0)

// States
#define EMPTY 0.0
#define BLACK 1.0
#define WHITE 2.0

// Game States
#define PLAYING 0.0
#define BLACK_WINS 1.0
#define WHITE_WINS 2.0

// Helper to read texture
vec4 loadValue(vec2 uv) {
    return texelFetch(iChannel0, ivec2(uv), 0);
}

// Get stone color at position
float getStone(ivec2 p) {
    return texelFetch(iChannel0, p, 0).x;
}

// Check if a point is on the board
bool onBoard(ivec2 p) {
    return p.x >= 0 && p.x < BOARD_SIZE && p.y >= 0 && p.y < BOARD_SIZE;
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    ivec2 iFragCoord = ivec2(fragCoord);
    
    // Initialize
    if (iFrame == 0) {
        fragColor = vec4(0.0);
        if (iFragCoord == ivec2(STATE_POS)) {
            fragColor = vec4(BLACK, PLAYING, 0.0, 0.0); 
        }
        return;
    }
    
    // Default: Keep previous state
    vec4 data = loadValue(fragCoord);
    fragColor = data;
    
    vec4 globalState = loadValue(STATE_POS);
    float currentPlayer = globalState.x;
    float gameState = globalState.y;
    
    if (gameState != PLAYING) {
        // Allow reset?
        return;
    }
    
    // Input Handling
    vec4 lastMouse = loadValue(STATE_POS + vec2(1.0, 0.0));
    bool isNewClick = (iMouse.z > 0.0) && (iMouse.zw != lastMouse.zw);
    
    // Update Global State
    if (iFragCoord == ivec2(STATE_POS)) {
        if (isNewClick) {
            float minDim = min(iResolution.x, iResolution.y);
            vec2 uv = (iMouse.xy - 0.5 * iResolution.xy) / minDim;
            float boardSize = 0.9;
            vec2 boardUV = (uv + boardSize * 0.5) / boardSize;
            
            // Resign Check
            vec2 screenUV = iMouse.xy / iResolution.xy;
            if (screenUV.x > 0.85 && screenUV.y > 0.9) {
                fragColor = vec4(currentPlayer, (currentPlayer == BLACK) ? WHITE_WINS : BLACK_WINS, 0.0, 0.0);
                return;
            }
            
            // Move Check
            if (boardUV.x >= 0.0 && boardUV.x <= 1.0 && boardUV.y >= 0.0 && boardUV.y <= 1.0) {
                vec2 gridUV = boardUV * (float(BOARD_SIZE) - 1.0);
                ivec2 boardPos = ivec2(round(gridUV));
                vec2 dist = abs(gridUV - vec2(boardPos));
                if (length(dist) < 0.4) { 
                    if (onBoard(boardPos)) {
                        if (getStone(boardPos) == EMPTY) {
                            fragColor = vec4((currentPlayer == BLACK) ? WHITE : BLACK, PLAYING, 0.0, 0.0);
                            return;
                        }
                    }
                }
            }
        }
        return;
    }
    
    // Update Last Mouse
    if (iFragCoord == ivec2(STATE_POS + vec2(1.0, 0.0))) {
        fragColor = iMouse;
        return;
    }
    
    // Board Update
    if (onBoard(iFragCoord)) {
        if (isNewClick) {
            float minDim = min(iResolution.x, iResolution.y);
            vec2 uv = (iMouse.xy - 0.5 * iResolution.xy) / minDim;
            float boardSize = 0.9;
            vec2 boardUV = (uv + boardSize * 0.5) / boardSize;
            
            // Resign Check
            vec2 screenUV = iMouse.xy / iResolution.xy;
            if (screenUV.x > 0.85 && screenUV.y > 0.9) {
                return;
            }
            
            if (boardUV.x >= 0.0 && boardUV.x <= 1.0 && boardUV.y >= 0.0 && boardUV.y <= 1.0) {
                vec2 gridUV = boardUV * (float(BOARD_SIZE) - 1.0);
                ivec2 movePos = ivec2(round(gridUV));
                vec2 dist = abs(gridUV - vec2(movePos));
                
                if (length(dist) < 0.4) {
                    if (getStone(movePos) == EMPTY) {
                        // 1. Place Stone
                        if (iFragCoord == movePos) {
                            fragColor = vec4(currentPlayer, 0.0, 1.0, 0.0);
                            return;
                        }
                        
                        // 2. Capture Logic
                        if (data.x != EMPTY && data.x != currentPlayer) {
                             ivec2 startPos = iFragCoord;
                             float myColor = data.x;
                             
                             ivec2 stack[60];
                             int stackTop = 0;
                             stack[stackTop++] = startPos;
                             
                             ivec2 visited[60];
                             int visitedCount = 0;
                             visited[visitedCount++] = startPos;
                             
                             bool foundLiberty = false;
                             int safety = 0;
                             
                             while(stackTop > 0 && safety < 100) {
                                 safety++;
                                 ivec2 p = stack[--stackTop];
                                 
                                 ivec2 neighbors[4];
                                 neighbors[0] = p + ivec2(1, 0);
                                 neighbors[1] = p + ivec2(-1, 0);
                                 neighbors[2] = p + ivec2(0, 1);
                                 neighbors[3] = p + ivec2(0, -1);
                                 
                                 for(int i=0; i<4; i++) {
                                     ivec2 n = neighbors[i];
                                     if (!onBoard(n)) continue;
                                     if (n == movePos) continue; 
                                     
                                     float s = getStone(n);
                                     if (s == EMPTY) {
                                         foundLiberty = true;
                                         break;
                                     }
                                     
                                     if (s == myColor) {
                                         bool isVisited = false;
                                         for(int j=0; j<60; j++) {
                                             if (j >= visitedCount) break;
                                             if (visited[j] == n) {
                                                 isVisited = true;
                                                 break;
                                             }
                                         }
                                         if (!isVisited && visitedCount < 60) {
                                             visited[visitedCount++] = n;
                                             if (stackTop < 60) stack[stackTop++] = n;
                                         }
                                     }
                                 }
                                 if (foundLiberty) break;
                             }
                             
                             if (!foundLiberty) {
                                 fragColor = vec4(EMPTY, 0.0, 0.0, 0.0);
                                 return;
                             }
                        }
                    }
                }
            }
            
            // Clear Last Move marker
            // If we are here, we are NOT the new stone.
            // But we might be the OLD last move.
            // We should clear the marker bit (.z)
            // But wait, if I am the *new* stone, I returned above.
            // So here I am definitely not the new stone.
            // So I should clear my marker.
            fragColor.z = 0.0;
        }
    }
}
