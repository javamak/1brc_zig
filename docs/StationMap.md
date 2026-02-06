# StationMap Explanation

The `StationMap` struct is a specialized, high-performance hash map designed specifically for the 1 Billion Row Challenge. Its primary goal is to minimize overhead by avoiding memory allocations and reducing CPU cycles during lookups.

Here is a breakdown of how it works:

### 1. Data Structure (Parallel Arrays)
Instead of storing a single array of "Entry" objects, it uses three parallel fixed-size arrays. This is often cache-friendlier and simplifies access patterns.

```zig
const MapSize = 1000; // Fixed capacity
const StationMap = struct {
    keys: [MapSize][]const u8, // Stores the station name (slice of the buffer)
    hashes: [MapSize]u64,      // Stores the pre-computed hash for fast comparison
    values: [MapSize]Result,   // Stores the aggregation data (min, max, sum, count)
    // ...
};
```

*   **`MapSize = 1000`**: The map has a hard limit of 1000 slots. This works because the challenge guarantees a limited number of unique weather stations. Using a fixed size allows the compiler to optimize memory layout and avoids the cost of resizing the map at runtime.

### 2. Initialization
The `init` function prepares the map for use.

```zig
fn init() StationMap {
    return .{
        // Initialize all keys to empty slices. This acts as the "empty slot" flag.
        .keys = @as([MapSize][]const u8, @splat(&[_]u8{})),
        // Initialize hashes to 0 (though strictly not necessary if we check keys.len)
        .hashes = @as([MapSize]u64, @splat(0)),
        // Values are left undefined until a slot is actually used
        .values = undefined,
    };
}
```

### 3. Lookup and Insertion (`getByHash`)
This is the critical "hot path" function. It combines retrieval and insertion into one operation (often called "get or put").

```zig
fn getByHash(self: *StationMap, key: []const u8, hash: u64) *Result {
    // 1. Calculate the starting index
    var idx = hash % MapSize;

    // 2. Linear Probing Loop
    while (true) {
        // CASE A: Empty Slot Found (New Station)
        if (self.keys[idx].len == 0) {
            self.keys[idx] = key;       // Store the key
            self.hashes[idx] = hash;    // Store the hash
            self.values[idx] = Result{};// Initialize new Result (min=maxInt, etc.)
            return &self.values[idx];   // Return pointer to the new value
        }

        // CASE B: Slot Occupied (Check for Match)
        // Optimization: Check the integer hash first. It's much faster than checking
        // the string equality. Only if hashes match do we compare the actual strings.
        if (self.hashes[idx] == hash and std.mem.eql(u8, self.keys[idx], key)) {
            return &self.values[idx];   // Return pointer to existing value
        }

        // CASE C: Collision (Slot occupied by a different station)
        // Move to the next slot, wrapping around if necessary.
        idx = (idx + 1) % MapSize;
    }
}
```

### Why is this faster than `std.StringHashMap`?

1.  **Zero Allocation**: `std.StringHashMap` may allocate memory when you insert a new key. `StationMap` has all its memory pre-allocated on the stack (or heap if created via `allocator.create` as in your `main` function).
2.  **Pre-computed Hash**: The calling code (the SWAR loop) calculates the hash while parsing the string. We pass that `hash` directly to `getByHash`, saving the map from having to recalculate it.
3.  **Fast Collision Check**: By storing `hashes[idx]`, we can verify if a slot *might* be the right one using a single integer comparison, avoiding expensive string comparisons (`std.mem.eql`) for most collisions.
4.  **Linear Probing**: This is the simplest collision resolution strategy. It is extremely CPU cache-friendly because it accesses memory sequentially when collisions occur.

### Limitations
*   **Fixed Size**: If the input file has more than 1000 unique stations, this code will enter an infinite loop (it assumes it will eventually find an empty slot).
*   **Power of 2 vs Modulo**: In the previous version, `MapSize` was a power of 2 (e.g., 32768), allowing `hash & (MapSize - 1)`. Since it is now `1000`, it uses `hash % MapSize`, which involves a division instruction (slower than bitwise AND), but `1000` is small enough that the cache benefits likely outweigh the division cost.
