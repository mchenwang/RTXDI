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

uint GetUniformGridCellHashId(int3 cell, float3 normal)
{
    const uint p1 = 73856093;   // some large primes 
    const uint p2 = 19349663;
    const uint p3 = 83492791;
    uint hashId = (p1 * cell.x) ^ (p2 * cell.y) ^ (p3 * cell.z);
    // uint hashId = HashJenkins32(cell.x) ^ HashJenkins32(cell.y) ^ HashJenkins32(cell.z);
    
    uint normalBits =
        (normal.x >= 0 ? 1 : 0) +
        (normal.y >= 0 ? 2 : 0) +
        (normal.z >= 0 ? 4 : 0);
    
    hashId = (normalBits << 27) | hashId;

    hashId %= GRID_SIZE;
    return hashId;
}


uint ComputeSpatialHash(float3 wsPosition, float3 normal, float scale)
{
    return GetUniformGridCellHashId(GetUniformGridCell(wsPosition, scale), normal);
}

#if 0

uint HashUInt(uint v)
{
    return HashJenkins32(v) % GRID_SIZE;
}

uint HashInt(int v)
{
    return HashJenkins32(abs(v)) % GRID_SIZE;
    // return HashJenkins32(v);
    // const uint p1 = 73856093;   // some large primes 
    // const uint p2 = 19349663;
    // const uint p3 = 83492791;
    // uint hashId = (p1 * v) ^ (p2 * v) ^ (p3 * v);
    // return hashId % GRID_SIZE;
    // // v = ~v + (v << 15); // v = (v << 15) - v - 1;
    // v = v ^ (v >> 12);
    // v = v + (v << 2);
    // v = v ^ (v >> 4);
    // v = v * 2057; // v = (v + (v << 3)) + (v << 11);
    // v = v ^ (v >> 16);
    // return v;
}

uint HashS(float3 p, float s)
{
    return HashUInt(floor(p.x / s) + HashUInt(floor(p.y / s) + HashInt(floor(p.z / s))));
    // int3 v = floor(p / s);
    // const uint p1 = 73856093;
    // const uint p2 = 19349663;
    // const uint p3 = 83492791;
    // uint hashId = (p1 * v.x) ^ (p2 * v.y) ^ (p3 * v.z);
    // return hashId;
}

uint HashSStar(float3 p, float s)
{
    // return ((HashS(p, s * 2.f) << 0) % (GRID_SIZE / 8)) + ((floor(p.x / s) % 2) + 2 * (floor(p.y / s) % 2) + 4 * (floor(p.z / s) % 2)) * (GRID_SIZE / 8);
    return ((HashS(p, s * 2.f) % (GRID_SIZE / 8)) << 3) + 
           (
                abs((floor(p.x / s)) % 2) +
                abs((floor(p.y / s)) % 2) * 2 +
                abs((floor(p.z / s)) % 2) * 4
           ) * (GRID_SIZE / 8);
}

float HashF(float p, float s, int n)
{
    // return sin(2.f * c_pi * p / n);
    return sin(p * 0.5f);
}

uint ComputeSpatialHash(float3 wsPosition, float3 normal, float scale)
{
    // return GetUniformGridCellHashId(GetUniformGridCell(wsPosition, scale), normal);
    float3 bais = float3(HashF(wsPosition.x, ceil(1.f / scale), 3),
                         HashF(wsPosition.y, ceil(1.f / scale), 3),
                         HashF(wsPosition.z, ceil(1.f / scale), 3));
    // return HashS(wsPosition, scale);
    // bais.yz = 0.f;
    float a = 0.f;
    return HashSStar(wsPosition + bais * a, scale) % GRID_SIZE;
}

#else

#define HASH_GRID_POSITION_BIT_NUM          17
#define HASH_GRID_POSITION_BIT_MASK         ((1u << HASH_GRID_POSITION_BIT_NUM) - 1)
#define HASH_GRID_LEVEL_BIT_NUM             10
#define HASH_GRID_LEVEL_BIT_MASK            ((1u << HASH_GRID_LEVEL_BIT_NUM) - 1)
#define HASH_GRID_NORMAL_BIT_NUM            3
#define HASH_GRID_NORMAL_BIT_MASK           ((1u << HASH_GRID_NORMAL_BIT_NUM) - 1)
#define HASH_GRID_HASH_MAP_BUCKET_SIZE      32
#define HASH_GRID_INVALID_HASH_KEY          0LL
#define HASH_GRID_USE_NORMALS               1
#define HASH_GRID_ALLOW_COMPACTION          (HASH_GRID_HASH_MAP_BUCKET_SIZE == 32)

typedef uint CacheEntry;
typedef uint64_t HashKey;

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
    // return hashKey;
    return HashJenkins32(uint((hashKey >> 0) & 0xffffffff))
         ^ HashJenkins32(uint((hashKey >> 32) & 0xffffffff));
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
        (sampleNormal.x >= 0 ? 1 : 0) +
        (sampleNormal.y >= 0 ? 2 : 0) +
        (sampleNormal.z >= 0 ? 4 : 0);

    hashKey |= ((HashKey)normalBits << (HASH_GRID_POSITION_BIT_NUM * 3 + HASH_GRID_LEVEL_BIT_NUM));
#endif // HASH_GRID_USE_NORMALS

    return hashKey;
}

void AtomicCompareExchange(in uint dstOffset, in HashKey compareValue, in HashKey value, out HashKey originalValue)
{
    // InterlockedCompareExchange(u_GridHashMap[dstOffset], compareValue, value, originalValue);
    const uint cLock = 0xAAAAAAAA;
    uint fuse = 0;
    const uint fuseLength = 8;
    bool busy = true;
    while (busy && fuse < fuseLength)
    {
        uint state;
        InterlockedExchange(u_GridHashMapLockBuffer[dstOffset], cLock, state);
        busy = state != 0;

        if (state != cLock)
        {
            originalValue = u_GridHashMap[dstOffset];
            if (originalValue == compareValue)
                u_GridHashMap[dstOffset] = value;
            InterlockedExchange(u_GridHashMapLockBuffer[dstOffset], state, fuse);
            fuse = fuseLength;
        }
        ++fuse;
    }
}

bool HashMapInsert(const HashKey hashKey, out CacheEntry cacheEntry)
{
    uint    hash        = Hash32(hashKey);
    uint    slot        = hash % S_HASH_MAP_CAPACITY;
    uint    initSlot    = slot;
    HashKey prevHashKey = HASH_GRID_INVALID_HASH_KEY;

    const uint baseSlot = GetBaseSlot(slot);
    for (uint bucketOffset = 0; bucketOffset < HASH_GRID_HASH_MAP_BUCKET_SIZE && baseSlot + bucketOffset < S_HASH_MAP_CAPACITY; ++bucketOffset)
    {
        AtomicCompareExchange(baseSlot + bucketOffset, HASH_GRID_INVALID_HASH_KEY, hashKey, prevHashKey);

        if (prevHashKey == HASH_GRID_INVALID_HASH_KEY)
        {
            cacheEntry = baseSlot + bucketOffset;
            return true;
        }
        else if (prevHashKey == hashKey)
        {
            cacheEntry = baseSlot + bucketOffset;
            return true;
        }
    }

    cacheEntry = 0;
    return false;
}

bool HashMapFind(const HashKey hashKey, inout CacheEntry cacheEntry)
{
    uint    hash        = Hash32(hashKey);
    uint    slot        = hash % S_HASH_MAP_CAPACITY;

    const uint baseSlot = GetBaseSlot(slot);
    for (uint bucketOffset = 0; bucketOffset < HASH_GRID_HASH_MAP_BUCKET_SIZE && baseSlot + bucketOffset < S_HASH_MAP_CAPACITY; ++bucketOffset)
    {
        HashKey storedHashKey = u_GridHashMap[baseSlot + bucketOffset];
        // HashKey storedHashKey = 0;

        if (storedHashKey == hashKey)
        {
            cacheEntry = baseSlot + bucketOffset;
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
    CacheEntry    cacheEntry = 0;
     HashKey hashKey    = ComputeSpatialHash(samplePosition, sampleNormal, viewDepth, scale);
    bool     successful = HashMapInsert(hashKey, cacheEntry);

    o_cacheEntry = cacheEntry;
    return successful;

    // o_cacheEntry = GetUniformGridCellHashId(GetUniformGridCell(samplePosition, scale), sampleNormal);
    // return true;
}

bool FindEntry(float3 samplePosition, float3 sampleNormal, float viewDepth, float scale, out CacheEntry o_cacheEntry)
{
    CacheEntry    cacheEntry = 0;
     HashKey hashKey    = ComputeSpatialHash(samplePosition, sampleNormal, viewDepth, scale);
    bool     successful = HashMapFind(hashKey, cacheEntry);

    o_cacheEntry = cacheEntry;
    return successful;

    // o_cacheEntry = GetUniformGridCellHashId(GetUniformGridCell(samplePosition, scale), sampleNormal);
    // return true;
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

    return GetColorFromHash32(Hash32(hashKey));
}
#endif


#endif