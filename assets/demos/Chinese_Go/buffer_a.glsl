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

// Structure to return group info
struct GroupInfo {
    int stones;
    int liberties;
};

// Flood fill to count stones and liberties
GroupInfo getGroupInfo(ivec2 startPos, float color) {
    GroupInfo info;
    info.stones = 0;
    info.liberties = 0;
    
    ivec2 stack[60];
    int stackTop = 0;
    stack[stackTop++] = startPos;
    
    ivec2 visited[60];
    int visitedCount = 0;
    visited[visitedCount++] = startPos;
    
    // Track unique liberties (capped at 20) for Ko check
    ivec2 liberties[20];
    int libertyCount = 0;
    
    int safety = 0;
    while(stackTop > 0 && safety < 100) {
        safety++;
        ivec2 p = stack[--stackTop];
        info.stones++;
        
        ivec2 neighbors[4];
        neighbors[0] = p + ivec2(1, 0);
        neighbors[1] = p + ivec2(-1, 0);
        neighbors[2] = p + ivec2(0, 1);
        neighbors[3] = p + ivec2(0, -1);
        
        for(int i=0; i<4; i++) {
            ivec2 n = neighbors[i];
            if (!onBoard(n)) continue;
            
            float s = getStone(n);
            if (s == EMPTY) {
                // Check if already counted
                bool known = false;
                for(int k=0; k<20; k++) {
                    if (k >= libertyCount) break;
                    if (liberties[k] == n) {
                        known = true;
                        break;
                    }
                }
                if (!known && libertyCount < 20) {
                    liberties[libertyCount++] = n;
                }
            } else if (s == color) {
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
    }
    info.liberties = libertyCount;
    return info;
}

// Simplified check for death (just need to know if liberties == 0)
bool isDead(ivec2 startPos, float color) {
    ivec2 stack[60];
    int stackTop = 0;
    stack[stackTop++] = startPos;
    
    ivec2 visited[60];
    int visitedCount = 0;
    visited[visitedCount++] = startPos;
    
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
            
            float s = getStone(n);
            if (s == EMPTY) return false; // Found a liberty
            
            if (s == color) {
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
    }
    return true;
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    ivec2 iFragCoord = ivec2(fragCoord);
    
    // Initialize
    if (iFrame == 0) {
        fragColor = vec4(0.0);
        if (iFragCoord == ivec2(STATE_POS)) {
            // .x = Current Player, .y = Game State, .zw = Ko Position (-1 if none)
            fragColor = vec4(BLACK, PLAYING, -1.0, -1.0); 
        }
        return;
    }
    
    // Default: Keep previous state
    vec4 data = loadValue(fragCoord);
    fragColor = data;
    
    vec4 globalState = loadValue(STATE_POS);
    float currentPlayer = globalState.x;
    float gameState = globalState.y;
    vec2 koPos = globalState.zw;
    
    if (gameState != PLAYING) {
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
                
                if (length(dist) < 0.4 && onBoard(boardPos)) {
                    if (getStone(boardPos) == EMPTY) {
                        // Check Ko Rule
                        if (koPos.x >= 0.0 && float(boardPos.x) == koPos.x && float(boardPos.y) == koPos.y) {
                            return;
                        }
                        
                        // Check if move creates a Ko (captures 1 stone, new stone has 1 liberty)
                        int capturedCount = 0;
                        vec2 potentialKo = vec2(-1.0);
                        
                        ivec2 neighbors[4];
                        neighbors[0] = boardPos + ivec2(1, 0);
                        neighbors[1] = boardPos + ivec2(-1, 0);
                        neighbors[2] = boardPos + ivec2(0, 1);
                        neighbors[3] = boardPos + ivec2(0, -1);
                        
                        float opponent = (currentPlayer == BLACK) ? WHITE : BLACK;
                        
                        for(int i=0; i<4; i++) {
                            ivec2 n = neighbors[i];
                            if (!onBoard(n)) continue;
                            if (getStone(n) == opponent) {
                                // Check if opponent group dies (if it has 1 liberty and that liberty is the move position)
                                GroupInfo gInfo = getGroupInfo(n, opponent);
                                
                                if (gInfo.liberties == 1) {
                                    capturedCount += gInfo.stones;
                                    if (gInfo.stones == 1) {
                                        potentialKo = vec2(n);
                                    }
                                }
                            }
                        }
                        
                        vec2 nextKo = vec2(-1.0);
                        
                        if (capturedCount == 1) {
                            // Ko condition: captured 1 stone, new stone has 1 liberty (isolated)
                            bool hasFriendlyNeighbor = false;
                            int directLiberties = 0;
                             for(int i=0; i<4; i++) {
                                ivec2 n = neighbors[i];
                                if (!onBoard(n)) continue;
                                float s = getStone(n);
                                if (s == currentPlayer) hasFriendlyNeighbor = true;
                                if (s == EMPTY) directLiberties++;
                            }
                            
                            if (!hasFriendlyNeighbor && directLiberties == 0) {
                                nextKo = potentialKo;
                            }
                        }
                        
                        fragColor = vec4(opponent, PLAYING, nextKo);
                        return;
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
                
                if (length(dist) < 0.4 && onBoard(movePos)) {
                    if (getStone(movePos) == EMPTY) {
                        // Check Ko
                        if (koPos.x >= 0.0 && float(movePos.x) == koPos.x && float(movePos.y) == koPos.y) {
                            return;
                        }
                        
                        // 1. Place Stone
                        if (iFragCoord == movePos) {
                            fragColor = vec4(currentPlayer, 0.0, 1.0, 0.0);
                            return;
                        }
                        
                        // 2. Capture Logic
                        if (data.x != EMPTY && data.x != currentPlayer) {
                             // Check if stone dies (if it has 1 liberty and that liberty is the move position)
                             GroupInfo info = getGroupInfo(iFragCoord, data.x);
                             if (info.liberties == 1) {
                                 // Verify if the single liberty is indeed the move position
                                 bool connectedToMovePos = false;
                                 
                                 ivec2 stack[60];
                                 int stackTop = 0;
                                 stack[stackTop++] = iFragCoord;
                                 
                                 ivec2 visited[60];
                                 int visitedCount = 0;
                                 visited[visitedCount++] = iFragCoord;
                                 
                                 int safety = 0;
                                 while(stackTop > 0 && safety < 100) {
                                     safety++;
                                     ivec2 p = stack[--stackTop];
                                     
                                     if (abs(p.x - movePos.x) + abs(p.y - movePos.y) == 1) {
                                         connectedToMovePos = true;
                                     }
                                     
                                     ivec2 neighbors[4];
                                     neighbors[0] = p + ivec2(1, 0);
                                     neighbors[1] = p + ivec2(-1, 0);
                                     neighbors[2] = p + ivec2(0, 1);
                                     neighbors[3] = p + ivec2(0, -1);
                                     
                                     for(int i=0; i<4; i++) {
                                         ivec2 n = neighbors[i];
                                         if (!onBoard(n)) continue;
                                         if (getStone(n) == data.x) {
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
                                 }
                                 
                                 if (connectedToMovePos) {
                                     // Group dies
                                     fragColor = vec4(EMPTY, 0.0, 0.0, 0.0);
                                     return;
                                 }
                             }
                        }
                    }
                }
            }
            
            // Clear Last Move marker
            fragColor.z = 0.0;
        }
    }
}
