Shader "Custom/ChromaKey"
{
    Properties
    {
        [Toggle] _IsEnabled("Enable Chroma Key", Float) = 1

        [Header(Main Settings)]
        [MainTexture] _MainTex ("Texture", 2D) = "white" {}
        [MainColor] [HDR] _KeyColor("Key Color", Color) = (0,1,0,0)
        [HDR] _TintColor("Tint Color", Color) = (1,1,1,1)
        
        [Header(Key Settings)]
        [Space(10)]
        _ColorCutoff("Color Sensitivity", Range(0, 1)) = 0.3
        
        _ColorFeathering("Edge Softness", Range(0, 0.25)) = 0.02
        [Header(Edge Refinement)]
        [Space(10)]
        _MaskFeathering("Mask Smoothing", Range(0, 1)) = 1
        
        [Header(Spill Removal)]
        [Space(10)]
        _Despill("Spill Removal", Range(0, 1)) = 0.5
        _DespillLuminanceAdd("Preserve Brightness", Range(0, 1)) = 0.2
        
        
        [HideInInspector] _StencilRef("Stencil Ref", Float) = 0
        [HideInInspector] _StencilComp("Stencil Comparison", Float) = 8
    }
    CustomEditor "ChromaKeyGUI"

    SubShader
    {
        Tags 
        { 
            "RenderType" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
            "UniversalMaterialType" = "Unlit"
            "Queue" = "Transparent"
            "IgnoreProjector" = "True"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off

            Stencil
            {
                Ref [_StencilRef]
                Comp [_StencilComp]
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "ChromaKeyUtils.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float fogCoord : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _MainTex_TexelSize;
                float4 _KeyColor;
                float4 _TintColor;
                float _ColorCutoff;
                float _ColorFeathering;
                float _MaskFeathering;
                float _Sharpening;
                float _Despill;
                float _DespillLuminanceAdd;
                float _IsEnabled;
            CBUFFER_END

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                output.fogCoord = ComputeFogFactor(output.positionCS.z);
                
                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                float2 pixelWidth = float2(_MainTex_TexelSize.x, 0);
                float2 pixelHeight = float2(0, _MainTex_TexelSize.y);

                float4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);

                if (_IsEnabled < 0.5)
                {
                    return color * _TintColor;
                }

                _ColorFeathering = _ColorCutoff + _ColorFeathering;
                float mask = GetChromaKeyMask(input.uv, TEXTURE2D_ARGS(_MainTex, sampler_MainTex), _KeyColor, _ColorCutoff, _ColorFeathering);

                // 8-direction sampling for smooth edges
                float c = mask;
                float r = GetChromaKeyMask(input.uv + pixelWidth, TEXTURE2D_ARGS(_MainTex, sampler_MainTex), _KeyColor, _ColorCutoff, _ColorFeathering);
                float l = GetChromaKeyMask(input.uv - pixelWidth, TEXTURE2D_ARGS(_MainTex, sampler_MainTex), _KeyColor, _ColorCutoff, _ColorFeathering);
                float d = GetChromaKeyMask(input.uv + pixelHeight, TEXTURE2D_ARGS(_MainTex, sampler_MainTex), _KeyColor, _ColorCutoff,_ColorFeathering);
                float u = GetChromaKeyMask(input.uv - pixelHeight, TEXTURE2D_ARGS(_MainTex, sampler_MainTex), _KeyColor, _ColorCutoff, _ColorFeathering);
                float rd = GetChromaKeyMask(input.uv + pixelWidth + pixelHeight, TEXTURE2D_ARGS(_MainTex, sampler_MainTex), _KeyColor, _ColorCutoff,_ColorFeathering) * 0.707;
                float dl = GetChromaKeyMask(input.uv - pixelWidth + pixelHeight, TEXTURE2D_ARGS(_MainTex, sampler_MainTex), _KeyColor, _ColorCutoff, _ColorFeathering) * 0.707;
                float lu = GetChromaKeyMask(input.uv - pixelHeight - pixelWidth, TEXTURE2D_ARGS(_MainTex, sampler_MainTex), _KeyColor, _ColorCutoff, _ColorFeathering) * 0.707;
                float ur = GetChromaKeyMask(input.uv + pixelWidth - pixelHeight, TEXTURE2D_ARGS(_MainTex, sampler_MainTex), _KeyColor, _ColorCutoff, _ColorFeathering) * 0.707;
                
                float blurContribution = (r + l + d + u + rd + dl + lu + ur + c) * 0.12774655;
                float smoothedMask = smoothstep(_Sharpening, 1, lerp(c, blurContribution, _MaskFeathering));
                float4 result = color * smoothedMask;

                // Despill
                float v = (2 * result.b + result.r) * 0.25;
                result.g = result.g > v ? lerp(result.g, v, _Despill) : result.g;
                
                float4 dif = color - result;
                float desaturatedDif = RGB2Y(dif.xyz);
                result += lerp(0, desaturatedDif, _DespillLuminanceAdd);
                
                float4 finalColor = float4(result.xyz, smoothedMask) * _TintColor;
                finalColor.rgb = MixFog(finalColor.rgb, input.fogCoord);
                
                return finalColor;
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0
            #pragma multi_compile_shadowcaster

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShaderVariablesFunctions.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "ChromaKeyUtils.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _MainTex_TexelSize;
                float4 _KeyColor;
                float4 _TintColor;
                float _ColorCutoff;
                float _ColorFeathering;
                float _MaskFeathering;
                float _Sharpening;
                float _Despill;
                float _DespillLuminanceAdd;
            CBUFFER_END

            float3 _LightDirection;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(float3(0, 0, -1));
                output.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
                output.uv = input.uv;
                
                #if UNITY_REVERSED_Z
                    output.positionCS.z = min(output.positionCS.z, output.positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #else
                    output.positionCS.z = max(output.positionCS.z, output.positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #endif
                
                return output;
            }

            float4 ShadowPassFragment(Varyings input) : SV_TARGET
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                
                float mask = GetChromaKeyMask(input.uv, TEXTURE2D_ARGS(_MainTex, sampler_MainTex), _KeyColor, _ColorCutoff, _ColorFeathering);
                clip(mask - 0.5);
                
                return 0;
            }
            ENDHLSL
        }
    }
    
    FallBack "Universal Render Pipeline/Unlit"
}