const std = @import("std");

const language = @import("language.zig");

const Config = language.Config;

export fn alloc(size: usize) ?[*]u8 {
    const bytes = std.heap.page_allocator.alloc(u8, size) catch return null;
    return bytes.ptr;
}

export fn free(ptr: [*]u8, len: usize) void {
    std.heap.page_allocator.free(ptr[0..len]);
}

threadlocal var translated: []u8 = &.{};

export fn getTranslatedPointer() [*]const u8 {
    return translated.ptr;
}

export fn translate(target_bs: bool, source_ptr: [*]const u8, source_len: usize) isize {
    const source_config = .{ .syntax = if (target_bs) Config.Syntax.bsx else .bs };
    const target_config = .{ .syntax = if (target_bs) Config.Syntax.bs else .bsx };

    const source = source_ptr[0..source_len];

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var parser = language.Parser.init(arena.allocator(), source, source_config);

    const statements = parser.parse() catch
        return -1;

    var output = std.ArrayList(u8).initCapacity(std.heap.page_allocator, source_len) catch
        return -2;
    var writer = output.writer();

    for (statements) |statement| {
        statement.emit(.{ .config = target_config }, writer) catch
            return -3;
    }

    translated = output.toOwnedSlice() catch
        return -4;

    return @intCast(translated.len);
}
