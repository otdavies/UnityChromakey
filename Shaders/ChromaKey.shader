Shader "Unlit/ChromaKey"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _KeyColor("KeyColor", Color) = (0,1,0,0)
        _TintColor("TintColor", Color) = (1,1,1,1)
        _Cutoff("Cutoff", Range(0, 1)) = 1
        _ColorFeathering("ColorFeathering", Range(0, 1)) = 1
        _MaskFeathering("MaskFeathering", Range(0, 1)) = 1
        _Sharpening("Sharpening", Range(0, 1)) = 0
        _Despill("DespillStrength", Range(0, 1)) = 0
        _DespillLuminanceAdd("DespillLuminanceAdd", Range(0, 1)) = 0
    }
    SubShader
    {
        Tags
        {
            "RenderPipeline"="HDRenderPipeline"
            "RenderType"="HDUnlitShader"
            "Queue" = "Transparent+0"
        }

        ZWrite Off
        Blend SrcAlpha OneMinusSrcAlpha
        cull off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_TexelSize;
            float4 _MainTex_ST;
            float4 _KeyColor;
            float4 _TintColor;
            float _Cutoff;
            float _ColorFeathering;
            float _MaskFeathering;
            float _Sharpening;
            float _Despill;
            float _DespillLuminanceAdd;

            // Utility funcs
            float rgb2y(float3 c) 
            {
                return (0.299*c.r + 0.587*c.g + 0.114*c.b);
            }

            float rgb2cb(float3 c) 
            {
                return (0.5 + -0.168736*c.r - 0.331264*c.g + 0.5*c.b);
            }

            float rgb2cr(float3 c) 
            {
                return (0.5 + 0.5*c.r - 0.418688*c.g - 0.081312*c.b);
            }

            float colorclose(float Cb_p, float Cr_p, float Cb_key, float Cr_key, float tola, float tolb)
            {
                float temp = sqrt((Cb_key-Cb_p)*(Cb_key-Cb_p)+(Cr_key-Cr_p)*(Cr_key-Cr_p));
                if (temp < tola) return (0);
                if (temp < tolb) return (temp-tola)/(tolb-tola);
                return (1);
            }

            float maskedTex2D(sampler2D tex, float2 uv)
            {
                float4 color = tex2D(tex, uv);
                
                // Chroma key to CYK conversion
                float key_cb = rgb2cb(_KeyColor.rgb);
                float key_cr = rgb2cr(_KeyColor.rgb);
                float pix_cb = rgb2cb(color.rgb);
                float pix_cr = rgb2cr(color.rgb);

                return colorclose(pix_cb, pix_cr, key_cb, key_cr, _Cutoff, _ColorFeathering);
            }


			//--------------

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float2 pixelWidth = float2(1.0 / _MainTex_TexelSize.z, 0);
                float2 pixelHeight = float2(0, 1.0 / _MainTex_TexelSize.w);
                float4 color = tex2D(_MainTex, i.uv);

                // Flat unfeathered mask
                float mask = maskedTex2D(_MainTex, i.uv);

                // Feathering & smoothing
                float c = mask;
                float r = maskedTex2D(_MainTex, i.uv + pixelWidth);
                float l = maskedTex2D(_MainTex, i.uv - pixelWidth);
                float d = maskedTex2D(_MainTex, i.uv + pixelHeight); 
                float u = maskedTex2D(_MainTex, i.uv - pixelHeight);
                float rd = maskedTex2D(_MainTex, i.uv + pixelWidth + pixelHeight) * .707;
                float dl = maskedTex2D(_MainTex, i.uv - pixelWidth + pixelHeight) * .707;
                float lu = maskedTex2D(_MainTex, i.uv - pixelHeight - pixelWidth) * .707;
                float ur = maskedTex2D(_MainTex, i.uv + pixelWidth - pixelHeight) * .707;
                float blurContribution = (r + l + d + u + rd + dl + lu + ur + c) * 0.12774655;
                float smoothedMask = smoothstep(_Sharpening, 1, lerp(c, blurContribution, _MaskFeathering));
                float4 result = color * smoothedMask;

                // Despill
                float v = (2*result.b+result.r)/4;
                if(result.g > v) result.g = lerp(result.g, v, _Despill);
                float4 dif = (color - result);
                float desaturatedDif = rgb2y(dif.xyz);
                result += lerp(0, desaturatedDif, _DespillLuminanceAdd);
                float4 test = result + desaturatedDif;
                return float4(result.xyz * _TintColor, smoothedMask);
            }
            ENDCG
        }
    }
}
