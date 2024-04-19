#ifndef HASH_GRID_HELPER_HLSLI
#define HASH_GRID_HELPER_HLSLI

static const uint3 GRID_DIMENSIONS = uint3(ENV_GUID_GRID_DIMENSIONS, ENV_GUID_GRID_DIMENSIONS, ENV_GUID_GRID_DIMENSIONS);
static const uint GRID_SIZE = GRID_DIMENSIONS.x * GRID_DIMENSIONS.y * GRID_DIMENSIONS.z;

int3 GetUniformGridCell(float3 wsPosition, float cellSize)
{
    return floor(wsPosition / cellSize);
}

uint HashJenkins32(uint a)
{
    a = (a + 0x7ed55d16) + (a << 12);
    a = (a ^ 0xc761c23c) ^ (a >> 19);
    a = (a + 0x165667b1) + (a << 5);
    a = (a + 0xd3a2646c) ^ (a << 9);
    a = (a + 0xfd7046c5) + (a << 3);
    a = (a ^ 0xb55a4f09) ^ (a >> 16);
    return a;
}

uint GetUniformGridCellHashId(int3 cell)
{
    const uint p1 = 73856093;   // some large primes 
    const uint p2 = 19349663;
    const uint p3 = 83492791;
    uint hashId = (p1 * cell.x) ^ (p2 * cell.y) ^ (p3 * cell.z);
    // uint hashId = HashJenkins32(cell.x) ^ HashJenkins32(cell.y) ^ HashJenkins32(cell.z);

    hashId %= GRID_SIZE;
    return hashId;
}

uint ComputeSpatialHash(float3 wsPosition, float cellSize = 0.5f)
{
    return GetUniformGridCellHashId(GetUniformGridCell(wsPosition, cellSize));
}

#endif