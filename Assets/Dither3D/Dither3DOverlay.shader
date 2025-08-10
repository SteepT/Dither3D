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
        _BlackPoint ("Black Dither Range", Range(0,0.5)) = 0.33
        _WhitePoint ("White Dither Range", Range(0,0.5)) = 0.33
        _BlackClampMix ("Black Clamp Mix", Range(0,1)) = 0
        _WhiteClampMix ("White Clamp Mix", Range(0,1)) = 0

        _ReferenceRes ("Reference Screen Height", Float) = 1080

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
            float _BlackPoint;
            float _WhitePoint;
            float _BlackClampMix;
            float _WhiteClampMix;
            float _ReferenceRes;

            fixed ProcessDitherChannel(fixed c, float2 uv, float4 screenPos, float2 dx, float2 dy)
            {
                if (c < _BlackPoint)
                {
                    float b = c / max(_BlackPoint, 1e-5);
                    fixed d = GetDither3D_(uv, screenPos, dx, dy, b).x;
                    float dithered = _BlackPoint * d;
                    return lerp(dithered, c, _BlackClampMix);
                }
                else if (c > 1.0 - _WhitePoint)
                {
                    float b = (c - (1.0 - _WhitePoint)) / max(_WhitePoint, 1e-5);
                    fixed d = GetDither3D_(uv, screenPos, dx, dy, b).x;
                    float dithered = (1.0 - _WhitePoint) + _WhitePoint * d;
                    return lerp(dithered, c, _WhiteClampMix);
                }
                else
                {
                    return c;
                }
            }

            fixed4 GetOverlayDitherColor_(float2 uv_DitherTex, float4 screenPos, float2 dx, float2 dy, fixed4 color)
            {
                color.rgb = saturate(color.rgb * _InputExposure + _InputOffset);

                #ifdef DITHERCOL_GRAYSCALE
                    fixed brightness = GetGrayscale(color);
                    brightness = ProcessDitherChannel(brightness, uv_DitherTex, screenPos, dx, dy);
                    color.rgb = brightness;
                #elif DITHERCOL_RGB
                    color.r = ProcessDitherChannel(color.r, uv_DitherTex, screenPos, dx, dy);
                    color.g = ProcessDitherChannel(color.g, uv_DitherTex, screenPos, dx, dy);
                    color.b = ProcessDitherChannel(color.b, uv_DitherTex, screenPos, dx, dy);
                #elif DITHERCOL_CMYK
                    fixed4 cmyk = RGBtoCMYK(color.rgb);
                    cmyk.x = ProcessDitherChannel(cmyk.x, RotateUV(uv_DitherTex, float2(0.966, 0.259)), screenPos, dx, dy);
                    cmyk.y = ProcessDitherChannel(cmyk.y, RotateUV(uv_DitherTex, float2(0.259, 0.966)), screenPos, dx, dy);
                    cmyk.z = ProcessDitherChannel(cmyk.z, RotateUV(uv_DitherTex, float2(1.000, 0.000)), screenPos, dx, dy);
                    cmyk.w = ProcessDitherChannel(cmyk.w, RotateUV(uv_DitherTex, float2(0.707, 0.707)), screenPos, dx, dy);
                    color.rgb = CMYKtoRGB(cmyk);
                #endif

                return color;
            }

            fixed4 GetOverlayDitherColor(float2 uv_DitherTex, float4 screenPos, fixed4 color)
            {
                float scale = _ScreenParams.y / _ReferenceRes;
                float2 dx = ddx(uv_DitherTex) * scale;
                float2 dy = ddy(uv_DitherTex) * scale;
                return GetOverlayDitherColor_(uv_DitherTex, screenPos, dx, dy, color);
            }

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
                fixed4 ditherCol = GetOverlayDitherColor(i.uv, i.screenPos, baseCol);
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
