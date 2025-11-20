#define BOARD_SIZE 19
#define STATE_POS vec2(20.0, 0.0)
#define HISTORY_COUNT_POS (STATE_POS + vec2(0.0, 1.0))
#define HISTORY_STRIDE (STATE_POS.x + 2.0)

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

ivec2 slotOrigin(int index, int slotsPerRow, int stride) {
    int row = index / slotsPerRow;
    int col = index - row * slotsPerRow;
    return ivec2(col * stride, row * stride);
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

// Check if a stone placed at movePos would have liberties
bool hasLibertiesAfterMove(ivec2 movePos, float color) {
    ivec2 neighbors[4];
    neighbors[0] = movePos + ivec2(1, 0);
    neighbors[1] = movePos + ivec2(-1, 0);
    neighbors[2] = movePos + ivec2(0, 1);
    neighbors[3] = movePos + ivec2(0, -1);
    
    for(int i=0; i<4; i++) {
        ivec2 n = neighbors[i];
        if (!onBoard(n)) continue;
        float s = getStone(n);
        if (s == EMPTY) return true;
        if (s == color) {
            // Friendly group must have > 1 liberty (since one is the current movePos)
            if (getGroupInfo(n, color).liberties > 1) return true;
        }
    }
    return false;
}

// Calculate how many stones would be captured by a move
int getCaptureCount(ivec2 movePos, float color) {
    int captured = 0;
    float opponent = (color == BLACK) ? WHITE : BLACK;
    ivec2 neighbors[4];
    neighbors[0] = movePos + ivec2(1, 0);
    neighbors[1] = movePos + ivec2(-1, 0);
    neighbors[2] = movePos + ivec2(0, 1);
    neighbors[3] = movePos + ivec2(0, -1);
    
    for(int i=0; i<4; i++) {
        ivec2 n = neighbors[i];
        if (!onBoard(n)) continue;
        if (getStone(n) == opponent) {
            GroupInfo gInfo = getGroupInfo(n, opponent);
            if (gInfo.liberties == 1) {
                captured += gInfo.stones;
            }
        }
    }
    return captured;
}

// Check if a move is suicide
bool isSuicide(ivec2 movePos, float color) {
    return getCaptureCount(movePos, color) == 0 && !hasLibertiesAfterMove(movePos, color);
}

bool isValidMove(ivec2 movePos, float color, vec2 koPos, out vec2 nextKo) {
    nextKo = vec2(-1.0);
    if (!onBoard(movePos)) return false;
    if (getStone(movePos) != EMPTY) return false;
    
    if (koPos.x >= 0.0 && float(movePos.x) == koPos.x && float(movePos.y) == koPos.y) {
        return false;
    }
    
    if (isSuicide(movePos, color)) return false;
    
    int capturedCount = getCaptureCount(movePos, color);
    if (capturedCount == 1) {
        bool hasFriendlyNeighbor = false;
        int directLiberties = 0;
        
        ivec2 neighbors[4];
        neighbors[0] = movePos + ivec2(1, 0);
        neighbors[1] = movePos + ivec2(-1, 0);
        neighbors[2] = movePos + ivec2(0, 1);
        neighbors[3] = movePos + ivec2(0, -1);
        
        for(int i=0; i<4; i++) {
            ivec2 n = neighbors[i];
            if (!onBoard(n)) continue;
            float s = getStone(n);
            if (s == color) hasFriendlyNeighbor = true;
            if (s == EMPTY) directLiberties++;
        }
        
        if (!hasFriendlyNeighbor && directLiberties == 0) {
            float opponent = (color == BLACK) ? WHITE : BLACK;
            for(int i=0; i<4; i++) {
                ivec2 n = neighbors[i];
                if (!onBoard(n)) continue;
                if (getStone(n) == opponent) {
                    GroupInfo gInfo = getGroupInfo(n, opponent);
                    if (gInfo.liberties == 1 && gInfo.stones == 1) {
                        nextKo = vec2(n);
                        break;
                    }
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
        } else if (iFragCoord == ivec2(HISTORY_COUNT_POS)) {
            fragColor = vec4(0.0);
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
    
    int historyStride = int(HISTORY_STRIDE + 0.5);
    int slotsPerRow = max(1, int(iResolution.x) / historyStride);
    int slotsPerCol = max(1, int(iResolution.y) / historyStride);
    int totalSlots = slotsPerRow * slotsPerCol;
    int maxHistory = max(0, totalSlots - 1);
    int historyCount = int(loadValue(HISTORY_COUNT_POS).x + 0.5);
    historyCount = clamp(historyCount, 0, maxHistory);
    
    if (gameState != PLAYING) {
        // Still allow undo to rewind a finished game
    }
    
    // Input Handling
    vec4 lastMouse = loadValue(STATE_POS + vec2(1.0, 0.0));
    bool isNewClick = (iMouse.z > 0.0) && (iMouse.zw != lastMouse.zw);
    
    float minDim = min(iResolution.x, iResolution.y);
    vec2 screenUV = iMouse.xy / iResolution.xy;
    vec2 uv = (iMouse.xy - 0.5 * iResolution.xy) / minDim;
    float boardSize = 0.9;
    vec2 boardUV = (uv + boardSize * 0.5) / boardSize;
    vec2 boardGrid = boardUV * (float(BOARD_SIZE) - 1.0);
    ivec2 movePos = ivec2(round(boardGrid));
    vec2 dist = abs(boardGrid - vec2(movePos));
    
    // Button hit boxes (aligned with image.glsl)
    vec2 resignCenter = vec2(0.91, 0.94);
    vec2 resignHalf = vec2(0.07, 0.03);
    vec2 undoCenter = vec2(0.91, 0.84);
    vec2 undoHalf = vec2(0.07, 0.03);
    
    vec2 resignP = screenUV - resignCenter;
    resignP.x *= iResolution.x / iResolution.y;
    bool isResignClick = isNewClick && all(lessThanEqual(abs(resignP), resignHalf));
    
    vec2 undoP = screenUV - undoCenter;
    undoP.x *= iResolution.x / iResolution.y;
    bool isUndoClick = isNewClick && all(lessThanEqual(abs(undoP), undoHalf));
    
    bool tryMove = isNewClick && gameState == PLAYING && !isResignClick && !isUndoClick &&
                   boardUV.x >= 0.0 && boardUV.x <= 1.0 && boardUV.y >= 0.0 && boardUV.y <= 1.0 &&
                   length(dist) < 0.4;
    
    vec2 nextKo = vec2(-1.0);
    bool validMove = false;
    if (tryMove) {
        validMove = isValidMove(movePos, currentPlayer, koPos, nextKo);
    }
    
    bool shouldUndo = isUndoClick && historyCount > 0 && maxHistory > 0;
    bool recordHistory = validMove && historyCount >= 0 && maxHistory > 0;
    
    // History slots
    if (maxHistory > 0) {
        int slotX = int(floor(fragCoord.x / float(historyStride)));
        int slotY = int(floor(fragCoord.y / float(historyStride)));
        bool insideGrid = slotX < slotsPerRow && slotY < slotsPerCol;
        int slotIndex = slotY * slotsPerRow + slotX;
        if (insideGrid && slotIndex > 0) {
            ivec2 origin = ivec2(slotX * historyStride, slotY * historyStride);
            ivec2 localCoord = iFragCoord - origin;
            bool boardCoord = (localCoord.x >= 0 && localCoord.x < BOARD_SIZE) && (localCoord.y >= 0 && localCoord.y < BOARD_SIZE);
            bool globalCoord = (localCoord.x == int(STATE_POS.x)) && (localCoord.y == int(STATE_POS.y));
            
            if ((boardCoord || globalCoord) && slotIndex <= maxHistory) {
                if (recordHistory) {
                    ivec2 sourceOrigin = slotOrigin(slotIndex - 1, slotsPerRow, historyStride);
                    fragColor = loadValue(vec2(sourceOrigin + localCoord));
                    return;
                } else if (shouldUndo) {
                    if (slotIndex < historyCount) {
                        ivec2 sourceOrigin = slotOrigin(slotIndex + 1, slotsPerRow, historyStride);
                        fragColor = loadValue(vec2(sourceOrigin + localCoord));
                    } else {
                        fragColor = vec4(0.0);
                    }
                    return;
                }
            }
        }
    }
    
    // Input Handling
    // Update Global State
    if (iFragCoord == ivec2(STATE_POS)) {
        if (shouldUndo) {
            ivec2 history0Origin = slotOrigin(1, slotsPerRow, historyStride);
            fragColor = loadValue(vec2(history0Origin + iFragCoord));
            return;
        }
        
        if (isResignClick) {
            fragColor = vec4(currentPlayer, (currentPlayer == BLACK) ? WHITE_WINS : BLACK_WINS, 0.0, 0.0);
            return;
        }
        
        if (validMove) {
            fragColor = vec4((currentPlayer == BLACK) ? WHITE : BLACK, PLAYING, nextKo);
            return;
        }
        return;
    }
    
    // Update Last Mouse
    if (iFragCoord == ivec2(STATE_POS + vec2(1.0, 0.0))) {
        fragColor = iMouse;
        return;
    }
    
    // History count
    if (iFragCoord == ivec2(HISTORY_COUNT_POS)) {
        if (recordHistory) {
            fragColor = vec4(float(min(historyCount + 1, maxHistory)), 0.0, 0.0, 0.0);
        } else if (shouldUndo) {
            fragColor = vec4(float(max(historyCount - 1, 0)), 0.0, 0.0, 0.0);
        }
        return;
    }
    
    // Board Update
    if (onBoard(iFragCoord)) {
        if (shouldUndo) {
            ivec2 history0Origin = slotOrigin(1, slotsPerRow, historyStride);
            fragColor = loadValue(vec2(history0Origin + iFragCoord));
            return;
        }
        
        if (validMove) {
            if (iFragCoord == movePos) {
                fragColor = vec4(currentPlayer, 0.0, 1.0, 0.0);
                return;
            }
            
            if (data.x != EMPTY && data.x != currentPlayer) {
                GroupInfo info = getGroupInfo(iFragCoord, data.x);
                if (info.liberties == 1) {
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
                        fragColor = vec4(EMPTY, 0.0, 0.0, 0.0);
                        return;
                    }
                }
            }
        }
        
        if (isNewClick && !isUndoClick && !isResignClick) {
            fragColor.z = 0.0;
        }
    }
}
