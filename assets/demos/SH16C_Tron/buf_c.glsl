// Font rendering

const vec2 txState           = vec2(124.0,3.0);
const vec2 txWins            = vec2(124.0,5.0);
const vec2 txBoosts          = vec2(124.0,7.0);
const vec2 txOptions         = vec2(124.0,11.0);

const vec3 p1Color       = vec3(1.,0.9,0.2);
const vec3 p2Color       = vec3(.0,0.9,1.);

vec4 loadValue( in vec2 re )
{
    return texture( iChannel0, (0.5+re) / iChannelResolution[0].xy, -100.0 );
}

//============================================================
// Font rendering by Flyguy (https://www.shadertoy.com/view/llSGRm)


#define CHAR_SIZE vec2(6, 7)
#define CHAR_SPACING vec2(6, 9)

#define STRWIDTH(c) (c * CHAR_SPACING.x)
#define STRHEIGHT(c) (c * CHAR_SPACING.y)


vec2 print_pos = vec2(0);
float font_size = 5.;
//Automatically generated from the sprite sheet here: http://uzebox.org/wiki/index.php?title=File:Font6x8.png
vec2 ch_spc = vec2(0.0,0.0);
vec2 ch_exc = vec2(276705.0,32776.0);
vec2 ch_quo = vec2(1797408.0,0.0);
vec2 ch_hsh = vec2(10738.0,1134484.0);
vec2 ch_dol = vec2(538883.0,19976.0);
vec2 ch_pct = vec2(1664033.0,68006.0);
vec2 ch_amp = vec2(545090.0,174362.0);
vec2 ch_apo = vec2(798848.0,0.0);
vec2 ch_lbr = vec2(270466.0,66568.0);
vec2 ch_rbr = vec2(528449.0,33296.0);
vec2 ch_ast = vec2(10471.0,1688832.0);
vec2 ch_crs = vec2(4167.0,1606144.0);
vec2 ch_per = vec2(0.0,1560.0);
vec2 ch_dsh = vec2(7.0,1572864.0);
vec2 ch_com = vec2(0.0,1544.0);
vec2 ch_lsl = vec2(1057.0,67584.0);
vec2 ch_0 = vec2(935221.0,731292.0);
vec2 ch_1 = vec2(274497.0,33308.0);
vec2 ch_2 = vec2(934929.0,1116222.0);
vec2 ch_3 = vec2(934931.0,1058972.0);
vec2 ch_4 = vec2(137380.0,1302788.0);
vec2 ch_5 = vec2(2048263.0,1058972.0);
vec2 ch_6 = vec2(401671.0,1190044.0);
vec2 ch_7 = vec2(2032673.0,66576.0);
vec2 ch_8 = vec2(935187.0,1190044.0);
vec2 ch_9 = vec2(935187.0,1581336.0);
vec2 ch_col = vec2(195.0,1560.0);
vec2 ch_scl = vec2(195.0,1544.0);
vec2 ch_les = vec2(135300.0,66052.0);
vec2 ch_equ = vec2(496.0,3968.0);
vec2 ch_grt = vec2(528416.0,541200.0);
vec2 ch_que = vec2(934929.0,1081352.0);
vec2 ch_ats = vec2(935285.0,714780.0);
vec2 ch_A = vec2(935188.0,780450.0);
vec2 ch_B = vec2(1983767.0,1190076.0);
vec2 ch_C = vec2(935172.0,133276.0);
vec2 ch_D = vec2(1983764.0,665788.0);
vec2 ch_E = vec2(2048263.0,1181758.0);
vec2 ch_F = vec2(2048263.0,1181728.0);
vec2 ch_G = vec2(935173.0,1714334.0);
vec2 ch_H = vec2(1131799.0,1714338.0);
vec2 ch_I = vec2(921665.0,33308.0);
vec2 ch_J = vec2(66576.0,665756.0);
vec2 ch_K = vec2(1132870.0,166178.0);
vec2 ch_L = vec2(1065220.0,133182.0);
vec2 ch_M = vec2(1142100.0,665762.0);
vec2 ch_N = vec2(1140052.0,1714338.0);
vec2 ch_O = vec2(935188.0,665756.0);
vec2 ch_P = vec2(1983767.0,1181728.0);
vec2 ch_Q = vec2(935188.0,698650.0);
vec2 ch_R = vec2(1983767.0,1198242.0);
vec2 ch_S = vec2(935171.0,1058972.0);
vec2 ch_T = vec2(2035777.0,33288.0);
vec2 ch_U = vec2(1131796.0,665756.0);
vec2 ch_V = vec2(1131796.0,664840.0);
vec2 ch_W = vec2(1131861.0,699028.0);
vec2 ch_X = vec2(1131681.0,84130.0);
vec2 ch_Y = vec2(1131794.0,1081864.0);
vec2 ch_Z = vec2(1968194.0,133180.0);
vec2 ch_lsb = vec2(925826.0,66588.0);
vec2 ch_rsl = vec2(16513.0,16512.0);
vec2 ch_rsb = vec2(919584.0,1065244.0);
vec2 ch_pow = vec2(272656.0,0.0);
vec2 ch_usc = vec2(0.0,62.0);
vec2 ch_a = vec2(224.0,649374.0);
vec2 ch_b = vec2(1065444.0,665788.0);
vec2 ch_c = vec2(228.0,657564.0);
vec2 ch_d = vec2(66804.0,665758.0);
vec2 ch_e = vec2(228.0,772124.0);
vec2 ch_f = vec2(401543.0,1115152.0);
vec2 ch_g = vec2(244.0,665474.0);
vec2 ch_h = vec2(1065444.0,665762.0);
vec2 ch_i = vec2(262209.0,33292.0);
vec2 ch_j = vec2(131168.0,1066252.0);
vec2 ch_k = vec2(1065253.0,199204.0);
vec2 ch_l = vec2(266305.0,33292.0);
vec2 ch_m = vec2(421.0,698530.0);
vec2 ch_n = vec2(452.0,1198372.0);
vec2 ch_o = vec2(228.0,665756.0);
vec2 ch_p = vec2(484.0,667424.0);
vec2 ch_q = vec2(244.0,665474.0);
vec2 ch_r = vec2(354.0,590904.0);
vec2 ch_s = vec2(228.0,114844.0);
vec2 ch_t = vec2(8674.0,66824.0);
vec2 ch_u = vec2(292.0,1198868.0);
vec2 ch_v = vec2(276.0,664840.0);
vec2 ch_w = vec2(276.0,700308.0);
vec2 ch_x = vec2(292.0,1149220.0);
vec2 ch_y = vec2(292.0,1163824.0);
vec2 ch_z = vec2(480.0,1148988.0);
vec2 ch_lpa = vec2(401542.0,66572.0);
vec2 ch_bar = vec2(266304.0,33288.0);
vec2 ch_rpa = vec2(788512.0,1589528.0);
vec2 ch_tid = vec2(675840.0,0.0);
vec2 ch_lar = vec2(8387.0,1147904.0);


//Extracts bit b from the given number.
//Shifts bits right (num / 2^bit) then ANDs the result with 1 (mod(result,2.0)).
float extract_bit(float n, float b)
{
    b = clamp(b,-1.0,22.0); //Fixes small artefacts on my nexus 7
	return floor(mod(floor(n / pow(2.0,floor(b))),2.0));   
}

//Returns the pixel at uv in the given bit-packed sprite.
float sprite(vec2 spr, vec2 size, vec2 uv)
{
    uv = floor(uv);
    //Calculate the bit to extract (x + y * width) (flipped on x-axis)
    float bit = (size.x-uv.x-1.0) + uv.y * size.x;
    
    //Clipping bound to remove garbage outside the sprite's boundaries.
    bool bounds = all(greaterThanEqual(uv,vec2(0)));
    bounds = bounds && all(lessThan(uv,size));
    
    return bounds ? extract_bit(spr.x, bit - 21.0)+extract_bit(spr.y, bit) : 0.0;

}

//Prints a character and moves the print position forward by 1 character width.
float drawChar(vec2 ch, vec2 uv)
{
    float px = sprite(ch, CHAR_SIZE, uv/font_size - print_pos);
    print_pos.x += CHAR_SPACING.x;
    return px;
}

//Returns the digit sprite for the given number.
vec2 get_digit(int d)
{    
    if(d == 0) return ch_0;
    if(d == 1) return ch_1;
    if(d == 2) return ch_2;
    if(d == 3) return ch_3;
    if(d == 4) return ch_4;
    if(d == 5) return ch_5;
    if(d == 6) return ch_6;
    if(d == 7) return ch_7;
    if(d == 8) return ch_8;
    if(d == 9) return ch_9;
    return vec2(0.0);
}

//============================================================
//============================================================


vec3 mainScreenText(vec2 uv, float playerVsGpu)
{
    vec3 c = vec3(0);
    
    float col = 0.0;
    
    font_size = mix(5., 7., playerVsGpu);
    print_pos = vec2(-STRWIDTH(13.0)/2.0, -150./font_size -STRHEIGHT(1.0)/2.0);
    
    col = drawChar(ch_P,uv);
    col += drawChar(ch_L,uv);
    col += drawChar(ch_A,uv);
    col += drawChar(ch_Y,uv);
    col += drawChar(ch_E,uv);
    col += drawChar(ch_R,uv);
    
    col += drawChar(ch_spc,uv);
    
    col += drawChar(ch_v,uv);
    col += drawChar(ch_s,uv);
    
    col += drawChar(ch_spc,uv);
    
    col += drawChar(ch_G,uv);
    col += drawChar(ch_P,uv);
    col += drawChar(ch_U,uv);
    c += mix(vec3(0.5), vec3(1.,.9,0.1), playerVsGpu)*col;
    
    font_size = mix(7., 5., playerVsGpu);
    print_pos = vec2(-STRWIDTH(16.0)/2.0, -250./font_size -STRHEIGHT(1.0)/2.0);
       
    col = drawChar(ch_P,uv);
    col += drawChar(ch_L,uv);
    col += drawChar(ch_A,uv);
    col += drawChar(ch_Y,uv);
    col += drawChar(ch_E,uv);
    col += drawChar(ch_R,uv);
    
    col += drawChar(ch_spc,uv);
    
    col += drawChar(ch_v,uv);
    col += drawChar(ch_s,uv);
    
    col += drawChar(ch_spc,uv);
    
    col += drawChar(ch_P,uv);
    col += drawChar(ch_L,uv);
    col += drawChar(ch_A,uv);
    col += drawChar(ch_Y,uv);
    col += drawChar(ch_E,uv);
    col += drawChar(ch_R,uv);
    c += mix(vec3(1.,.9,.1), vec3(0.5), playerVsGpu)*col;
    
    return c;
}

vec3 gameStartCounter(vec2 uv, float state)
{        
    font_size = 16.;
    print_pos = vec2(-STRWIDTH(1.0)/2.0, -STRHEIGHT(1.0)/2.0);
    float col = drawChar(get_digit(int(-state)+1),uv);       

    return vec3(.1,.9,1.)*col;
}

vec3 gameHud(vec2 uv, float playerVsGpu, vec2 wins, vec2 boosts)
{        
    font_size = 6.;
    print_pos = vec2(-490.*(iResolution.x/iResolution.y)/font_size, 490./font_size-STRHEIGHT(1.0));
    float col = 0.;       
	col += drawChar(ch_P,uv);
    col += drawChar(ch_L,uv);
    col += drawChar(ch_A,uv);
    col += drawChar(ch_Y,uv);
    col += drawChar(ch_E,uv);
    col += drawChar(ch_R,uv);
    col += drawChar(ch_spc,uv);
    col += drawChar(ch_1,uv);
    
    font_size = 4.;
    print_pos = vec2(-490.*(iResolution.x/iResolution.y)/font_size, 400./font_size-STRHEIGHT(1.0));
	col += drawChar(ch_L,uv);
    col += drawChar(ch_i,uv);
    col += drawChar(ch_v,uv);
    col += drawChar(ch_e,uv);
    col += drawChar(ch_s,uv);
    col += drawChar(ch_col,uv);
    col += drawChar(ch_spc,uv);
    col += drawChar(get_digit(5 - int(wins.y)),uv);
    
    print_pos = vec2(-490.*(iResolution.x/iResolution.y)/font_size, 330./font_size-STRHEIGHT(1.0));
	col += drawChar(ch_T,uv);
    col += drawChar(ch_u,uv);
    col += drawChar(ch_r,uv);
    col += drawChar(ch_b,uv);
    col += drawChar(ch_o,uv);
    col += drawChar(ch_s,uv);
    col += drawChar(ch_col,uv);
    col += drawChar(ch_spc,uv);
    col += drawChar(get_digit(int(boosts.x)),uv);
    
    if (wins.x > 4.5)
    {
        font_size = 8.;
        print_pos = vec2(-460.*(iResolution.x/iResolution.y)/font_size + STRWIDTH(1.0)/2., 0.);
        col += drawChar(ch_Y,uv);
        col += drawChar(ch_O,uv);
        col += drawChar(ch_U,uv);
        print_pos = vec2(-460.*(iResolution.x/iResolution.y)/font_size, -STRHEIGHT(1.0));
        col += drawChar(ch_W,uv);
        col += drawChar(ch_I,uv);
        col += drawChar(ch_N,uv);
        col += drawChar(ch_exc,uv);
    }
    else if (wins.y > 4.5)
    {
        font_size = 8.;
        print_pos = vec2(-460.*(iResolution.x/iResolution.y)/font_size + STRWIDTH(1.0)/2., 0.);
        col += drawChar(ch_Y,uv);
        col += drawChar(ch_O,uv);
        col += drawChar(ch_U,uv);
        print_pos = vec2(-460.*(iResolution.x/iResolution.y)/font_size, -STRHEIGHT(1.0));
        col += drawChar(ch_L,uv);
        col += drawChar(ch_O,uv);
        col += drawChar(ch_S,uv);
        col += drawChar(ch_E,uv);
    }
    
    vec3 p1c = p1Color*col;
    
    font_size = 6.;
    
    if (playerVsGpu > 0.5)
    {
        print_pos = vec2(490.*(iResolution.x/iResolution.y)/font_size - STRWIDTH(3.0), 490./font_size-STRHEIGHT(1.0));
        col = drawChar(ch_G,uv);
        col += drawChar(ch_P,uv);
        col += drawChar(ch_U,uv);
    }
    else
    {
        print_pos = vec2(490.*(iResolution.x/iResolution.y)/font_size - STRWIDTH(8.0), 490./font_size-STRHEIGHT(1.0));
        col = drawChar(ch_P,uv);
        col += drawChar(ch_L,uv);
        col += drawChar(ch_A,uv);
        col += drawChar(ch_Y,uv);
        col += drawChar(ch_E,uv);
        col += drawChar(ch_R,uv);
        col += drawChar(ch_spc,uv);
        col += drawChar(ch_2,uv);

        if (wins.y > 4.5)
        {
            font_size = 8.;
            print_pos = vec2(460.*(iResolution.x/iResolution.y)/font_size - STRWIDTH(3.5), 0.);
            col += drawChar(ch_Y,uv);
            col += drawChar(ch_O,uv);
            col += drawChar(ch_U,uv);
            print_pos = vec2(460.*(iResolution.x/iResolution.y)/font_size - STRWIDTH(4.0), -STRHEIGHT(1.0));
            col += drawChar(ch_W,uv);
            col += drawChar(ch_I,uv);
            col += drawChar(ch_N,uv);
            col += drawChar(ch_exc,uv);
        }
        else if (wins.x > 4.5)
        {
            font_size = 8.;
            print_pos = vec2(460.*(iResolution.x/iResolution.y)/font_size - STRWIDTH(3.5), 0.);
            col += drawChar(ch_Y,uv);
            col += drawChar(ch_O,uv);
            col += drawChar(ch_U,uv);
            print_pos = vec2(460.*(iResolution.x/iResolution.y)/font_size - STRWIDTH(4.0), -STRHEIGHT(1.0));
            col += drawChar(ch_L,uv);
            col += drawChar(ch_O,uv);
            col += drawChar(ch_S,uv);
            col += drawChar(ch_E,uv);
    	}
    }
    
    font_size = 4.;
    print_pos = vec2(490.*(iResolution.x/iResolution.y)/font_size - STRWIDTH(9.0), 330./font_size-STRHEIGHT(1.0));
    col += drawChar(ch_T,uv);
    col += drawChar(ch_u,uv);
    col += drawChar(ch_r,uv);
    col += drawChar(ch_b,uv);
    col += drawChar(ch_o,uv);
    col += drawChar(ch_s,uv);
    col += drawChar(ch_col,uv);
    col += drawChar(ch_spc,uv);
    col += drawChar(get_digit(int(boosts.y)),uv);
    
    print_pos = vec2(490.*(iResolution.x/iResolution.y)/font_size - STRWIDTH(8.0), 400./font_size-STRHEIGHT(1.0));
	col += drawChar(ch_L,uv);
    col += drawChar(ch_i,uv);
    col += drawChar(ch_v,uv);
    col += drawChar(ch_e,uv);
    col += drawChar(ch_s,uv);
    col += drawChar(ch_col,uv);
    col += drawChar(ch_spc,uv);
    col += drawChar(get_digit(5 - int(wins.x)),uv);
    
    
                
    vec3 p2c = p2Color*col;
    return p1c + p2c;
}

vec3 showContinue(vec2 uv)
{        
    font_size = 4.;
    float col = 0.;       

    print_pos = vec2(480.*(iResolution.x/iResolution.y)/font_size - STRWIDTH(11.0), -490./font_size+STRHEIGHT(2.0));
    col += drawChar(ch_P,uv);
    col += drawChar(ch_r,uv);
    col += drawChar(ch_e,uv);
    col += drawChar(ch_s,uv);
    col += drawChar(ch_s,uv);
    col += drawChar(ch_spc,uv);
    col += drawChar(ch_E,uv);
    col += drawChar(ch_N,uv);
    col += drawChar(ch_T,uv);
    col += drawChar(ch_E,uv);
    col += drawChar(ch_R,uv);
    
    print_pos = vec2(480.*(iResolution.x/iResolution.y)/font_size - STRWIDTH(11.0), -490./font_size+STRHEIGHT(1.0));
    col += drawChar(ch_t,uv);
    col += drawChar(ch_o,uv);
    col += drawChar(ch_spc,uv);
    col += drawChar(ch_c,uv);
    col += drawChar(ch_o,uv);
    col += drawChar(ch_n,uv);
    col += drawChar(ch_t,uv);
    col += drawChar(ch_i,uv);
    col += drawChar(ch_n,uv);
    col += drawChar(ch_u,uv);
    col += drawChar(ch_e,uv);
    return vec3(col);
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    //------------------------
    // load game state
    //------------------------
    float state  = loadValue( txState ).x;
    float playerVsGpu  = loadValue( txOptions ).x;
    vec2 wins  = loadValue( txWins ).xy;
    vec2 boosts  = loadValue( txBoosts ).xz;
    
    
    //------------------------
    // render
    //------------------------
    
    vec3 col = vec3(0);
    vec2 uv = fragCoord.xy /iResolution.xy;
    vec2 p = -500. + 1000.*uv;
    p.x *= iResolution.x / iResolution.y;
    if (state < -9.)
    {
        col += mainScreenText(p, playerVsGpu);
    }
    else
    {
     	if (state < 0.)
        {
            col += gameStartCounter(p, state);
        }
        else if (state > 1.5)
        {
            col += showContinue(p);
        }
        col += gameHud(p, playerVsGpu, wins, boosts);
    }
    
	fragColor = vec4(col, 1.0);
}
