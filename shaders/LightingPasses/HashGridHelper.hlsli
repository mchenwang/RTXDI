#ifndef HASH_GRID_HELPER_HLSLI
#define HASH_GRID_HELPER_HLSLI

static const uint3 GRID_DIMENSIONS = uint3(ENV_GUID_GRID_DIMENSIONS, ENV_GUID_GRID_DIMENSIONS, ENV_GUID_GRID_DIMENSIONS);
static const uint GRID_SIZE = GRID_DIMENSIONS.x * GRID_DIMENSIONS.y * GRID_DIMENSIONS.z;

int3 GetUniformGridCell(float3 wsPosition, float cellSize)
{
    return floor(wsPosition / cellSize);
}

uint GetUniformGridCellHashId(int3 cell)
{
    const uint p1 = 73856093;   // some large primes 
    const uint p2 = 19349663;
    const uint p3 = 83492791;
    uint hashId = p1 * cell.x ^ p2 * cell.y ^ p3 * cell.z;
    hashId %= GRID_SIZE;
    return hashId;
}

uint GetUniformGridCellHashId(float3 wsPosition, float cellSize = 0.5f)
{
    return GetUniformGridCellHashId(GetUniformGridCell(wsPosition, cellSize));
}

uint HashInt(int value)
{
    // value = ((value >> 16) ^ value) * 0x45d9f3b;
    // value = ((value >> 16) ^ value) * 0x45d9f3b;
    // value = (value >> 16) ^ value;
    // return value;
    return abs(value % 1000000007);
}

uint ASH_Hs(float3 p, float s)
{
    // return HashInt(floor(p.x / s) + HashInt(floor(p.y / s) + HashInt(floor(p.z / s))));
    return GetUniformGridCellHashId(p, 1.f / s);
}

uint ASH_Hs_star(float3 p, int s)
{
    return ASH_Hs(p, s - 1) + (floor(p.x / s) % 2) + 2 * (floor(p.y / s) % 2) + 4 * (floor(p.z / s) % 2);
}

float ASH_F(float x, int s, int n)
{
    const float c_pi = 3.1415926535f;
    // n = 1;
    // s = 0.1f;
    // return sin((x * n) / s);
    return sin(x * 2 * c_pi * n / s);
}

uint AdvanceSpatialHash(float3 p, int s)
{
    float3 a = float3(1.f / s, 0.f, 0.f);
    // float a = 1.f / s;
    float3 wave = float3(ASH_F((p.x), s, 3), ASH_F((p.y), s, 5), ASH_F((p.z), s, 7));
    return ASH_Hs_star(p + a * wave, s);
}
#endif