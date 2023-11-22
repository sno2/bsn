//! A script to copy the examples into a JSON for the playground website.

const std = @import("std");

pub fn main() !void {
    var allocator = std.heap.page_allocator;

    var examples_dir = try std.fs.cwd().openIterableDir("examples", .{});
    var examples_iter = examples_dir.iterate();

    var examples_file = try std.fs.cwd().createFile("./playground/data/examples.json", .{ .read = true });
    var json_writer = examples_file.writer();
    try json_writer.writeByte('[');

    var i: usize = 0;
    while (try examples_iter.next()) |entry| {
        if (i != 0) {
            try json_writer.writeAll(",\n");
        }
        i += 1;

        var name = entry.name;

        var bytes = try examples_dir.dir.readFileAlloc(allocator, name, 4096);

        try json_writer.print("{{ \"name\": \"{s}\", \"text\": ", .{name});
        try std.json.encodeJsonString(bytes, .{}, json_writer);
        try json_writer.writeAll("}");
    }

    try json_writer.writeAll("]");
}
