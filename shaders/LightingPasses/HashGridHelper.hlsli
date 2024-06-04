#ifndef HASH_GRID_HELPER_HLSLI
#define HASH_GRID_HELPER_HLSLI

static const uint GRID_SIZE = WORLD_GRID_SIZE;

#include "WSHash/TwoLevel.hlsli"

struct GridEntry
{
    uint gridId;
    uint subCellIndex;
    uint gridLevel;
};

bool InsertGridEntry(float3 samplePos, float3 gridNormal, float viewDepth, float gridScale, out GridEntry o_entry)
{
    CacheEntry hashEntry = 0;
    uint gridLevel = GetGridLevel(viewDepth);
    if (!TryInsertEntry(samplePos, gridNormal, gridLevel, gridScale, hashEntry))
        return false;

    o_entry.gridId = hashEntry.x;
    o_entry.subCellIndex = hashEntry.y;
    o_entry.gridLevel = gridLevel;
    return true;
}

bool FindGridEntry(float3 samplePos, float3 gridNormal, float viewDepth, float gridScale, out GridEntry o_entry)
{
    CacheEntry hashEntry = 0;
    uint gridLevel = GetGridLevel(viewDepth);
    if (!FindEntry(samplePos, gridNormal, gridLevel, gridScale, hashEntry))
        return false;

    o_entry.gridId = hashEntry.x;
    o_entry.subCellIndex = hashEntry.y;
    o_entry.gridLevel = gridLevel;
    return true;
}

bool InsertGridEntry(float3 samplePos, float3 gridNormal, uint gridLevel, float gridScale, out GridEntry o_entry)
{
    CacheEntry hashEntry = 0;
    if (!TryInsertEntry(samplePos, gridNormal, gridLevel, gridScale, hashEntry))
        return false;

    o_entry.gridId = hashEntry.x;
    o_entry.subCellIndex = hashEntry.y;
    o_entry.gridLevel = gridLevel;
    return true;
}

bool FindGridEntry(float3 samplePos, float3 gridNormal, uint gridLevel, float gridScale, out GridEntry o_entry)
{
    CacheEntry hashEntry = 0;
    if (!FindEntry(samplePos, gridNormal, gridLevel, gridScale, hashEntry))
        return false;

    o_entry.gridId = hashEntry.x;
    o_entry.subCellIndex = hashEntry.y;
    o_entry.gridLevel = gridLevel;
    return true;
}

#endif