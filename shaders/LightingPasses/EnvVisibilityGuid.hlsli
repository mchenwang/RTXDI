#ifndef ENV_VISIBILITY_HLSLI
#define ENV_VISIBILITY_HLSLI

// #include "HashGridHelper.hlsli"

// // Assume normalized input on +Z hemisphere.
// // Output is on [-1, 1].
// float2 EncodeHemioct(in float3 v)
// {
// 	// Project the hemisphere onto the hemi-octahedron,
// 	// and then into the xy plane
// 	float2 p = v.xy * (1.0 / (abs(v.x) + abs(v.y) + v.z));
// 	// Rotate and scale the center diamond to the unit square
// 	return float2(p.x + p.y, p.x - p.y);
// }
// float3 DecodeHemioct(float2 e)
// {
// 	// Rotate and scale the unit square back to the center diamond
// 	float2 temp = float2(e.x + e.y, e.x - e.y) * 0.5;
// 	float3 v = float3(temp, 1.0 - abs(temp.x) - abs(temp.y));
// 	return normalize(v);
// }

// uint GetInnerPixelIndexByHemioctTexcoord(float2 tex)
// {
//     uint x = clamp(floor(tex.x * 6), 0, 5);
//     uint y = clamp(floor(tex.y * 6), 0, 5);
//     uint pixelIndex = y * 6 + x;

//     return pixelIndex;
// }

// float3 GetDirectionByInnerPixelIndex(uint index, float2 jitter)
// {
//     float2 hemioctTex;
//     hemioctTex = (float2(index % 6, index / 6) + jitter) / float2(6.f, 6.f);

// 	return DecodeHemioct(hemioctTex);
// }

// float2 GetSphereTexcoordByInnerPixelIndex(uint index, float2 jitter)
// {
//     return (float2(index % 6, index / 6) + jitter) / float2(6.f, 6.f);
// }


// #ifdef RTXDI_APPLICATION_BRIDGE_HLSLI

// bool SampleEnvVisibilityMap(RAB_Surface surface, inout RAB_RandomSamplerState rng, out float2 uv, out float pdf)
// {
//     uint hashId = ComputeSpatialHash(surface.worldPos, 0.5f);
//     float xi = RAB_GetNextRandom(rng);
//     float offset = hashId * 6 * 6;
//     uint l = 0, r = 35;
//     // while (l < r)
//     // {
//     //     uint m = (l + r) >> 1;
//     //     if (u_EnvVisiblityCdfMap[offset + m] < xi) l = m + 1;
//     //     else r = m;
//     // }
//     for (; l <= 35; ++l) if (u_EnvVisiblityCdfMap[offset + l] >= xi) break;
//     if (l > 35 || u_EnvVisiblityCdfMap[offset + l] <= 0.f)
//     {
//         float3 p;
//         float u1 = RAB_GetNextRandom(rng);
//         float u2 = RAB_GetNextRandom(rng);
//         const float sin_theta = sqrt(u1);
//         const float phi = 2.0f * c_pi * u2;
//         const float c_1_pi = 1.f / c_pi;
//         p.x = sin_theta * cos(phi);
//         p.y = sin_theta * sin(phi);
//         p.z = sqrt(max(0.f, 1.f - sin_theta * sin_theta));

//         float3 tangent, bitangent;
//         branchlessONB(surface.normal, tangent, bitangent);

//         float3 dir = normalize(tangent * p.x + bitangent * p.y + surface.normal * p.z);

//         uv = directionToEquirectUV(dir);
//         pdf = c_1_pi * sqrt(max(0.f, 1.f - sin_theta * sin_theta));
//         return true;
//     }

//     float2 jitter = float2(RAB_GetNextRandom(rng), RAB_GetNextRandom(rng));
//     float3 dirLocal = GetDirectionByInnerPixelIndex(l, jitter);

//     float3 tangent, bitangent;
//     branchlessONB(surface.normal, tangent, bitangent);
//     float3 dir = normalize(tangent * dirLocal.x + bitangent * dirLocal.y + surface.normal * dirLocal.z);

//     uv = directionToEquirectUV(dir);
//     pdf = u_EnvVisiblityCdfMap[offset + l] - 
//         (l == 0 ? 0 : u_EnvVisiblityCdfMap[offset + l - 1]);

//     return true;
// }

// void UpdateVisibilityMap(RAB_Surface surface, float3 dir, bool visible)
// {
//     if (!visible) return;

//     uint hashId = ComputeSpatialHash(surface.worldPos, 0.5f);

//     float3 tangent, bitangent;
//     branchlessONB(surface.normal, tangent, bitangent);
//     float3 dirLocal = float3(dot(dir, tangent), dot(dir, bitangent), dot(dir, surface.normal));

//     float2 hemioctTex = EncodeHemioct(normalize(dirLocal));

//     uint pixelIndex = GetInnerPixelIndexByHemioctTexcoord(hemioctTex);

//     InterlockedAdd(u_EnvVisiblityDataMap[hashId].total_cnt, 1);
//     InterlockedAdd(u_EnvVisiblityDataMap[hashId].local_cnt[pixelIndex], 1);
// }

// #endif
#endif