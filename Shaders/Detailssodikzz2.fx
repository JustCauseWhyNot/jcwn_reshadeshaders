/**
  Details filter from GeForce Experience. Provided by NVIDIA Corporation.

  Copyright 2019 Suketu J. Shah. All rights reserved.

  Redistribution and use in source and binary forms, with or without modification, are permitted provided
  that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice, this list of conditions
       and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions
       and the following disclaimer in the documentation and/or other materials provided with the distribution.
    3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse
       or promote products derived from this software without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
  TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#include "ReShadeUI.fxh"

uniform float g_sldSharpen < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.000; ui_max=1.000;
	ui_label = "Sharpen";
	ui_step = 0.001;
> = 0.5;

uniform float g_sldClarity < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.000; ui_max=1.000;
	ui_label = "Clarity";
	ui_step = 0.001;
> = 0.7;

uniform float g_sldHDR < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.000; ui_max=1.000;
	ui_label = "HDR Toning";
	ui_step = 0.001;
> = 0.6;

uniform float g_sldBloom < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.000; ui_max=1.000;
	ui_label = "Bloom";
	ui_step = 0.001;
> = 0.15;

#include "NvCommon.fxh"

texture LargeBlurTex { Width = BUFFER_WIDTH*0.5;   Height = BUFFER_HEIGHT*0.5;  Format = RGBA16F; }; //requires recent changes to support this
sampler sLargeBlurTex { Texture = LargeBlurTex;};

float4 gaussian(sampler sinput, float2 uv, int nSteps, float2 axis)
{
    float norm = -1.35914091423 / (nSteps * nSteps);
    float4 accum = tex2D(sinput, uv) * 0.5;
    float2 offsetinc = axis * BUFFER_PIXEL_SIZE;

	float divisor = 0.5; //exp(0) * 0.5

    [loop]
    for(float iStep = 1; iStep <= nSteps; iStep++)
    {
        //linear sample, gathers 2 texels at once
        //only texel not being sampled that way is center, hence it needs 1/2 the weight
        float tapOffset = iStep * 2.0 - 0.5;
        float tapWeight = exp(iStep * iStep * norm);

        accum += tex2Dlod(sinput, float4(uv + offsetinc * tapOffset, 0, 0)) * tapWeight;
        accum += tex2Dlod(sinput, float4(uv - offsetinc * tapOffset, 0, 0)) * tapWeight;
        divisor += tapWeight;
    }
    accum /= 2.0 * divisor;
    return accum;
}

float4 box(sampler sinput, float2 uv)
{
    const float3 blurData[8] = 
    {
        float3( 0.5, 1.5,1.50),
        float3( 1.5,-0.5,1.50),
        float3(-0.5,-1.5,1.50),
        float3(-1.5, 0.5,1.50),
        float3( 2.5, 1.5,1.00),
        float3( 1.5,-2.5,1.00),
        float3(-2.5,-1.5,1.00),
        float3(-1.5, 2.5,1.00),
    };

    float4 blur = 0.0;
    for(int i=0; i<8; i++)
    blur += tex2Dlod(sinput, float4(uv + blurData[i].xy * BUFFER_PIXEL_SIZE, 0, 0)) * blurData[i].z;

    blur /= (4 * 1.5) + (4 * 1.0);
    return blur;
}

float getluma(float3 color)
{
    return dot(color,float3(0.299,0.587,0.114));
}

void PSGaussian1(in VSOut i, out float4 color : SV_Target)
{
	color = gaussian(NV::ColorInput, i.uv, 15, float2(1, 0));
}
void PSGaussian2AndBlend(in VSOut i, out float4 color : SV_Target)
{
	float4 largeblur = gaussian(sLargeBlurTex, i.uv, 15, float2(0, 1));
    float4 smallblur = box(NV::ColorInput, i.uv);
    color = tex2D(NV::ColorInput, i.uv);

    float a = getluma(color.rgb);
	float b = getluma(largeblur.rgb);
	float c = getluma(smallblur.rgb);

//HDR Toning
    float sqrta     = sqrt(a);
    float HDRToning = sqrta * lerp(sqrta*(2*a*b-a-2*b+2.0), (2*sqrta*b-2*b+1), b > 0.5); //modified soft light v1
    color = color / (a+1e-6) * lerp(a,HDRToning,g_sldHDR);

//sharpen
    float Sharpen = getluma(color.rgb - smallblur.rgb); //need to recompute, as luma of color changed by hdr toning
    float sharplimit = lerp(0.25,0.6,g_sldSharpen);
    Sharpen = clamp(Sharpen,-sharplimit, sharplimit);
    color.rgb = color.rgb / a * lerp(a,a+Sharpen,g_sldSharpen);

//clarity
    float Clarity = (0.5 + a - b);
    Clarity = lerp(2*Clarity + a*(1-2*Clarity), 2*(1-Clarity)+(2*Clarity-1)*rsqrt(a), a > b); //modified soft light v2
    color.rgb *= lerp(1.0,Clarity,g_sldClarity);

//bloom
    color.rgb = 1-(1-color.rgb)*(1-largeblur.rgb * g_sldBloom);

}

technique Details
{
    pass
    {
        VertexShader = VSMain;
        PixelShader  = PSGaussian1;
        RenderTarget = LargeBlurTex;
    }
    pass
    {
        VertexShader = VSMain;
        PixelShader  = PSGaussian2AndBlend;
    }
}

