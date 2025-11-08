#include "ReShade.fxh"
uniform float g_sldExposure <
    ui_label = "Exposure";
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 0.01;
    > = 0.0;
uniform float g_sldHighlightsIntensity <
    ui_label = "Highlights";
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 0.01;
    > = 0.0;
uniform float g_sldShadowsIntensity <
    ui_label = "Shadows";
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 0.01;
    > = 0.0;
float GetToneCurve(float x, float exposureV, float highlightsV, float shadowsV)
{
    float shadows       = smoothstep(0.666,0.0,x);
    float highlights    = smoothstep(0.333,1.0,x);
    float rest      = saturate(1.0 - shadows - highlights);
    x = pow(saturate(x * exposureV), exp2(shadows * shadowsV + highlights * highlightsV + rest - 1));
    return x;
}
float4 PS_Exposure(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
        float4 color = tex2D(ReShade::BackBuffer,texcoord.xy);
    float exposureV     = exp2(g_sldExposure);      //-100%: exposure of 0.5, 100%: gamma of 2
    float highlightsV   = exp2(-g_sldHighlightsIntensity);
    float shadowsV      = exp2(-g_sldShadowsIntensity);
    //apply modifications. Need to be per channel, otherwise shadows etc weights won't work.
    color.r = GetToneCurve(color.r,exposureV,highlightsV,shadowsV);
    color.g = GetToneCurve(color.g,exposureV,highlightsV,shadowsV);
    color.b = GetToneCurve(color.b,exposureV,highlightsV,shadowsV);
    return color;
}

technique Nvdia_Exposure
{
        pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_Exposure;
    }
}
