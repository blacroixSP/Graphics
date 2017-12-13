#include "LightweightCore.hlsl"
#include "LightweightSurfaceInput.hlsl"

#if defined (_COLORADDSUBDIFF_ON)
half4 _ColorAddSubDiff;
#endif

#if defined(_COLORCOLOR_ON)
half3 RGBtoHSV(half3 arg1)
{
    half4 K = half4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    half4 P = lerp(half4(arg1.bg, K.wz), half4(arg1.gb, K.xy), step(arg1.b, arg1.g));
    half4 Q = lerp(half4(P.xyw, arg1.r), half4(arg1.r, P.yzx), step(P.x, arg1.r));
    half D = Q.x - min(Q.w, Q.y);
    half E = 1e-10;
    return half3(abs(Q.z + (Q.w - Q.y) / (6.0 * D + E)), D / (Q.x + E), Q.x);
}

half3 HSVtoRGB(half3 arg1)
{
    half4 K = half4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    half3 P = abs(frac(arg1.xxx + K.xyz) * 6.0 - K.www);
    return arg1.z * lerp(K.xxx, saturate(P - K.xxx), arg1.y);
}
#endif

// Color function
#if defined(UNITY_PARTICLE_INSTANCING_ENABLED)
#define vertColor(c) \
        vertInstancingColor(c);
#else
#define vertColor(c)
#endif

// Flipbook vertex function
#if defined(UNITY_PARTICLE_INSTANCING_ENABLED)
#if defined(_FLIPBOOK_BLENDING)
#define vertTexcoord(v, o) \
        vertInstancingUVs(v.texcoords.xy, o.texcoord, o.texcoord2AndBlend);
#else
#define vertTexcoord(v, o) \
        vertInstancingUVs(v.texcoords.xy, o.texcoord); \
        o.texcoord = TRANSFORM_TEX(o.texcoord, _MainTex);
#endif
#else
#if defined(_FLIPBOOK_BLENDING)
#define vertTexcoord(v, o) \
        o.texcoord = v.texcoords.xy; \
        o.texcoord2AndBlend.xy = v.texcoords.zw; \
        o.texcoord2AndBlend.z = v.texcoordBlend;
#else
#define vertTexcoord(v, o) \
        o.texcoord = TRANSFORM_TEX(v.texcoords.xy, _MainTex);
#endif
#endif

// Fading vertex function
#if defined(SOFTPARTICLES_ON) || defined(_FADING_ON)
#define vertFading(o) \
    o.projectedPosition = ComputeScreenPos (clipPosition); \
    COMPUTE_EYEDEPTH(o.projectedPosition.z);
#else
#define vertFading(o)
#endif

// Color blending fragment function
#if defined(_COLOROVERLAY_ON)
#define fragColorMode(albedo, color) \
    albedo.rgb = lerp(1 - 2 * (1 - albedo.rgb) * (1 - i.color.rgb), 2 * albedo.rgb * i.color.rgb, step(albedo.rgb, 0.5)); \
    albedo.a *= i.color.a;
#elif defined(_COLORCOLOR_ON)
#define fragColorMode(i) \
    half3 aHSL = RGBtoHSV(albedo.rgb); \
    half3 bHSL = RGBtoHSV(i.color.rgb); \
    half3 rHSL = half3(bHSL.x, bHSL.y, aHSL.z); \
    albedo = half4(HSVtoRGB(rHSL), albedo.a * i.color.a);
#elif defined(_COLORADDSUBDIFF_ON)
#define fragColorMode(i) \
    albedo.rgb = albedo.rgb + i.color.rgb * _ColorAddSubDiff.x; \
    albedo.rgb = lerp(albedo.rgb, abs(albedo.rgb), _ColorAddSubDiff.y); \
    albedo.a *= i.color.a;
#else
#define fragColorMode(i) \
    albedo *= i.color;
#endif

// Pre-multiplied alpha helper
#if defined(_ALPHAPREMULTIPLY_ON)
#define ALBEDO_MUL albedo
#else
#define ALBEDO_MUL albedo.a
#endif

// Soft particles fragment function
#if defined(SOFTPARTICLES_ON) && defined(_FADING_ON)
#define fragSoftParticles(i) \
    if (SOFT_PARTICLE_NEAR_FADE > 0.0 || SOFT_PARTICLE_INV_FADE_DISTANCE > 0.0) \
    { \
        float sceneZ = LinearEyeDepth (SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(i.projectedPosition))); \
        float fade = saturate (SOFT_PARTICLE_INV_FADE_DISTANCE * ((sceneZ - SOFT_PARTICLE_NEAR_FADE) - i.projectedPosition.z)); \
        ALBEDO_MUL *= fade; \
    }
#else
#define fragSoftParticles(i)
#endif

// Camera fading fragment function
#if defined(_FADING_ON)
#define fragCameraFading(i) \
    float cameraFade = saturate((i.projectedPosition.z - CAMERA_NEAR_FADE) * CAMERA_INV_FADE_DISTANCE); \
    ALBEDO_MUL *= cameraFade;
#else
#define fragCameraFading(i)
#endif

// Vertex shader input
struct appdata_particles
{
    float4 vertex : POSITION;
    float3 normal : NORMAL;
    half4 color : COLOR;
#if defined(_FLIPBOOK_BLENDING) && !defined(UNITY_PARTICLE_INSTANCING_ENABLED)
    float4 texcoords : TEXCOORD0;
    float texcoordBlend : TEXCOORD1;
#else
    float2 texcoords : TEXCOORD0;
#endif
#if defined(_NORMALMAP)
    float4 tangent : TANGENT;
#endif
};

struct VertexOutputLit
{
    half4 color                     : COLOR;
    float2 texcoord                 : TEXCOORD0;
#if _NORMALMAP
    half3 tangent                   : TEXCOORD1;
    half3 binormal                  : TEXCOORD2;
    half3 normal                    : TEXCOORD3;
#else
    half3 normal                    : TEXCOORD1;
#endif

#if defined(_FLIPBOOK_BLENDING)
    float3 texcoord2AndBlend        : TEXCOORD4;
#endif
#if defined(SOFTPARTICLES_ON) || defined(_FADING_ON)
    float4 projectedPosition        : TEXCOORD5;
#endif
    float4 posWS                    : TEXCOORD6; // xyz: position; w = fogFactor;
    float4 clipPos                  : SV_POSITION;
};

half4 readTexture(TEXTURE2D_ARGS(_Texture, sampler_Texture), VertexOutputLit IN)
{
    half4 color = SAMPLE_TEXTURE2D(_Texture, sampler_Texture, IN.texcoord);
#ifdef _FLIPBOOK_BLENDING
    half4 color2 = SAMPLE_TEXTURE2D(_Texture, sampler_Texture, IN.texcoord2AndBlend.xy);
    color = lerp(color, color2, IN.texcoord2AndBlend.z);
#endif
    return color;
}

void InitializeSurfaceData(VertexOutputLit IN, out SurfaceData surfaceData)
{
    half4 albedo = readTexture(_MainTex, sampler_MainTex, IN) * IN.color;

    // No distortion Support
    fragColorMode(IN);
    fragSoftParticles(IN);
    fragCameraFading(IN);

#if defined(_METALLICGLOSSMAP)
    half2 metallicGloss = readTexture(_MetallicGlossMap, sampler_MetallicGlossMap, IN).ra * half2(1.0, _Glossiness);
#else
    half2 metallicGloss = half2(_Metallic, _Glossiness);
#endif

#if defined(_NORMALMAP)
    float3 normal = normalize(UnpackNormalScale(readTexture(_BumpMap, sampler_BumpMap, IN), _BumpScale));
#else
    float3 normal = float3(0, 0, 1);
#endif

#if defined(_EMISSION)
    half3 emission = readTexture(_EmissionMap, sampler_EmissionMap, IN).rgb;
#else
    half3 emission = 0;
#endif

    surfaceData.albedo = albedo.rbg;
    surfaceData.specular = half3(0, 0, 0);
    surfaceData.normal = normal;
    surfaceData.emission = emission * _EmissionColor.rgb;
    surfaceData.metallic = metallicGloss.r;
    surfaceData.smoothness = metallicGloss.g;
    surfaceData.occlusion = 1.0;

#if defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON) || defined(_ALPHAOVERLAY_ON)
    surfaceData.alpha = albedo.a;
#else
    surfaceData.alpha = 1;
#endif

#if defined(_ALPHAMODULATE_ON)
    surfaceData.albedo = lerp(half3(1.0, 1.0, 1.0), surfaceData.albedo, surfaceData.alpha);
#endif

#if defined(_ALPHATEST_ON)
    clip(surfaceData.alpha - _Cutoff + 0.0001);
#endif

}
