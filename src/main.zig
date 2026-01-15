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
        // var map = std.StringHashMap(Result).init(allocator);
        const map_ptr = try allocator.create(std.StringHashMap(Result));
        map_ptr.* = std.StringHashMap(Result).init(allocator);
        maps[i] = map_ptr;
        const thread = try std.Thread.spawn(.{}, task, .{ allocator, data, chunk, map_ptr });
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

fn task(
    allocator: std.mem.Allocator,
    data: []const u8,
    chunk: Chunk,
    map: *std.StringHashMap(Result),
) !void {
    // Slice directly from mmap
    const buff = data[chunk.start..chunk.end];

    var itr = std.mem.splitScalar(u8, buff, '\n');
    while (itr.next()) |entry| {
        if (entry.len == 0) continue;

        var item_itr = std.mem.splitScalar(u8, entry, ';');

        const station = item_itr.next() orelse continue;
        const temp_str = item_itr.next() orelse continue;

        const temp = try std.fmt.parseFloat(f64, temp_str);

        if (map.getPtr(station)) |mes| {
            mes.count += 1;
            mes.max = @max(mes.max, temp);
            mes.min = @min(mes.min, temp);
            mes.sum += temp;
        } else {
            const mes = Result{
                .min = temp,
                .max = temp,
                .count = 1,
                .sum = temp,
            };

            // station must be owned by the map
            const key_copy = try allocator.dupe(u8, station);
            try map.put(key_copy, mes);
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
            break;
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
