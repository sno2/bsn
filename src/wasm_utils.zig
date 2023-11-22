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

const ErrorInfo = extern struct {
    message_ptr: [*]u8,
    message_len: usize,
    start: usize,
    index: usize,
};

export fn freeErrorInfo(info: *ErrorInfo) void {
    std.heap.page_allocator.free(info.message_ptr[0..info.message_len]);
    std.heap.page_allocator.destroy(info);
}

export fn validate(syntax: Config.Syntax, source_ptr: [*]const u8, source_len: usize) ?*ErrorInfo {
    const source_config = .{ .syntax = syntax };

    const source = source_ptr[0..source_len];

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var parser = language.Parser.init(arena.allocator(), source, source_config);

    _ = parser.parse() catch {
        var message = std.ArrayList(u8).init(std.heap.page_allocator);
        parser.error_context.?.write(parser, message.writer()) catch unreachable;

        var owned_message = message.toOwnedSlice() catch unreachable;
        var info = std.heap.page_allocator.create(ErrorInfo) catch unreachable;
        info.* = .{
            .message_ptr = owned_message.ptr,
            .message_len = owned_message.len,
            .start = parser.lex.start,
            .index = parser.lex.index,
        };
        return info;
    };

    return null;
}
