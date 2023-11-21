//! The AST expressions and statements for the Bussin language.

const std = @import("std");

const Config = @import("Config.zig");
const execution = @import("../execution.zig");
const Lexer = @import("Lexer.zig");

const Executable = execution.Executable;
const Token = Lexer.Token;
const Value = execution.Value;

pub const EmitContext = struct {
    config: Config,
    level: usize = 0,

    pub fn indent(ctx: EmitContext) EmitContext {
        return .{
            .config = ctx.config,
            .level = ctx.level + 1,
        };
    }

    pub fn writeIndent(ctx: EmitContext, writer: anytype) !void {
        for (0..ctx.level) |i| {
            _ = i;
            try writer.writeAll("    ");
        }
    }
};

/// An expression.
pub const Expression = union(enum) {
    null,
    identifier: []const u8,
    number_i32: i32,
    number_f64: f64,
    string: []const u8,
    boolean: bool,
    binary: *BinaryExpression,
    function_call: FunctionCall,
    member: *MemberExpression,
    object: ObjectExpression,

    const BSIdentifierLookup = std.ComptimeStringMap([]const u8, .{
        .{ "waffle", "println" },
        .{ "clapback", "exec" },
        .{ "yap", "input" },
        .{ "nerd", "math" },
    });

    const BSXIdentifierLookup = std.ComptimeStringMap([]const u8, .{
        .{ "println", "waffle" },
        .{ "exec", "clapback" },
        .{ "input", "yap" },
        .{ "math", "nerd" },
    });

    pub fn emit(expression: Expression, ctx: EmitContext, writer: anytype) @TypeOf(writer).Error!void {
        switch (expression) {
            .null => try writer.writeAll(switch (ctx.config.syntax) {
                .bs => "null",
                .bsx => "fake",
            }),
            .identifier => |name| try writer.writeAll(switch (ctx.config.syntax) {
                .bs => BSIdentifierLookup.get(name) orelse name,
                .bsx => BSXIdentifierLookup.get(name) orelse name,
            }),
            .number_i32 => |number| try writer.print("{}", .{number}),
            .number_f64 => |number| try writer.print("{d}", .{number}),
            .string => |string| try writer.print("\"{s}\"", .{string}),
            .boolean => |boolean| try writer.print("{s}", .{switch (boolean) {
                true => switch (ctx.config.syntax) {
                    .bs => "true",
                    .bsx => "nocap",
                },
                false => switch (ctx.config.syntax) {
                    .bs => "false",
                    .bsx => "cap",
                },
            }}),
            .binary => |binary| try binary.emit(ctx, writer),
            .function_call => |function_call| try function_call.emit(ctx, writer),
            .member => |member| try member.emit(ctx, writer),
            .object => |object| try object.emit(ctx, writer),
        }
    }

    pub fn generateBytecode(expression: Expression, exe: *Executable) std.mem.Allocator.Error!void {
        switch (expression) {
            .null => try exe.emitWithConstant(.push_constant, .null),
            .identifier => |name| try exe.emitWithIdentifier(.push_binding, name),
            .boolean => |boolean| try exe.emitWithConstant(.push_constant, Value.from(boolean)),
            .number_i32 => |number| {
                try exe.emitWithIndex(.push_number_i32, @bitCast(number));
            },
            .number_f64 => |number| {
                const number_f32 = std.math.lossyCast(f32, number);
                if (number == number_f32) {
                    try exe.emitWithIndex(.push_number_f32, @bitCast(number_f32));
                } else {
                    const bytes = std.mem.toBytes(number);
                    const first_u32 = std.mem.bytesAsSlice(u32, bytes[0..4])[0];
                    const second_u32 = std.mem.bytesAsSlice(u32, bytes[4..8])[0];
                    try exe.emitWithIndexes(.push_number_f64, &.{ first_u32, second_u32 });
                }
            },
            .string => |string| try exe.emitWithString(.push_string, string),
            .binary => |binary| try binary.generateBytecode(exe),
            .function_call => |function_call| try function_call.generateBytecode(exe),
            .member => |member| try member.generateBytecode(exe),
            .object => |object| try object.generateBytecode(exe),
        }
    }
};

/// A function call.
pub const FunctionCall = struct {
    data: []Expression,

    /// Returns the callee expression.
    pub fn callee(self: FunctionCall) Expression {
        return self.data[0];
    }

    /// Returns the arguments.
    pub fn arguments(self: FunctionCall) []Expression {
        return self.data[1..];
    }

    pub fn emit(function_call: FunctionCall, ctx: EmitContext, writer: anytype) !void {
        try function_call.callee().emit(ctx, writer);
        try writer.writeAll("(");

        for (function_call.arguments(), 0..) |argument, i| {
            if (i != 0) {
                try writer.writeAll(", ");
            }

            try argument.emit(ctx, writer);
        }

        try writer.writeAll(")");
    }

    pub fn generateBytecode(function_call: FunctionCall, exe: *Executable) !void {
        try function_call.callee().generateBytecode(exe);

        for (function_call.arguments()) |argument| {
            try argument.generateBytecode(exe);
        }

        try exe.emitWithIndex(.call, @intCast(function_call.arguments().len));
    }
};

/// A member expression.
pub const MemberExpression = struct {
    root: Expression,
    name: []const u8,

    pub fn emit(member: MemberExpression, ctx: EmitContext, writer: anytype) !void {
        try member.root.emit(ctx, writer);
        try writer.print(".{s}", .{member.name});
    }

    pub fn generateBytecode(member: MemberExpression, exe: *Executable) !void {
        try member.root.generateBytecode(exe);
        try exe.emitWithIdentifier(.member, member.name);
    }
};

/// A binary operator.
pub const BinaryOperator = enum {
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
    @"=",

    /// Converts a Token.Tag into a BinaryOperator.
    pub fn fromTokenTag(tag: Token.Tag) BinaryOperator {
        return switch (tag) {
            .@"+" => .@"+",
            .@"-" => .@"-",
            .@"*" => .@"*",
            .@"/" => .@"/",
            .@"%" => .@"%",
            .@"<" => .@"<",
            .@">" => .@">",
            .@"<=" => .@"<=",
            .@">=" => .@">=",
            .@"==" => .@"==",
            .@"!=" => .@"!=",
            .@"&&" => .@"&&",
            .@"|" => .@"|",
            .@"=" => .@"=",
            else => unreachable,
        };
    }

    pub fn emit(operator: BinaryOperator, ctx: EmitContext, writer: anytype) !void {
        try writer.writeAll(switch (operator) {
            .@"+" => "+",
            .@"-" => "-",
            .@"*" => "*",
            .@"/" => "/",
            .@"%" => "%",
            .@"<" => switch (ctx.config.syntax) {
                .bs => "<",
                .bsx => "smol",
            },
            .@">" => switch (ctx.config.syntax) {
                .bs => ">",
                .bsx => "thicc",
            },
            .@"<=" => "<=",
            .@">=" => ">=",
            .@"==" => switch (ctx.config.syntax) {
                .bs => "==",
                .bsx => "nah",
            },
            .@"!=" => switch (ctx.config.syntax) {
                .bs => "!=",
                .bsx => "nah",
            },
            .@"&&" => switch (ctx.config.syntax) {
                .bs => "&&",
                .bsx => "btw",
            },
            .@"|" => switch (ctx.config.syntax) {
                .bs => "|",
                .bsx => "carenot",
            },
            .@"=" => switch (ctx.config.syntax) {
                .bs => "=",
                .bsx => "be",
            },
        });
    }
};

/// A binary expression.
pub const BinaryExpression = struct {
    left: Expression,
    operator: BinaryOperator,
    right: Expression,

    pub fn emit(binary: BinaryExpression, ctx: EmitContext, writer: anytype) !void {
        try binary.left.emit(ctx, writer);
        try writer.writeAll(" ");
        try binary.operator.emit(ctx, writer);
        try writer.writeAll(" ");
        try binary.right.emit(ctx, writer);
    }

    pub fn generateBytecode(binary: BinaryExpression, exe: *Executable) !void {
        // Assignment
        if (binary.operator == .@"=") {
            switch (binary.left) {
                .identifier => |name| {
                    try binary.right.generateBytecode(exe);
                    try exe.emitWithIdentifier(.put_binding, name);
                },
                .member => |member| {
                    try binary.right.generateBytecode(exe);
                    try member.root.generateBytecode(exe);
                    try exe.emitWithIdentifier(.put_property_in_expression, member.name);
                },
                else => unreachable,
            }
            return;
        }

        try binary.left.generateBytecode(exe);
        try binary.right.generateBytecode(exe);
        try exe.emit(switch (binary.operator) {
            .@"+" => .@"+",
            .@"-" => .@"-",
            .@"*" => .@"*",
            .@"/" => .@"/",
            .@"%" => .@"%",
            .@"==" => .@"==",
            .@"!=" => .@"!=",
            .@"<" => .@"<",
            .@">" => .@">",
            .@">=" => .@">=",
            .@"<=" => .@"<=",
            .@"&&" => .@"&&",
            .@"|" => .@"|",
            .@"=" => unreachable,
        });
    }
};

/// An object expression.
pub const ObjectExpression = struct {
    entries: []Entry,

    pub const Entry = struct {
        name: []const u8,
        value: Expression,
    };

    pub fn emit(object: ObjectExpression, ctx: EmitContext, writer: anytype) !void {
        try writer.writeAll("{ ");

        for (object.entries, 0..) |entry, i| {
            if (i != 0) {
                try writer.writeAll(", ");
            }

            try writer.print("{s}: ", .{entry.name});
            try entry.value.emit(ctx, writer);
        }

        try writer.writeAll(" }");
    }

    pub fn generateBytecode(object: ObjectExpression, exe: *Executable) !void {
        try exe.emitWithIndex(.create_object, @intCast(object.entries.len));
        for (object.entries) |entry| {
            try entry.value.generateBytecode(exe);
            try exe.emitWithIdentifier(.put_property, entry.name);
        }
    }
};

/// A statement.
pub const Statement = union(enum) {
    let: LetStatement,
    @"const": ConstStatement,
    @"if": IfStatement,
    try_catch: TryCatchStatement,
    @"for": *ForStatement,
    @"fn": *FnStatement,
    expression: Expression,

    pub fn emit(statement: Statement, ctx: EmitContext, writer: anytype) @TypeOf(writer).Error!void {
        try ctx.writeIndent(writer);
        switch (statement) {
            .let => |let| try let.emit(ctx, writer),
            .@"const" => |@"const"| try @"const".emit(ctx, writer),
            .@"if" => |@"if"| try @"if".emit(ctx, writer),
            .try_catch => |try_catch| try try_catch.emit(ctx, writer),
            .@"for" => |@"for"| try @"for".emit(ctx, writer),
            .@"fn" => |@"fn"| try @"fn".emit(ctx, writer),
            .expression => |expression| try expression.emit(ctx, writer),
        }
        try writer.writeAll("\n");
    }

    pub fn generateBytecode(statement: Statement, exe: *Executable) std.mem.Allocator.Error!void {
        switch (statement) {
            .let => |let| try let.generateBytecode(exe),
            .@"const" => |@"const"| try @"const".generateBytecode(exe),
            .expression => |expression| {
                try expression.generateBytecode(exe);
                try exe.emit(.pop);
            },
            .@"if" => |@"if"| try @"if".generateBytecode(exe),
            .@"for" => |@"for"| try @"for".generateBytecode(exe),
            .@"fn" => |@"fn"| try @"fn".generateBytecode(exe),
            .try_catch => |try_catch| try try_catch.generateBytecode(exe),
        }
    }
};

/// A let statement.
pub const LetStatement = struct {
    name: []const u8,
    expression: Expression,

    pub fn emit(let: LetStatement, ctx: EmitContext, writer: anytype) !void {
        try writer.print("{s} {s} {s} ", .{
            switch (ctx.config.syntax) {
                .bs => "let",
                .bsx => "lit",
            },
            let.name,
            switch (ctx.config.syntax) {
                .bs => "=",
                .bsx => "be",
            },
        });

        try let.expression.emit(ctx, writer);

        try writer.writeAll(switch (ctx.config.syntax) {
            .bs => ";",
            .bsx => " rn",
        });
    }

    pub fn generateBytecode(let: LetStatement, exe: *Executable) !void {
        try let.expression.generateBytecode(exe);
        try exe.emitWithIdentifier(.create_mutable_binding, let.name);
    }
};

/// A const statement.
pub const ConstStatement = struct {
    name: []const u8,
    expression: Expression,

    pub fn emit(@"const": ConstStatement, ctx: EmitContext, writer: anytype) !void {
        try writer.print("{s} {s} {s} ", .{
            switch (ctx.config.syntax) {
                .bs => "const",
                .bsx => "mf",
            },
            @"const".name,
            switch (ctx.config.syntax) {
                .bs => "=",
                .bsx => "be",
            },
        });

        try @"const".expression.emit(ctx, writer);

        try writer.writeAll(switch (ctx.config.syntax) {
            .bs => ";",
            .bsx => " rn",
        });
    }

    pub fn generateBytecode(@"const": ConstStatement, exe: *Executable) !void {
        try @"const".expression.generateBytecode(exe);
        try exe.emitWithIdentifier(.create_binding, @"const".name);
    }
};

/// An if statement.
pub const IfStatement = struct {
    condition: Expression,
    block: []Statement,
    alternates: []Alternate,

    pub const Alternate = struct {
        condition: ?Expression,
        block: []Statement,
    };

    pub fn emit(@"if": IfStatement, ctx: EmitContext, writer: anytype) !void {
        try writer.print("{s} (", .{switch (ctx.config.syntax) {
            .bs => "if",
            .bsx => "sus",
        }});

        try @"if".condition.emit(ctx, writer);

        try writer.writeAll(") {\n");

        for (@"if".block) |stmt| {
            try stmt.emit(ctx.indent(), writer);
        }

        try ctx.writeIndent(writer);
        try writer.writeAll("}");

        for (@"if".alternates) |alternate| {
            if (alternate.condition) |condition| {
                try writer.print("{s} (", .{switch (ctx.config.syntax) {
                    .bs => " else if",
                    .bsx => " impostor sus",
                }});

                try condition.emit(ctx, writer);

                try writer.writeAll(") {\n");
            } else {
                try writer.writeAll(switch (ctx.config.syntax) {
                    .bs => " else {\n",
                    .bsx => " impostor {\n",
                });
            }

            for (alternate.block) |stmt| {
                try stmt.emit(ctx.indent(), writer);
            }

            try ctx.writeIndent(writer);
            try writer.writeAll("}");
        }
    }

    pub fn generateBytecode(@"if": IfStatement, exe: *Executable) !void {
        var merge_jump_indexes = try std.ArrayList(u32).initCapacity(exe.allocator, 1 + @"if".alternates.len);
        defer merge_jump_indexes.deinit();

        try @"if".condition.generateBytecode(exe);

        var next_condition_index = try exe.emitWithMutableIndex(.jump_if_not_true);

        try exe.emit(.push_environment);

        for (@"if".block) |stmt| {
            try stmt.generateBytecode(exe);
        }

        try exe.emit(.pop_environment);

        if (@"if".alternates.len != 0) {
            merge_jump_indexes.appendAssumeCapacity(
                try exe.emitWithMutableIndex(.jump),
            );
        }

        for (@"if".alternates) |alternate| {
            exe.replaceMutableIndex(next_condition_index, @intCast(exe.bytecode.items.len));

            if (alternate.condition) |condition| {
                try condition.generateBytecode(exe);
                next_condition_index = try exe.emitWithMutableIndex(.jump_if_not_true);
            }

            try exe.emit(.push_environment);

            for (alternate.block) |stmt| {
                try stmt.generateBytecode(exe);
            }

            try exe.emit(.pop_environment);

            merge_jump_indexes.appendAssumeCapacity(
                try exe.emitWithMutableIndex(.jump),
            );
        }

        if (@"if".alternates.len == 0 or @"if".alternates[@"if".alternates.len - 1].condition != null) {
            exe.replaceMutableIndex(next_condition_index, @intCast(exe.bytecode.items.len));
        }

        for (merge_jump_indexes.items) |index| {
            exe.replaceMutableIndex(index, @intCast(exe.bytecode.items.len));
        }
    }
};

/// A for statement.
pub const ForStatement = struct {
    init: Statement,
    @"test": Expression,
    update: Expression,
    block: []Statement,

    pub fn emit(@"for": ForStatement, ctx: EmitContext, writer: anytype) !void {
        try writer.print("{s} (", .{switch (ctx.config.syntax) {
            .bs => "for",
            .bsx => "yall",
        }});

        switch (@"for".init) {
            .let => |let| try let.emit(ctx, writer),
            .@"const" => |@"const"| try @"const".emit(ctx, writer),
            else => unreachable,
        }
        try writer.writeAll(" ");
        try @"for".@"test".emit(ctx, writer);
        try writer.writeAll(switch (ctx.config.syntax) {
            .bs => "; ",
            .bsx => " rn ",
        });
        try @"for".update.emit(ctx, writer);

        try writer.writeAll(") {\n");

        for (@"for".block) |stmt| {
            try stmt.emit(ctx.indent(), writer);
        }

        try ctx.writeIndent(writer);
        try writer.writeAll("}");
    }

    pub fn generateBytecode(@"for": ForStatement, exe: *Executable) !void {
        try exe.emit(.push_environment);
        try @"for".init.generateBytecode(exe);

        try exe.emit(.push_environment);

        const body_index: u32 = @intCast(exe.bytecode.items.len);
        try @"for".@"test".generateBytecode(exe);
        const jump_index = try exe.emitWithMutableIndex(.jump_if_not_true);

        for (@"for".block) |stmt| {
            try stmt.generateBytecode(exe);
        }

        try @"for".update.generateBytecode(exe);
        try exe.emit(.pop);
        try exe.emit(.reset_environment);

        try exe.emitWithIndex(.jump, @intCast(body_index));

        exe.replaceMutableIndex(jump_index, @intCast(exe.bytecode.items.len));

        try exe.emit(.pop_environment);
        try exe.emit(.pop_environment);
    }
};

/// A try-catch statement.
pub const TryCatchStatement = struct {
    @"try": []Statement,
    @"catch": []Statement,

    pub fn emit(try_catch: TryCatchStatement, ctx: EmitContext, writer: anytype) !void {
        try writer.print("{s} {{", .{switch (ctx.config.syntax) {
            .bs => "try",
            .bsx => "fuck_around",
        }});

        for (try_catch.@"try") |stmt| {
            try stmt.emit(ctx.indent(), writer);
        }

        try ctx.writeIndent(writer);
        try writer.print("}} {s} {{\n", .{switch (ctx.config.syntax) {
            .bs => "catch",
            .bsx => "find_out",
        }});

        for (try_catch.@"catch") |stmt| {
            try stmt.emit(ctx.indent(), writer);
        }

        try ctx.writeIndent(writer);
        try writer.writeAll("}");
    }

    pub fn generateBytecode(try_catch: TryCatchStatement, exe: *Executable) !void {
        const exception_index = try exe.emitWithMutableIndex(.push_fallible);

        for (try_catch.@"try") |stmt| {
            try stmt.generateBytecode(exe);
        }

        try exe.emit(.pop_fallbile);

        const merge_index = try exe.emitWithMutableIndex(.jump);

        exe.replaceMutableIndex(exception_index, @intCast(exe.bytecode.items.len));

        for (try_catch.@"catch") |stmt| {
            try stmt.generateBytecode(exe);
        }

        exe.replaceMutableIndex(merge_index, @intCast(exe.bytecode.items.len));
    }
};

/// A function statement.
pub const FnStatement = struct {
    name: []const u8,
    parameters: [][]const u8,
    block: []Statement,

    pub fn emit(@"fn": FnStatement, ctx: EmitContext, writer: anytype) !void {
        try writer.print("{s} {s}(", .{ switch (ctx.config.syntax) {
            .bs => "fn",
            .bsx => "bruh",
        }, @"fn".name });

        for (@"fn".parameters, 0..) |parameter, i| {
            if (i != 0) {
                try writer.writeAll(", ");
            }

            try writer.writeAll(parameter);
        }

        try writer.writeAll(") {\n");

        for (@"fn".block) |stmt| {
            try stmt.emit(ctx.indent(), writer);
        }

        try ctx.writeIndent(writer);
        try writer.writeAll("}");
    }

    pub fn generateBytecode(@"fn": *FnStatement, exe: *Executable) !void {
        // NOTE: Functions are compiled lazily so we just add the node.
        try exe.emitWithFunctionData(.put_function, .{
            .node = @"fn",
        });
    }
};
