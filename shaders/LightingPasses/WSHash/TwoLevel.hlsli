#ifndef ONE_LEVEL_WORLD_SPACE_HASH_HLSLI
#define ONE_LEVEL_WORLD_SPACE_HASH_HLSLI

#include "HashBase.hlsli"

#define HASH_GRID_POSITION_BIT_NUM          9
#define HASH_GRID_POSITION_BIT_MASK         ((1u << HASH_GRID_POSITION_BIT_NUM) - 1)
#define HASH_GRID_LEVEL_BIT_NUM             4
#define HASH_GRID_LEVEL_BIT_MASK            ((1u << HASH_GRID_LEVEL_BIT_NUM) - 1)
#define HASH_GRID_NORMAL_BIT_NUM            3
#define HASH_GRID_NORMAL_BIT_MASK           ((1u << HASH_GRID_NORMAL_BIT_NUM) - 1)
#define HASH_GRID_HASH_MAP_BUCKET_SIZE      32
#define HASH_GRID_INVALID_HASH_KEY          0
#define HASH_GRID_ALLOW_COMPACTION          (HASH_GRID_HASH_MAP_BUCKET_SIZE == 32)
#define HASH_GRID_SUB_CELL_NUM              1
// #define HASH_GRID_SUB_CELL_NUM              WORLD_GRID_SUB_CELL_NUM

typedef uint2 CacheEntry;
typedef uint  SubLevelHashKey;
typedef uint2 HashKey;

static const uint S_HASH_MAP_CAPACITY = GRID_SIZE / HASH_GRID_SUB_CELL_NUM;

uint GetBaseSlot(uint slot)
{
#if HASH_GRID_ALLOW_COMPACTION
    return (slot / HASH_GRID_HASH_MAP_BUCKET_SIZE) * HASH_GRID_HASH_MAP_BUCKET_SIZE;
#else // !HASH_GRID_ALLOW_COMPACTION
    return slot;
#endif // !HASH_GRID_ALLOW_COMPACTION
}

uint Hash32(uint val)
{
    return HashJenkins32(val);
}

uint GetGridLevel(float viewDepth)
{
    // return clamp(floor(LogBase(viewDepth, 20)), 0, HASH_GRID_LEVEL_BIT_MASK);
    if (viewDepth < 25.f) return 0;
    return clamp((viewDepth - 25.f) / 10.f, 1, HASH_GRID_LEVEL_BIT_MASK);
}

float GetVoxelSize(uint gridLevel, float scale)
{
    return scale * pow(2, gridLevel);
}

int3 CalculateGridPosition(float3 samplePosition, uint gridLevel, float scale)
{
    float voxelSize    = GetVoxelSize(gridLevel, scale);
    int3  gridPosition = floor(samplePosition / voxelSize);

    return gridPosition;
}

int4 CalculateGridPositionLog(float3 samplePosition, float viewDepth, float scale)
{
    uint  gridLevel    = GetGridLevel(viewDepth);
    float voxelSize    = GetVoxelSize(gridLevel, scale);
    int3  gridPosition = floor(samplePosition / voxelSize);

    return int4(gridPosition.xyz, gridLevel);
}

HashKey ComputeSpatialHash(int3 gridPosition, float3 normal, uint gridLevel)
{
    HashKey hashKey;
    hashKey.x = (((SubLevelHashKey)gridPosition.x & HASH_GRID_POSITION_BIT_MASK) << (HASH_GRID_POSITION_BIT_NUM * 0))
                | (((SubLevelHashKey)gridPosition.y & HASH_GRID_POSITION_BIT_MASK) << (HASH_GRID_POSITION_BIT_NUM * 1))
                | (((SubLevelHashKey)gridPosition.z & HASH_GRID_POSITION_BIT_MASK) << (HASH_GRID_POSITION_BIT_NUM * 2))
                | (((SubLevelHashKey)gridLevel & HASH_GRID_LEVEL_BIT_MASK) << (HASH_GRID_POSITION_BIT_NUM * 3));
    hashKey.y = (normal.x >= 0 ? 1 : 0) +
                (normal.y >= 0 ? 2 : 0) +
                (normal.z >= 0 ? 4 : 0);

    return hashKey;
}

HashKey ComputeSpatialHash(float3 samplePosition, float3 sampleNormal, float viewDepth, float scale)
{
    int4 gridPosition = CalculateGridPositionLog(samplePosition, viewDepth, scale);
    
    return ComputeSpatialHash(gridPosition.xyz, sampleNormal, gridPosition.w);
}

HashKey ComputeSpatialHash(float3 samplePosition, float3 sampleNormal, uint gridLevel, float scale)
{
    int3 gridPosition = asuint(CalculateGridPosition(samplePosition, gridLevel, scale));

    return ComputeSpatialHash(gridPosition, sampleNormal, gridLevel);
}

void AtomicCompareExchangeL1(in uint dstOffset, in SubLevelHashKey compareValue, in SubLevelHashKey value, out SubLevelHashKey originalValue)
{
    InterlockedCompareExchange(u_GridHashMap[dstOffset], compareValue, value, originalValue);
}

// void AtomicCompareExchangeL2(in uint dstOffset, in SubLevelHashKey compareValue, in SubLevelHashKey value, out SubLevelHashKey originalValue)
// {
//     InterlockedCompareExchange(u_GridNormalUnorderedMap[dstOffset], compareValue, value, originalValue);
// }

bool HashMapInsert(const HashKey hashKey, out CacheEntry cacheEntry)
{
    uint    hash        = Hash32(hashKey.x);
    uint    slot        = hash % S_HASH_MAP_CAPACITY;
    uint    initSlot    = slot;
    HashKey prevHashKey = HASH_GRID_INVALID_HASH_KEY;

    const uint baseSlot = GetBaseSlot(slot);
    for (uint bucketOffset = 0; bucketOffset < HASH_GRID_HASH_MAP_BUCKET_SIZE && baseSlot + bucketOffset < S_HASH_MAP_CAPACITY; ++bucketOffset)
    {
        AtomicCompareExchangeL1(baseSlot + bucketOffset, HASH_GRID_INVALID_HASH_KEY, hashKey.x, prevHashKey.x);

        if (prevHashKey.x == HASH_GRID_INVALID_HASH_KEY || prevHashKey.x == hashKey.x)
        {
            cacheEntry.x = baseSlot + bucketOffset;
            cacheEntry.y = hashKey.y;
            return true;
        }
    }

    cacheEntry = 0;
    return false;
}

bool HashMapFind(const HashKey hashKey, inout CacheEntry cacheEntry)
{
    uint    hash        = Hash32(hashKey.x);
    uint    slot        = hash % S_HASH_MAP_CAPACITY;

    const uint baseSlot = GetBaseSlot(slot);
    for (uint bucketOffset = 0; bucketOffset < HASH_GRID_HASH_MAP_BUCKET_SIZE && baseSlot + bucketOffset < S_HASH_MAP_CAPACITY; ++bucketOffset)
    {
        SubLevelHashKey storedHashKey = u_GridHashMap[baseSlot + bucketOffset];

        if (storedHashKey == hashKey.x)
        {
            cacheEntry.x = baseSlot + bucketOffset;
            cacheEntry.y = hashKey.y;
            return true;
        }
#if HASH_GRID_ALLOW_COMPACTION
        else if (storedHashKey == HASH_GRID_INVALID_HASH_KEY)
        {
            return false;
        }
#endif // HASH_GRID_ALLOW_COMPACTION
    }

    return false;
}

bool TryInsertEntry(float3 samplePosition, float3 sampleNormal, float viewDepth, float scale, out CacheEntry o_cacheEntry)
{
    CacheEntry cacheEntry = 0;
    HashKey hashKey = ComputeSpatialHash(samplePosition, sampleNormal, viewDepth, scale);
    bool successful = HashMapInsert(hashKey, cacheEntry);

    o_cacheEntry = cacheEntry;
    return successful;
}

bool FindEntry(float3 samplePosition, float3 sampleNormal, float viewDepth, float scale, out CacheEntry o_cacheEntry)
{
    CacheEntry cacheEntry = 0;
    HashKey hashKey = ComputeSpatialHash(samplePosition, sampleNormal, viewDepth, scale);
    bool successful = HashMapFind(hashKey, cacheEntry);

    o_cacheEntry = cacheEntry;
    return successful;
}

bool TryInsertEntry(float3 samplePosition, float3 sampleNormal, uint gridLevel, float scale, out CacheEntry o_cacheEntry)
{
    CacheEntry cacheEntry = 0;
    HashKey hashKey = ComputeSpatialHash(samplePosition, sampleNormal, gridLevel, scale);
    bool successful = HashMapInsert(hashKey, cacheEntry);

    o_cacheEntry = cacheEntry;
    return successful;
}

bool FindEntry(float3 samplePosition, float3 sampleNormal, uint gridLevel, float scale, out CacheEntry o_cacheEntry)
{
    CacheEntry cacheEntry = 0;
    HashKey hashKey = ComputeSpatialHash(samplePosition, sampleNormal, gridLevel, scale);
    bool successful = HashMapFind(hashKey, cacheEntry);

    o_cacheEntry = cacheEntry;
    return successful;
}

bool TryInsertEntry(HashKey hashKey, out CacheEntry o_cacheEntry)
{
    CacheEntry cacheEntry = 0;
    bool successful = HashMapInsert(hashKey, cacheEntry);

    o_cacheEntry = cacheEntry;
    return successful;
}

bool FindEntry(HashKey hashKey, out CacheEntry o_cacheEntry)
{
    CacheEntry cacheEntry = 0;
    bool successful = HashMapFind(hashKey, cacheEntry);

    o_cacheEntry = cacheEntry;
    return successful;
}

// Debug functions
float3 GetColorFromHash32(uint hash)
{
    float3 color;
    color.x = ((hash >>  0) & 0x3ff) / 1023.0f;
    color.y = ((hash >> 11) & 0x7ff) / 2047.0f;
    color.z = ((hash >> 22) & 0x7ff) / 2047.0f;

    return color;
}

// Debug visualization
float3 HashGridDebugColoredHash(float3 samplePosition, float3 sampleNormal, float viewDepth, float scale)
{
    HashKey hashKey = ComputeSpatialHash(samplePosition, sampleNormal, viewDepth, scale);

    return GetColorFromHash32(Hash32(hashKey.x));
}


#endif