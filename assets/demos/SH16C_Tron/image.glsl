// Created by David Bargo - davidbargo/2016
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec3 col = texture( iChannel0, fragCoord.xy/iResolution.xy ).xyz;
    vec3 fontLayer = texture( iChannel1, fragCoord.xy/iResolution.xy ).xyz;

    col = mix(col, fontLayer, fontLayer.x + fontLayer.y + fontLayer.z > 0.01 ? 1.:0.);
	fragColor = vec4( col, 1.0 );
}
