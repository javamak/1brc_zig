const std = @import("std");

const Result = struct {
    min: f64 = std.math.floatMax(f64),
    max: f64 = std.math.floatMax(f64),
    avg: f64 = 0,
    sum: f64 = 0,
    count: usize = 0,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) @panic("Memory leak");
    }

    var file = try std.fs.cwd().openFile("measurements.txt", .{});
    defer file.close();

    var buff: [4096]u8 = undefined;

    var map = std.StringHashMap(Result).init(allocator);
    defer map.deinit();

    // var i: usize = 0;
    while (true) {
        //file.seekBy(10);
        const len = try file.read(&buff);

        var itr = std.mem.splitAny(u8, buff[0..len], "\n");
        while (itr.next()) |entry| {
            if (entry.len == 0) {
                break;
            }
            if (len == buff.len and itr.peek() == null) { //if last entry skip it and seek back in the file.
                const pos = -@as(isize, @intCast(entry.len));
                try file.seekBy(pos);
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
            // std.debug.print("{d}\n", .{i});
            // i += 1;
        }

        if (len < buff.len) {
            break;
        }
    }

    var itr = map.iterator();
    while (itr.next()) |entry| {
        std.debug.print("{s}:{d}/{d}/{d}, ", .{ entry.key_ptr.*, entry.value_ptr.min, std.math.round(entry.value_ptr.sum / @as(f64, @floatFromInt(entry.value_ptr.count)) * 10) / 10, entry.value_ptr.max });
        allocator.free(entry.key_ptr.*);
    }
}
