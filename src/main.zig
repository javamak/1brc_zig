const std = @import("std");

const Result = struct {
    key: []const u8 = &[_]u8{},
    min: i32 = std.math.maxInt(i32),
    max: i32 = std.math.minInt(i32),
    sum: i64 = 0,
    count: usize = 0,
};

const MapSize = 1000;
const StationMap = struct {
    keys: [MapSize][]const u8,
    hashes: [MapSize]u64,
    values: [MapSize]Result,

    fn init() StationMap {
        return .{
            .keys = @as([MapSize][]const u8, @splat(&[_]u8{})),
            .hashes = @as([MapSize]u64, @splat(0)),
            .values = undefined,
        };
    }

    fn getByHash(self: *StationMap, key: []const u8, hash: u64) *Result {
        var idx = hash % MapSize;
        while (true) {
            if (self.keys[idx].len == 0) {
                self.keys[idx] = key;
                self.hashes[idx] = hash;
                self.values[idx] = Result{};
                return &self.values[idx];
            }
            if (self.hashes[idx] == hash and std.mem.eql(u8, self.keys[idx], key)) {
                return &self.values[idx];
            }
            idx = (idx + 1) % MapSize;
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("Memory leak");
    }

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const filename = if (args.len > 1) args[1] else "/home/arun/Work/1brc/measurements.txt";
    var file = try std.fs.cwd().openFile(filename, .{});

    const data = try std.posix.mmap(null, try file.getEndPos(), std.posix.PROT.READ, .{ .TYPE = .SHARED }, file.handle, 0);
    defer std.posix.munmap(data);
    file.close();

    const chunks = try calculateChunks(allocator, data);
    defer allocator.free(chunks);

    var threads = try allocator.alloc(std.Thread, chunks.len);
    defer allocator.free(threads);
    var maps = try allocator.alloc(*StationMap, chunks.len);
    defer allocator.free(maps);

    var i: usize = 0;
    for (chunks) |chunk| {
        const map_ptr = try allocator.create(StationMap);
        map_ptr.* = StationMap.init();
        maps[i] = map_ptr;
        const thread = try std.Thread.spawn(.{}, task, .{ data, chunk, map_ptr });
        threads[i] = thread;

        i += 1;
    }
    for (threads) |thread| {
        thread.join();
    }

    var finalMap = std.StringHashMap(Result).init(allocator);
    defer finalMap.deinit();

    for (maps) |map| {
        try mergeMaps(allocator, &finalMap, map);
    }

    var list: std.ArrayList(Result) = .empty;
    defer list.deinit(allocator);

    var itr = finalMap.iterator();
    while (itr.next()) |entry| {
        var res = entry.value_ptr.*;
        res.key = entry.key_ptr.*;
        try list.append(allocator, res);
    }

    std.sort.block(Result, list.items, {}, struct {
        fn lessThan(_: void, lhs: Result, rhs: Result) bool {
            return std.mem.order(u8, lhs.key, rhs.key) == .lt;
        }
    }.lessThan);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("{{", .{});
    for (list.items) |res| {
        const min = @as(f64, @floatFromInt(res.min)) / 10.0;
        const max = @as(f64, @floatFromInt(res.max)) / 10.0;
        const avg = std.math.round(@as(f64, @floatFromInt(res.sum)) / @as(f64, @floatFromInt(res.count))) / 10.0;
        try stdout.print("{s}={d:.1}/{d:.1}/{d:.1}, ", .{ res.key, min, avg, max });
    }
    try stdout.print("}}\n", .{});
    try stdout.flush();
}

fn mergeMaps(allocator: std.mem.Allocator, finalMap: *std.StringHashMap(Result), map: *StationMap) !void {
    for (map.keys, 0..) |key, i| {
        if (key.len == 0) continue;
        const result = finalMap.getPtr(key);

        if (result) |mes| {
            const val = map.values[i];
            mes.count += val.count;
            if (val.max > mes.max) mes.max = val.max;
            if (val.min < mes.min) mes.min = val.min;
            mes.sum += val.sum;
        } else {
            try finalMap.put(key, map.values[i]);
        }
    }
    allocator.destroy(map);
}

fn task(
    data: []const u8,
    chunk: Chunk,
    map: *StationMap,
) !void {
    // Slice directly from mmap
    const buff = data[chunk.start..chunk.end];

    var cursor: usize = 0;
    const broadcast_semi: u64 = 0x3B3B3B3B3B3B3B3B;

    while (cursor < buff.len) {
        var h: u64 = 0;
        const start = cursor;

        // SWAR loop to find ';' and compute hash simultaneously
        while (cursor + 8 <= buff.len) {
            const word = std.mem.readInt(u64, buff[cursor..][0..8], .little);
            const match = word ^ broadcast_semi;
            const mask = (match -% 0x0101010101010101) & ~match & 0x8080808080808080;

            if (mask != 0) {
                const bit_idx = @ctz(mask);
                const byte_idx = bit_idx >> 3;
                if (byte_idx > 0) {
                    const shift_bits = @as(u6, @intCast(byte_idx)) * 8;
                    const word_mask = (@as(u64, 1) << shift_bits) - 1;
                    h ^= (word & word_mask);
                }
                h *%= 0x100000001b3;
                cursor += byte_idx;
                break;
            }
            h ^= word;
            h *%= 0x100000001b3;
            cursor += 8;
        }

        // Fallback for remaining bytes
        if (cursor < buff.len and buff[cursor] != ';') {
            while (cursor < buff.len and buff[cursor] != ';') {
                h ^= buff[cursor];
                h *%= 0x100000001b3;
                cursor += 1;
            }
        }

        const station = buff[start..cursor];
        const mes = map.getByHash(station, h);

        cursor += 1; // skip ';'
        const remaining = buff[cursor..];
        var idx: usize = 0;
        var temp: i32 = 0;
        var sign: i32 = 1;

        if (remaining[idx] == '-') {
            sign = -1;
            idx += 1;
        }

        var val: i32 = remaining[idx] - '0';
        idx += 1;

        if (remaining[idx] != '.') {
            val = val * 10 + (remaining[idx] - '0');
            idx += 1;
        }
        idx += 1; // skip .
        val = val * 10 + (remaining[idx] - '0');
        idx += 1; // skip decimal digit
        if (idx < remaining.len and remaining[idx] == '\r') idx += 1;
        idx += 1; // skip newline
        cursor += idx;

        temp = val * sign;

        mes.count += 1;
        if (temp > mes.max) mes.max = temp;
        if (temp < mes.min) mes.min = temp;
        mes.sum += temp;
    }
}

const Chunk = struct { start: u64 = 0, end: u64 = 0 };

fn calculateChunks(
    allocator: std.mem.Allocator,
    data: []const u8,
) ![]Chunk {
    const chunk_size: usize = 1000 * 200000;
    const max: usize = data.len;

    const chunks: usize =
        (max + chunk_size - 1) / chunk_size;

    const arr = try allocator.alloc(Chunk, chunks);

    var start: usize = 0;
    var end: usize = chunk_size;

    for (0..chunks) |i| {
        if (end >= max) {
            end = max;
            arr[i] = Chunk{ .start = start, .end = end };
            return allocator.realloc(arr, i + 1);
        }

        // move `end` forward until newline
        var j = end;
        while (j < max) : (j += 1) {
            if (data[j] == '\n') {
                j += 1; // include newline
                break;
            }
        }

        end = j;

        arr[i] = Chunk{ .start = start, .end = end };
        start = end;
        end = start + chunk_size;
    }

    return arr;
}
