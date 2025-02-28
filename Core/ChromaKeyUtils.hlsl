#ifndef CHROMA_KEY_UTILS_INCLUDED
#define CHROMA_KEY_UTILS_INCLUDED

float RGB2Y(float3 c) 
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

float RGB2Cb(float3 c) 
{
    return 0.5 + dot(c, float3(-0.168736, -0.331264, 0.5));
}

float RGB2Cr(float3 c) 
{
    return 0.5 + dot(c, float3(0.5, -0.418688, -0.081312));
}

float ColorClose(float Cb_p, float Cr_p, float Cb_key, float Cr_key, float tola, float tolb)
{
    float2 delta = float2(Cb_key - Cb_p, Cr_key - Cr_p);
    float dist2 = dot(delta, delta);
    float tola2 = tola * tola;
    float tolb2 = tolb * tolb;
    
    return dist2 < tola2 ? 0 : 
           dist2 < tolb2 ? (dist2 - tola2) / (tolb2 - tola2) : 1;
}

float GetChromaKeyMask(float2 uv, TEXTURE2D_PARAM(MainTex, samplerMainTex), float4 KeyColor, float ColorCutoff, float ColorFeathering)
{
    float4 color = SAMPLE_TEXTURE2D(MainTex, samplerMainTex, uv);
    float key_cb = RGB2Cb(KeyColor.rgb);
    float key_cr = RGB2Cr(KeyColor.rgb);
    float pix_cb = RGB2Cb(color.rgb);
    float pix_cr = RGB2Cr(color.rgb);

    return ColorClose(pix_cb, pix_cr, key_cb, key_cr, ColorCutoff, ColorFeathering);
}

#endif