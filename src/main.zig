const std = @import("std");
const ordered = @import("ordered");

const Result = struct {
    min: f64 = std.math.floatMax(f64),
    max: f64 = std.math.floatMax(f64),
    avg: f64 = 0,
    sum: f64 = 0,
    count: usize = 0,
};

// The function must return a `std.math.Order` value based on the comparison of the two keys
fn strCompare(lhs: []const u8, rhs: []const u8) std.math.Order {
    return std.mem.order(u8, lhs, rhs);
}

const btree_type = ordered.BTreeMap([]const u8, Result, strCompare, 4);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) @panic("Memory leak");
    }

    var file = try std.fs.cwd().openFile("/home/arun/Work/1brc/measurements.txt", .{});
    defer file.close();

    const chunks = try calculateChunks(allocator, file);
    defer allocator.free(chunks);

    var threads = try allocator.alloc(std.Thread, chunks.len);
    defer allocator.free(threads);
    var maps = try allocator.alloc(*std.StringHashMap(Result), chunks.len);
    defer allocator.free(maps);

    var i: usize = 0;
    for (chunks) |chunk| {
        // var map = std.StringHashMap(Result).init(allocator);
        const map_ptr = try allocator.create(std.StringHashMap(Result));
        map_ptr.* = std.StringHashMap(Result).init(allocator);
        maps[i] = map_ptr;
        const thread = try std.Thread.spawn(.{}, task, .{ allocator, file, chunk, map_ptr });
        threads[i] = thread;

        i += 1;
    }
    for (threads) |thread| {
        thread.join();
    }

    // var finalMap = std.StringHashMap(Result).init(allocator);
    var finalMap = btree_type.init(allocator);
    defer finalMap.deinit();

    for (maps) |map| {
        try mergeMaps(allocator, &finalMap, map);
    }

    var itr = try finalMap.iterator();
    while (try itr.next()) |entry| {
        std.debug.print("{s}:{d}/{d}/{d}, ", .{ entry.key, entry.value.min, std.math.round(entry.value.sum / @as(f64, @floatFromInt(entry.value.count)) * 10) / 10, entry.value.max });
        // allocator.free(entry.key);
    }
}

fn mergeMaps(allocator: std.mem.Allocator, finalMap: *btree_type, map: *std.StringHashMap(Result)) !void {
    var itr = map.iterator();
    while (itr.next()) |entry| {
        const result = finalMap.getPtr(entry.key_ptr.*);

        if (result) |mes| {
            mes.count += entry.value_ptr.count;
            mes.max = @max(mes.max, entry.value_ptr.max);
            mes.min = @min(mes.min, entry.value_ptr.min);
            mes.sum += entry.value_ptr.sum;
            allocator.free(entry.key_ptr.*);
        } else {
            try finalMap.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }
    map.*.deinit();
    allocator.destroy(map);
}

fn task(allocator: std.mem.Allocator, file: std.fs.File, chunk: Chunk, map: *std.StringHashMap(Result)) !void {
    const buff = try allocator.alloc(u8, chunk.end - chunk.start);
    defer allocator.free(buff);

    _ = try file.pread(buff, chunk.start);
    var itr = std.mem.splitAny(u8, buff, "\n");

    while (itr.next()) |entry| {
        if (entry.len == 0) {
            break;
        }

        var item_itr = std.mem.splitAny(u8, entry, ";");
        const station = item_itr.next().?;
        const temp = try std.fmt.parseFloat(f64, item_itr.next().?);

        const result = map.getPtr(station);

        if (result) |mes| {
            mes.count += 1;
            mes.max = @max(mes.max, temp);
            mes.min = @min(mes.min, temp);
            mes.sum += temp;
        } else {
            const mes = Result{ .min = temp, .max = temp, .count = 1, .sum = temp };
            const key_copy = try allocator.dupe(u8, station);
            try map.put(key_copy, mes);
        }
    }
}

const Chunk = struct { start: u64 = 0, end: u64 = 0 };

fn calculateChunks(allocator: std.mem.Allocator, file: std.fs.File) ![]Chunk {
    const chunk_size: u64 = 1000 * 200000;
    const max = try file.getEndPos();

    const chunks = @as(u64, @intFromFloat(@ceil(@as(f64, @floatFromInt(max)) / @as(f64, @floatFromInt(chunk_size)))));
    // const chunks: u64 = 3;

    const arr = try allocator.alloc(Chunk, chunks);

    var start: u64 = 0;
    var end: u64 = chunk_size;

    var buff: [100]u8 = undefined;

    for (0..chunks) |i| {
        if (end >= max) {
            end = max;
            arr[i] = Chunk{ .start = start, .end = end };
            break;
        }

        try file.seekTo(end);
        const len = try file.read(&buff);
        for (0..len) |j| {
            end += 1;
            if (buff[j] == '\n') {
                break;
            }
        }

        arr[i] = Chunk{ .start = start, .end = end };
        start = end;
        end += chunk_size;
    }
    return arr;
}
