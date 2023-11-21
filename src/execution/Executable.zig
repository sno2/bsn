//! A collection of instructions and data used for running Bussin code.

const std = @import("std");

const ast = @import("../language.zig").ast;
const Value = @import("value.zig").Value;
const Heap = @import("Heap.zig");

const Executable = @This();

/// The allocator for allocating data.
allocator: std.mem.Allocator,

/// The bytecode instructions.
bytecode: std.ArrayListUnmanaged(u8) = .{},

/// The constants defined in the executable.
constants: std.ArrayListUnmanaged(Value) = .{},

/// The identifiers used in the executable.
identifiers: std.ArrayListUnmanaged([]const u8) = .{},

/// The strings used in the executable.
strings: std.ArrayListUnmanaged([]const u8) = .{},

/// The functions compiled in the executable.
functions: std.ArrayListUnmanaged(FunctionData) = .{},

/// The possible ast node if this is a defined function.
ast_node: ?*ast.FnStatement = null,

const FunctionData = struct {
    node: *ast.FnStatement,
    index: ?Heap.ExecutableHeap.Index = null,
};

pub fn deinit(exe: *Executable) void {
    exe.bytecode.deinit(exe.allocator);
    exe.constants.deinit(exe.allocator);
    exe.identifiers.deinit(exe.allocator);
    exe.strings.deinit(exe.allocator);
    exe.functions.deinit(exe.allocator);
}

pub fn emit(exe: *Executable, insn: Instruction) !void {
    std.debug.assert(insn.argumentsCount() == 0);
    try exe.bytecode.append(exe.allocator, @intFromEnum(insn));
}

pub fn emitWithIndex(exe: *Executable, insn: Instruction, index: u32) !void {
    std.debug.assert(insn.argumentsCount() == 1);
    try exe.bytecode.append(exe.allocator, @intFromEnum(insn));
    try exe.bytecode.appendSlice(exe.allocator, &std.mem.toBytes(index));
}

pub fn emitWithIndexes(exe: *Executable, insn: Instruction, indexes: []const u32) !void {
    std.debug.assert(insn.argumentsCount() == indexes.len);
    try exe.bytecode.append(exe.allocator, @intFromEnum(insn));
    for (indexes) |index| {
        try exe.bytecode.appendSlice(exe.allocator, &std.mem.toBytes(index));
    }
}

pub fn emitWithMutableIndex(exe: *Executable, insn: Instruction) !u32 {
    std.debug.assert(insn.argumentsCount() == 1);
    try exe.bytecode.append(exe.allocator, @intFromEnum(insn));
    try exe.bytecode.appendSlice(exe.allocator, &std.mem.toBytes(@as(u32, 0)));
    return @intCast(exe.bytecode.items.len - 4);
}

pub fn replaceMutableIndex(exe: *Executable, jump_index: u32, jump_value: u32) void {
    exe.bytecode.items[jump_index..][0..4].* = std.mem.toBytes(jump_value);
}

pub fn emitWithIdentifier(exe: *Executable, insn: Instruction, identifier: []const u8) !void {
    try exe.identifiers.append(exe.allocator, identifier);
    try exe.emitWithIndex(insn, @intCast(exe.identifiers.items.len - 1));
}

pub fn emitWithString(exe: *Executable, insn: Instruction, string: []const u8) !void {
    try exe.strings.append(exe.allocator, string);
    try exe.emitWithIndex(insn, @intCast(exe.strings.items.len - 1));
}

pub fn emitWithConstant(exe: *Executable, insn: Instruction, constant: Value) !void {
    try exe.constants.append(exe.allocator, constant);
    try exe.emitWithIndex(insn, @intCast(exe.constants.items.len - 1));
}

pub fn emitWithFunctionData(exe: *Executable, insn: Instruction, function_data: FunctionData) !void {
    try exe.functions.append(exe.allocator, function_data);
    try exe.emitWithIndex(insn, @intCast(exe.functions.items.len - 1));
}

pub fn compile(allocator: std.mem.Allocator, program: []ast.Statement) !Executable {
    var exe = Executable{ .allocator = allocator };

    if (program.len == 0) {
        try exe.emit(.push_null);
        return exe;
    }

    for (program[0 .. program.len - 1]) |statement| {
        try statement.generateBytecode(&exe);
    }

    const last_statement = program[program.len - 1];

    switch (last_statement) {
        .expression => |expression| try expression.generateBytecode(&exe),
        else => {
            try last_statement.generateBytecode(&exe);
            try exe.emit(.push_null);
        },
    }

    return exe;
}

pub const Instruction = enum {
    pop,
    duplicate,
    push_constant,
    push_string,
    push_null,
    push_binding,
    create_binding,
    create_mutable_binding,
    put_binding,
    jump_if_not_true,
    jump,
    call,
    @"+",
    @"-",
    @"*",
    @"/",
    @"%",
    @"<",
    @">",
    @"<=",
    @">=",
    @"==",
    @"!=",
    @"&&",
    @"|",
    member,
    create_object,
    put_property,
    put_property_in_expression,
    push_fallible,
    pop_fallbile,
    put_function,
    push_environment,
    pop_environment,
    reset_environment,
    push_number_f32,
    push_number_f64,
    push_number_i32,

    pub fn argumentsCount(insn: Instruction) u8 {
        return switch (insn) {
            .push_number_f64 => 2,
            .jump_if_not_true,
            .jump,
            .push_constant,
            .push_string,
            .push_binding,
            .put_binding,
            .create_binding,
            .create_mutable_binding,
            .call,
            .member,
            .create_object,
            .put_property,
            .put_property_in_expression,
            .push_fallible,
            .put_function,
            .push_number_f32,
            .push_number_i32,
            => 1,
            else => 0,
        };
    }
};

pub const BytecodeIterator = struct {
    /// The bytecode instructions.
    bytecode: []const u8,

    /// The current index in the bytecode.
    index: usize = 0,

    pub const Item = struct {
        tag: Instruction,
        args: [*]align(1) const u32,
    };

    pub fn next(self: *BytecodeIterator) ?Item {
        if (self.index >= self.bytecode.len) {
            return null;
        }

        const tag: Instruction = @enumFromInt(self.bytecode[self.index]);
        self.index += 1;
        defer self.index += 4 * tag.argumentsCount();
        return .{
            .tag = tag,
            .args = @ptrCast(self.bytecode[self.index..].ptr),
        };
    }
};
