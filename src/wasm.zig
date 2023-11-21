//! A WASM binding for compiling and executing Bussin programs.
const std = @import("std");

const execution = @import("execution.zig");
const language = @import("language.zig");

const ProgramData = struct {
    arena: std.heap.ArenaAllocator,
    source: []u8,
    statements: []language.ast.Statement,
};

threadlocal var program: ProgramData = undefined;

const ExecutionStatus = struct {
    pub const ok = 0;
    pub const out_of_memory = 1;
    pub const syntax_error = 2;
    pub const uncaught_exception = 3;
    pub const marker = 4;
};

pub fn main() void {
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // const arena_allocator = arena.allocator();

    // const arguments = std.process.argsAlloc(arena_allocator) catch
    //     return ExecutionStatus.out_of_memory;

    // const syntax = if (std.mem.eql(u8, arguments[0], "bs"))
    //     language.Config.Syntax.bs
    // else
    //     .bsx;

    // var owned_source = arguments[1];

    // const config = .{ .syntax = syntax };

    // var parser = language.Parser.init(arena_allocator, owned_source, config);

    // var statements = parser.parse() catch |e| switch (e) {
    //     error.OutOfMemory => return ExecutionStatus.out_of_memory,
    //     error.SyntaxError => {
    //         // TODO: Set some kind of error message.
    //         return ExecutionStatus.syntax_error;
    //     },
    // };

    // var vm = execution.VM.init(.{ .arena = arena_allocator, .sparse = std.heap.page_allocator }, config) catch
    //     return ExecutionStatus.out_of_memory;

    // var exe = execution.Executable.compile(std.heap.page_allocator, statements) catch
    //     return ExecutionStatus.out_of_memory;

    // vm.execute(&exe) catch
    //     return ExecutionStatus.uncaught_exception;

    // program = .{
    //     .arena = arena,
    //     .source = owned_source,
    //     .statements = statements,
    // };

    // return ExecutionStatus.ok;
}
