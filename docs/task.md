# Task Method Explanation

The `task` function is the core worker unit in the 1 Billion Row Challenge implementation. It processes a specific chunk of the memory-mapped file, parses weather station data, and aggregates statistics into a thread-local `StationMap`.

## Key Responsibilities

1.  **SWAR Scanning**: Uses "SIMD Within A Register" techniques to scan for the delimiter (`;`) and compute the hash of the station name simultaneously.
2.  **Optimized Parsing**: Converts the temperature string to an integer without using standard library parsing functions or floating-point arithmetic.
3.  **Aggregation**: Updates the min, max, sum, and count for the station in the custom hash map.

## Detailed Breakdown

### 1. SWAR Loop (Scanning & Hashing)

Instead of processing the station name byte-by-byte, the code reads 8 bytes (`u64`) at a time. This reduces loop overhead and memory access frequency.

```zig
const broadcast_semi: u64 = 0x3B3B3B3B3B3B3B3B; // 0x3B is ';'

while (cursor + 8 <= buff.len) {
    const word = std.mem.readInt(u64, buff[cursor..][0..8], .little);
    
    // XOR with the broadcasted semicolon. Bytes that match ';' become 0x00.
    const match = word ^ broadcast_semi;
    
    // Standard bit-twiddling trick to find the lowest set byte.
    // If a byte in `match` is 0x00 (meaning it was ';'), the corresponding byte in `mask` becomes 0x80.
    const mask = (match -% 0x0101010101010101) & ~match & 0x8080808080808080;

    if (mask != 0) {
        // Semicolon found!
        const bit_idx = @ctz(mask); // Count trailing zeros to find position
        const byte_idx = bit_idx >> 3; // Convert bit index to byte index
        
        // Hash the bytes preceding the semicolon within this word
        if (byte_idx > 0) {
            const shift_bits = @as(u6, @intCast(byte_idx)) * 8;
            const word_mask = (@as(u64, 1) << shift_bits) - 1;
            h ^= (word & word_mask);
        }
        h *%= 0x100000001b3; // FNV-1a prime
        cursor += byte_idx;
        break;
    }
    
    // No semicolon in this 8-byte chunk. Hash the entire word and continue.
    h ^= word;
    h *%= 0x100000001b3;
    cursor += 8;
}
```

### 2. Map Lookup

Once the semicolon is found, we have the station name slice (`buff[start..cursor]`) and its hash (`h`). We retrieve the aggregation entry directly.

```zig
const mes = map.getByHash(station, h);
```

### 3. Unrolled Number Parsing

The temperature format is strictly controlled (`X.X`, `XX.X`, `-X.X`, or `-XX.X`). The code manually parses this to avoid the overhead of a generic parser. It treats the number as an integer (e.g., `12.3` becomes `123`) to use fast integer arithmetic for the sum.

```zig
var val: i32 = remaining[idx] - '0';
idx += 1;

// Check if the next char is a dot. If not, it's a 2-digit integer part.
if (remaining[idx] != '.') {
    val = val * 10 + (remaining[idx] - '0');
    idx += 1;
}
idx += 1; // skip '.'
val = val * 10 + (remaining[idx] - '0'); // add decimal part

// Apply sign
temp = val * sign;
```

### 4. Aggregation

Finally, the statistics are updated. Branchless logic is not strictly used here for min/max, but the CPU branch predictor handles this well given the random nature of weather data.

```zig
mes.count += 1;
if (temp > mes.max) mes.max = temp;
if (temp < mes.min) mes.min = temp;
mes.sum += temp;
```
