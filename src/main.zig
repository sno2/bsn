const std = @import("std");

const execution = @import("execution.zig");
const language = @import("language.zig");

const Executable = execution.Executable;
const Lexer = language.Lexer;
const Parser = language.Parser;
const Syntax = language.Config.Syntax;
const VM = execution.VM;
const Heap = execution.Heap;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    var arena_allocator = arena.allocator();

    var process_args = try std.process.ArgIterator.initWithAllocator(arena_allocator);
    defer process_args.deinit();

    const first_argument = process_args.next().?;

    var syntax = Syntax.bs;
    var source: []const u8 = undefined;

    if (std.mem.startsWith(u8, first_argument, "--inline-")) {
        source = process_args.next().?;

        if (std.mem.endsWith(u8, first_argument, "bsx")) {
            syntax = .bsx;
        }
    } else {
        const path = process_args.next().?;

        var file = try std.fs.cwd().openFile(path, .{});
        source = try file.readToEndAlloc(arena_allocator, 8 * 4096);

        if (std.mem.endsWith(u8, path, ".bsx")) {
            syntax = .bsx;
        }
    }

    const config = .{
        .syntax = syntax,
    };

    var parser = Parser{
        .arena = arena_allocator,
        .lex = Lexer.init(source, config),
    };

    const program = parser.parse() catch {
        var stdout = std.io.getStdOut();
        var stdout_writer = stdout.writer();
        try stdout_writer.writeAll("Syntax error: ");
        if (parser.error_context) |context| {
            try context.write(parser, stdout_writer);
        } else {
            try stdout_writer.writeAll("unknown");
        }

        try stdout_writer.writeAll("\n\n");

        var start_line = if (std.mem.lastIndexOfScalar(u8, parser.lex.source[0..parser.lex.start], '\n')) |start_line|
            start_line + 1
        else
            0;

        var end_line = if (std.mem.indexOfScalar(u8, parser.lex.source[parser.lex.start..], '\n')) |end_line|
            end_line - 1
        else
            parser.lex.source.len - parser.lex.index;

        try stdout_writer.print("{s}\n", .{parser.lex.source[start_line .. parser.lex.index + end_line]});

        for (start_line..parser.lex.start) |_| {
            try stdout_writer.writeAll(" ");
        }

        for (parser.lex.start..parser.lex.index) |_| {
            try stdout_writer.writeAll("^");
        }

        try stdout_writer.print("\nat {}\n", .{parser.lex.start});

        return;
    };

    var vm = try VM.init(Heap{
        .arena = arena_allocator,
        .sparse = gpa.allocator(),
    }, config);
    defer vm.heap.deinit();
    defer if (vm.error_context) |message| vm.heap.sparse.free(message);

    var exe = try Executable.compile(arena_allocator, program);

    vm.execute(&exe) catch |e| switch (e) {
        error.Exception => {
            var stdout = std.io.getStdOut();
            var stdout_writer = stdout.writer();
            try stdout_writer.print("Uncaught exception: {s}\n", .{vm.error_context orelse "unknown"});
        },
        else => return e,
    };
}
