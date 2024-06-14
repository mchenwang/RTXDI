#ifndef HASH_GRID_HELPER_HLSLI
#define HASH_GRID_HELPER_HLSLI

static const uint3 GRID_DIMENSIONS = uint3(WORLD_GRID_DIMENSION, WORLD_GRID_DIMENSION, WORLD_GRID_DIMENSION);
static const uint GRID_SIZE = GRID_DIMENSIONS.x * GRID_DIMENSIONS.y * GRID_DIMENSIONS.z;

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

#if 1

#define HASH_GRID_POSITION_BIT_NUM          9
#define HASH_GRID_POSITION_BIT_MASK         ((1u << HASH_GRID_POSITION_BIT_NUM) - 1)
#define HASH_GRID_LEVEL_BIT_NUM             2
#define HASH_GRID_LEVEL_BIT_MASK            ((1u << HASH_GRID_LEVEL_BIT_NUM) - 1)
#define HASH_GRID_NORMAL_BIT_NUM            3
#define HASH_GRID_NORMAL_BIT_MASK           ((1u << HASH_GRID_NORMAL_BIT_NUM) - 1)
#define HASH_GRID_HASH_MAP_BUCKET_SIZE      32
#define HASH_GRID_INVALID_HASH_KEY          0
#define HASH_GRID_USE_NORMALS               1
#define HASH_GRID_ALLOW_COMPACTION          (HASH_GRID_HASH_MAP_BUCKET_SIZE == 32)

typedef uint CacheEntry;
// typedef uint64_t HashKey;
typedef uint HashKey;

static const uint  S_HASH_MAP_CAPACITY = GRID_SIZE;

float LogBase(float x, float base)
{
    return log(x) / log(base);
}

uint GetBaseSlot(uint slot)
{
#if HASH_GRID_ALLOW_COMPACTION
    return (slot / HASH_GRID_HASH_MAP_BUCKET_SIZE) * HASH_GRID_HASH_MAP_BUCKET_SIZE;
#else // !HASH_GRID_ALLOW_COMPACTION
    return slot;
#endif // !HASH_GRID_ALLOW_COMPACTION
}

uint Hash32(HashKey hashKey)
{
    return HashJenkins32(hashKey);
    // return HashJenkins32(uint((hashKey >> 0) & 0xffffffff))
    //      ^ HashJenkins32(uint((hashKey >> 32) & 0xffffffff));
}

uint GetGridLevel(float viewDepth)
{
    if (viewDepth < 30.f) return 0;
    return clamp((viewDepth - 30.f) / 10.f, 1, HASH_GRID_LEVEL_BIT_MASK);
}

float GetVoxelSize(uint gridLevel, float scale)
{
    return scale * pow(2, gridLevel);
}

int4 CalculateGridPositionLog(float3 samplePosition, float viewDepth, float scale)
{
    uint  gridLevel    = GetGridLevel(viewDepth);
    float voxelSize    = GetVoxelSize(gridLevel, scale);
    int3  gridPosition = floor(samplePosition / voxelSize);

    return int4(gridPosition.xyz, gridLevel);
}

HashKey ComputeSpatialHash(float3 samplePosition, float3 sampleNormal, float viewDepth, float scale)
{
    uint4 gridPosition = asuint(CalculateGridPositionLog(samplePosition, viewDepth, scale));

    HashKey hashKey = (((HashKey)gridPosition.x & HASH_GRID_POSITION_BIT_MASK) << (HASH_GRID_POSITION_BIT_NUM * 0))
                    | (((HashKey)gridPosition.y & HASH_GRID_POSITION_BIT_MASK) << (HASH_GRID_POSITION_BIT_NUM * 1))
                    | (((HashKey)gridPosition.z & HASH_GRID_POSITION_BIT_MASK) << (HASH_GRID_POSITION_BIT_NUM * 2))
                    | (((HashKey)gridPosition.w & HASH_GRID_LEVEL_BIT_MASK) << (HASH_GRID_POSITION_BIT_NUM * 3));

#if HASH_GRID_USE_NORMALS
    uint normalBits =
        (sampleNormal.x >= -0.001 ? 1 : 0) +
        (sampleNormal.y >= -0.001 ? 2 : 0) +
        (sampleNormal.z >= -0.001 ? 4 : 0);
    
    hashKey = (hashKey << 3) | normalBits;
    // hashKey |= ((HashKey)normalBits << (HASH_GRID_POSITION_BIT_NUM * 3 + HASH_GRID_LEVEL_BIT_NUM));
#endif // HASH_GRID_USE_NORMALS

    return hashKey;
}

void AtomicCompareExchange(in uint dstOffset, in HashKey compareValue, in HashKey value, out HashKey originalValue)
{
    InterlockedCompareExchange(u_GridHashMap[dstOffset], compareValue, value, originalValue);
    // const uint cLock = 0xAAAAAAAA;
    // uint fuse = 0;
    // const uint fuseLength = 8;
    // bool busy = true;
    // while (busy && fuse < fuseLength)
    // {
    //     uint state;
    //     InterlockedExchange(u_GridHashMapLockBuffer[dstOffset], cLock, state);
    //     busy = state != 0;

    //     if (state != cLock)
    //     {
    //         originalValue = u_GridHashMap[dstOffset];
    //         if (originalValue == compareValue)
    //             u_GridHashMap[dstOffset] = value;
    //         InterlockedExchange(u_GridHashMapLockBuffer[dstOffset], state, fuse);
    //         fuse = fuseLength;
    //     }
    //     ++fuse;
    // }
}

bool HashMapInsert(const HashKey hashKey, out CacheEntry cacheEntry)
{
    uint    hash        = Hash32(hashKey);
    uint    slot        = hash % S_HASH_MAP_CAPACITY;
    uint    initSlot    = slot;
    HashKey prevHashKey = HASH_GRID_INVALID_HASH_KEY;

    const uint baseSlot = GetBaseSlot(slot);
    uint maxLoopCnt = 32;
    while (--maxLoopCnt)
    // for (uint bucketOffset = 0; bucketOffset < HASH_GRID_HASH_MAP_BUCKET_SIZE && baseSlot + bucketOffset < S_HASH_MAP_CAPACITY; ++bucketOffset)
    {
        // AtomicCompareExchange(baseSlot + bucketOffset, HASH_GRID_INVALID_HASH_KEY, hashKey, prevHashKey);
        AtomicCompareExchange(slot, HASH_GRID_INVALID_HASH_KEY, hashKey, prevHashKey);

        if (prevHashKey == HASH_GRID_INVALID_HASH_KEY || prevHashKey == hashKey)
        {
            // cacheEntry = baseSlot + bucketOffset;
            cacheEntry = slot;
            return true;
        }

        hash = Hash32(hash);
        slot = hash % S_HASH_MAP_CAPACITY;
    }

    cacheEntry = 0;
    return false;
}

bool HashMapFind(const HashKey hashKey, inout CacheEntry cacheEntry)
{
    uint    hash        = Hash32(hashKey);
    uint    slot        = hash % S_HASH_MAP_CAPACITY;

    const uint baseSlot = GetBaseSlot(slot);
    uint maxLoopCnt = 32;
    while (--maxLoopCnt)
    // for (uint bucketOffset = 0; bucketOffset < HASH_GRID_HASH_MAP_BUCKET_SIZE && baseSlot + bucketOffset < S_HASH_MAP_CAPACITY; ++bucketOffset)
    {
        // HashKey storedHashKey = u_GridHashMap[baseSlot + bucketOffset];
        HashKey storedHashKey = u_GridHashMap[slot];

        if (storedHashKey == hashKey)
        {
            // cacheEntry = baseSlot + bucketOffset;
            cacheEntry = slot;
            return true;
        }

        hash = Hash32(hash);
        slot = hash % S_HASH_MAP_CAPACITY;
// #if HASH_GRID_ALLOW_COMPACTION
//         else if (storedHashKey == HASH_GRID_INVALID_HASH_KEY)
//         {
//             return false;
//         }
// #endif // HASH_GRID_ALLOW_COMPACTION
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

// Debug functions
float3 GetColorFromHash32(uint hash)
{
    float3 color;
    color.x = ((hash >>  0) & 0x7f) / 127.0f;
    color.y = ((hash >>  7) & 0x7f) / 127.0f;
    color.z = ((hash >> 14) & 0x7f) / 127.0f;

    return color;
}

// Debug visualization
float3 HashGridDebugColoredHash(float3 samplePosition, float3 sampleNormal, float viewDepth, float scale)
{
    HashKey hashKey = ComputeSpatialHash(samplePosition, sampleNormal, viewDepth, scale);

    return GetColorFromHash32(Hash32(hashKey) % S_HASH_MAP_CAPACITY);
}
#endif


#endif