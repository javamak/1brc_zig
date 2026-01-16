const std = @import("std");

const Result = struct {
    key: []const u8 = &[_]u8{},
    min: i32 = std.math.maxInt(i32),
    max: i32 = std.math.minInt(i32),
    sum: i64 = 0,
    count: usize = 0,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("Memory leak");
    }

    var file = try std.fs.cwd().openFile("/home/arun/Work/1brc/measurements.txt", .{});

    const data = try std.posix.mmap(null, try file.getEndPos(), std.posix.PROT.READ, .{ .TYPE = .SHARED }, file.handle, 0);
    defer std.posix.munmap(data);
    file.close();

    const chunks = try calculateChunks(allocator, data);
    defer allocator.free(chunks);

    var threads = try allocator.alloc(std.Thread, chunks.len);
    defer allocator.free(threads);
    var maps = try allocator.alloc(*std.StringHashMap(Result), chunks.len);
    defer allocator.free(maps);

    var i: usize = 0;
    for (chunks) |chunk| {
        const map_ptr = try allocator.create(std.StringHashMap(Result));
        map_ptr.* = std.StringHashMap(Result).init(allocator);
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

    for (list.items) |res| {
        const min = @as(f64, @floatFromInt(res.min)) / 10.0;
        const max = @as(f64, @floatFromInt(res.max)) / 10.0;
        const avg = std.math.round(@as(f64, @floatFromInt(res.sum)) / @as(f64, @floatFromInt(res.count))) / 10.0;
        std.debug.print("{s}:{d:.1}/{d:.1}/{d:.1}, ", .{ res.key, min, avg, max });
    }
}

fn mergeMaps(allocator: std.mem.Allocator, finalMap: *std.StringHashMap(Result), map: *std.StringHashMap(Result)) !void {
    var itr = map.iterator();
    while (itr.next()) |entry| {
        const result = finalMap.getPtr(entry.key_ptr.*);

        if (result) |mes| {
            mes.count += entry.value_ptr.count;
            if (entry.value_ptr.max > mes.max) mes.max = entry.value_ptr.max;
            if (entry.value_ptr.min < mes.min) mes.min = entry.value_ptr.min;
            mes.sum += entry.value_ptr.sum;
        } else {
            try finalMap.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }
    map.*.deinit();
    allocator.destroy(map);
}

fn task(
    data: []const u8,
    chunk: Chunk,
    map: *std.StringHashMap(Result),
) !void {
    // Slice directly from mmap
    const buff = data[chunk.start..chunk.end];

    var cursor: usize = 0;
    while (cursor < buff.len) {
        const remaining = buff[cursor..];
        const semi = std.mem.indexOfScalar(u8, remaining, ';') orelse break;
        const station = remaining[0..semi];

        var idx = semi + 1;
        var temp: i32 = 0;
        var sign: i32 = 1;

        if (remaining[idx] == '-') {
            sign = -1;
            idx += 1;
        }

        while (remaining[idx] != '.') {
            temp = temp * 10 + (remaining[idx] - '0');
            idx += 1;
        }
        idx += 1; // skip .
        temp = temp * 10 + (remaining[idx] - '0');
        idx += 1; // skip decimal digit
        if (idx < remaining.len and remaining[idx] == '\r') idx += 1;
        idx += 1; // skip newline
        cursor += idx;

        temp *= sign;

        const gop = try map.getOrPut(station);
        if (gop.found_existing) {
            const mes = gop.value_ptr;
            mes.count += 1;
            if (temp > mes.max) mes.max = temp;
            if (temp < mes.min) mes.min = temp;
            mes.sum += temp;
        } else {
            gop.value_ptr.* = Result{
                .min = temp,
                .max = temp,
                .count = 1,
                .sum = temp,
            };
        }
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
