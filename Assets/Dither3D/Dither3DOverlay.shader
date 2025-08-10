Shader "Dither 3D/Overlay"
{
    Properties
    {
        [Header(Dither Input Brightness)]
        _InputExposure ("Exposure", Range(0,5)) = 1
        _InputOffset ("Offset", Range(-1,1)) = 0

        [Header(Dither Settings)]
        [DitherPatternProperty] _DitherMode ("Pattern", Int) = 3
        [HideInInspector] _DitherTex ("Dither 3D Texture", 3D) = "" {}
        [HideInInspector] _DitherRampTex ("Dither Ramp Texture", 2D) = "white" {}
        _Scale ("Dot Scale", Range(2,10)) = 5.0
        _SizeVariability ("Dot Size Variability", Range(0,1)) = 0
        _Contrast ("Dot Contrast", Range(0,2)) = 1
        _StretchSmoothness ("Stretch Smoothness", Range(0,2)) = 1

        [Header(Stylized Regions)]
        _ShadowThreshold ("Shadow Threshold", Range(0,0.5)) = 0.33
        _HighlightThreshold ("Highlight Threshold", Range(0,0.5)) = 0.33
        _BlackClamp ("Black Clamp Mix", Range(0,1)) = 0
        _WhiteClamp ("White Clamp Mix", Range(0,1)) = 0

        [Header(Blend Mode)]
        _BlendMode ("Blend Mode", Int) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }

        GrabPass { }

        Pass
        {
            Name "DitherOverlay"
            ZWrite Off
            ZTest Equal

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.5
            #pragma multi_compile __ DITHERCOL_GRAYSCALE DITHERCOL_RGB DITHERCOL_CMYK
            #pragma multi_compile __ INVERSE_DOTS
            #pragma multi_compile __ RADIAL_COMPENSATION
            #pragma multi_compile __ QUANTIZE_LAYERS
            #pragma multi_compile __ DEBUG_FRACTAL

            #include "UnityCG.cginc"
            #include "Dither3DInclude.cginc"

            sampler2D _GrabTexture;
            int _BlendMode;
            float _ShadowThreshold;
            float _HighlightThreshold;
            float _BlackClamp;
            float _WhiteClamp;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float4 screenPos : TEXCOORD1;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                o.screenPos = ComputeScreenPos(o.pos);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 baseCol = tex2Dproj(_GrabTexture, UNITY_PROJ_COORD(i.screenPos));
                fixed brightness = dot(baseCol.rgb, fixed3(0.299, 0.587, 0.114));

                fixed4 ditherCol;
                if (brightness < _ShadowThreshold)
                {
                    fixed4 shadowCol = lerp(fixed4(0,0,0, baseCol.a), baseCol, _BlackClamp);
                    ditherCol = GetDither3DColor(i.uv, i.screenPos, shadowCol);
                }
                else if (brightness > 1.0 - _HighlightThreshold)
                {
                    fixed4 highlightCol = lerp(fixed4(1,1,1, baseCol.a), baseCol, _WhiteClamp);
                    ditherCol = GetDither3DColor(i.uv, i.screenPos, highlightCol);
                }
                else
                {
                    return baseCol;
                }

                fixed4 result;
                if (_BlendMode == 1)
                {
                    // Linear Burn: result = base + dither - 1
                    result.rgb = saturate(baseCol.rgb + ditherCol.rgb - 1);
                    result.a = baseCol.a;
                }
                else if (_BlendMode == 2)
                {
                    // Linear Light: result = base + 2*dither - 1
                    result.rgb = saturate(baseCol.rgb + 2 * ditherCol.rgb - 1);
                    result.a = baseCol.a;
                }
                else
                {
                    // Replace with dithered color
                    result = ditherCol;
                }
                return result;
            }
            ENDCG
        }
    }
    FallBack Off
}
