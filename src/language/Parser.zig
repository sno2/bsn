//! A Parser for the Bussin language.

// NOTE: At multiple times in this file, we do not call toOwnedSlice() on
// ArrayLists. This is because we use an arena allocator, so shrinking to the
// capacity will not actually free the old list's memory.

const std = @import("std");

const ast = @import("ast.zig");
const Config = @import("Config.zig");
const Lexer = @import("Lexer.zig");

const Token = Lexer.Token;

const Parser = @This();

/// The arena allocator for data.
arena: std.mem.Allocator,

/// The underlying lazy lexer.
lex: Lexer,

/// The extra error data. This is only valid to use if the last call to a Parser
/// function returned an error.
error_context: ?union(enum) {
    expected: struct {
        expected: Token.Tag,
        found: Token.Tag,
    },
    expected_statement: struct { found: Token.Tag },
    expected_expression: struct { found: Token.Tag },
    expected_variable_declaration: struct { found: Token.Tag },
    invalid_assignment_target,

    pub fn writeTokenTag(token: Token.Tag, writer: anytype) !void {
        switch (token) {
            .number_i32 => try writer.writeAll("a number literal"),
            .number_f64 => try writer.writeAll("a number literal"),
            .identifier => try writer.writeAll("an identifier"),
            .eof => try writer.writeAll("the end of the file"),
            else => try writer.writeAll(@tagName(token)),
        }
    }

    pub fn write(self: @This(), p: Parser, writer: anytype) !void {
        _ = p;
        switch (self) {
            .expected => |data| {
                try writer.writeAll("Expected ");
                try writeTokenTag(data.expected, writer);
                try writer.writeAll(", found ");
                try writeTokenTag(data.found, writer);
            },
            .expected_statement => |data| {
                try writer.writeAll("Expected statement, found ");
                try writeTokenTag(data.found, writer);
            },
            .expected_expression => |data| {
                try writer.writeAll("Expected expression, found ");
                try writeTokenTag(data.found, writer);
            },
            .expected_variable_declaration => |data| {
                try writer.writeAll("Expected variable declaration, found ");
                try writeTokenTag(data.found, writer);
            },
            .invalid_assignment_target => {
                try writer.writeAll("Invalid assignment target");
            },
        }
    }
} = null,

/// The possible errors that can occur while parsing.
pub const Error = std.mem.Allocator.Error || error{SyntaxError};

pub fn init(arena: std.mem.Allocator, source: []const u8, config: Config) Parser {
    return Parser{
        .arena = arena,
        .lex = Lexer.init(source, config),
    };
}

/// Eats a token if it matches the given tag and returns a boolean indicating if
/// a token was eaten.
fn eat(p: *Parser, tag: Token.Tag) bool {
    if (p.lex.token != tag) {
        p.error_context = .{ .expected = .{ .expected = tag, .found = p.lex.token } };
        return false;
    }
    p.lex.next();
    return true;
}

/// Accepts a token.
fn accept(p: *Parser, tag: Token.Tag) !void {
    if (p.lex.token != tag) {
        p.error_context = .{ .expected = .{ .expected = tag, .found = p.lex.token } };
        return error.SyntaxError;
    }
    p.lex.next();
}

/// Accepts a token with a payload.
fn acceptWithPayload(p: *Parser, comptime tag: Token.Tag) !std.meta.TagPayload(Token, tag) {
    if (p.lex.token != tag) {
        p.error_context = .{ .expected = .{ .expected = tag, .found = p.lex.token } };
        return error.SyntaxError;
    }
    const payload = @field(p.lex.token, @tagName(tag));
    p.lex.next();
    return payload;
}

/// Accepts an expression.
pub fn acceptExpression(p: *Parser) Error!ast.Expression {
    return p.acceptExpressionRec(0);
}

/// Accepts an expression with a precedence power.
fn acceptExpressionRec(p: *Parser, highest_power: u8) Error!ast.Expression {
    var left = try p.acceptPrimaryExpression();

    while (true) {
        const token = p.lex.token;
        const power = getOperatorPrecedence(token);

        if (power < highest_power or (getOperatorAssociativity(token) == .left_to_right and power == highest_power)) {
            break;
        }

        p.lex.next();

        switch (token) {
            // Function call
            .@"(" => {
                var data = try std.ArrayList(ast.Expression).initCapacity(p.arena, 1);
                data.appendAssumeCapacity(left);

                while (!p.eat(.@")")) {
                    const argument = try p.acceptExpression();
                    try data.append(argument);

                    if (!p.eat(.@",")) {
                        try p.accept(.@")");
                        break;
                    }
                }

                left = .{ .function_call = .{ .data = data.items } };
            },
            // Member expression
            .@"." => {
                const name = try p.acceptWithPayload(.identifier);
                const member = try p.arena.create(ast.MemberExpression);
                member.* = .{ .root = left, .name = name };
                left = .{ .member = member };
            },
            // Assignment expression
            .@"=" => {
                switch (left) {
                    .identifier, .member => {},
                    else => {
                        p.error_context = .invalid_assignment_target;
                        return error.SyntaxError;
                    },
                }

                const binary = try p.arena.create(ast.BinaryExpression);
                binary.* = .{ .left = left, .operator = .@"=", .right = try p.acceptExpressionRec(power) };
                left = .{ .binary = binary };
            },
            // Binary expression
            else => {
                const operator = ast.BinaryOperator.fromTokenTag(token);
                const binary = try p.arena.create(ast.BinaryExpression);
                binary.* = .{ .left = left, .operator = operator, .right = try p.acceptExpressionRec(power) };
                left = .{ .binary = binary };
            },
        }
    }

    return left;
}

/// Returns the precedence power of a token.
fn getOperatorPrecedence(token: Token) u8 {
    return switch (token) {
        .@"(", .@"." => 8,
        .@"*", .@"/", .@"%" => 7,
        .@"+", .@"-" => 6,
        .@">", .@"<", .@">=", .@"<=" => 5,
        .@"==", .@"!=" => 4,
        .@"&&" => 3,
        .@"|" => 2,
        .@"=" => 1,
        else => 0,
    };
}

/// The associativity of an operator.
const OperatorAssociativity = enum {
    left_to_right,
    right_to_left,
};

/// Returns the associativity of a token.
fn getOperatorAssociativity(token: Token) OperatorAssociativity {
    return switch (token) {
        .@"=" => .right_to_left,
        else => .left_to_right,
    };
}

/// Accepts a primary expression.
fn acceptPrimaryExpression(p: *Parser) !ast.Expression {
    switch (p.lex.token) {
        .null => {
            p.lex.next();
            return .null;
        },
        .identifier => |name| {
            p.lex.next();
            return .{ .identifier = name };
        },
        .number_i32 => |number| {
            p.lex.next();
            return .{ .number_i32 = number };
        },
        .number_f64 => |number| {
            p.lex.next();
            return .{ .number_f64 = number };
        },
        .string => |string| {
            p.lex.next();
            return .{ .string = string };
        },
        .true => {
            p.lex.next();
            return .{ .boolean = true };
        },
        .false => {
            p.lex.next();
            return .{ .boolean = false };
        },
        .@"(" => {
            p.lex.next();
            const expression = try p.acceptExpression();
            try p.accept(.@")");
            return expression;
        },
        .@"{" => {
            p.lex.next();

            var entries = std.ArrayList(ast.ObjectExpression.Entry).init(p.arena);

            while (!p.eat(.@"}")) {
                const name = try p.acceptWithPayload(.identifier);
                const value = if (p.eat(.@":"))
                    try p.acceptExpression()
                else
                    ast.Expression{ .identifier = name };

                try entries.append(.{ .name = name, .value = value });

                if (!p.eat(.@",")) {
                    try p.accept(.@"}");
                    break;
                }
            }

            return .{ .object = .{ .entries = entries.items } };
        },
        else => {
            p.error_context = .{ .expected_expression = .{ .found = p.lex.token } };
            return error.SyntaxError;
        },
    }
}

/// Accepts a let statement.
fn acceptLetStatement(p: *Parser) !ast.LetStatement {
    try p.accept(.let);
    const name = try p.acceptWithPayload(.identifier);
    try p.accept(.@"=");
    const expression = try p.acceptExpression();
    _ = p.eat(.@";");
    return .{ .name = name, .expression = expression };
}

/// Accepts a const statement.
fn acceptConstStatement(p: *Parser) !ast.ConstStatement {
    try p.accept(.@"const");
    const name = try p.acceptWithPayload(.identifier);
    try p.accept(.@"=");
    const expression = try p.acceptExpression();
    _ = p.eat(.@";");
    return .{ .name = name, .expression = expression };
}

/// Accepts a let or const statement.
fn acceptVariableDeclaration(p: *Parser) !ast.Statement {
    return switch (p.lex.token) {
        .let => .{ .let = try p.acceptLetStatement() },
        .@"const" => .{ .@"const" = try p.acceptConstStatement() },
        else => {
            p.error_context = .{ .expected_variable_declaration = .{ .found = p.lex.token } };
            return error.SyntaxError;
        },
    };
}

/// Accepts an if statement.
fn acceptIfStatement(p: *Parser) !ast.IfStatement {
    try p.accept(.@"if");
    try p.accept(.@"(");
    const condition = try p.acceptExpression();
    try p.accept(.@")");
    const block = try p.acceptBlock();

    var alternates = std.ArrayList(ast.IfStatement.Alternate).init(p.arena);

    while (p.eat(.@"else")) {
        if (!p.eat(.@"if")) {
            const sub_block = try p.acceptBlock();
            try alternates.append(.{ .condition = null, .block = sub_block });
            break;
        }

        try p.accept(.@"(");
        const sub_condition = try p.acceptExpression();
        try p.accept(.@")");
        const sub_block = try p.acceptBlock();

        try alternates.append(.{ .condition = sub_condition, .block = sub_block });
    }

    return .{ .condition = condition, .block = block, .alternates = alternates.items };
}

/// Accepts a block, or list of statements delimited by curly braces.
fn acceptBlock(p: *Parser) ![]ast.Statement {
    var statements = std.ArrayList(ast.Statement).init(p.arena);

    try p.accept(.@"{");
    while (!p.eat(.@"}")) {
        const statement = try acceptStatement(p);
        try statements.append(statement);
    }

    return statements.items;
}

/// Accepts a try-catch statement.
fn acceptTryCatchStatement(p: *Parser) !ast.TryCatchStatement {
    try p.accept(.@"try");
    const @"try" = try p.acceptBlock();
    try p.accept(.@"catch");
    const @"catch " = try p.acceptBlock();
    return .{ .@"try" = @"try", .@"catch" = @"catch " };
}

/// Accepts a for statement.
fn acceptForStatement(p: *Parser) !ast.ForStatement {
    try p.accept(.@"for");
    try p.accept(.@"(");
    const init_value = try acceptVariableDeclaration(p);
    const @"test" = try p.acceptExpression();
    try p.accept(.@";");
    const update = try p.acceptExpression();
    try p.accept(.@")");
    const block = try p.acceptBlock();
    return .{ .init = init_value, .@"test" = @"test", .update = update, .block = block };
}

/// Accepts a function statement.
fn acceptFnStatement(p: *Parser) !ast.FnStatement {
    try p.accept(.@"fn");
    const name = try p.acceptWithPayload(.identifier);
    try p.accept(.@"(");
    var parameters = std.ArrayList([]const u8).init(p.arena);

    while (!p.eat(.@")")) {
        const parameter = try p.acceptWithPayload(.identifier);
        try parameters.append(parameter);

        if (!p.eat(.@",")) {
            try p.accept(.@")");
            break;
        }
    }

    const block = try p.acceptBlock();
    return .{ .name = name, .parameters = parameters.items, .block = block };
}

/// Accepts a statement.
pub fn acceptStatement(p: *Parser) Error!ast.Statement {
    switch (p.lex.token) {
        .let => return .{ .let = try p.acceptLetStatement() },
        .@"const" => return .{ .@"const" = try p.acceptConstStatement() },
        .@"if" => return .{ .@"if" = try p.acceptIfStatement() },
        .@"try" => return .{ .try_catch = try p.acceptTryCatchStatement() },
        .@"for" => {
            const data = try p.arena.create(ast.ForStatement);
            data.* = try p.acceptForStatement();
            return .{ .@"for" = data };
        },
        .@"fn" => {
            const data = try p.arena.create(ast.FnStatement);
            data.* = try p.acceptFnStatement();
            return .{ .@"fn" = data };
        },
        else => {
            const expression = try p.acceptExpression();
            _ = p.eat(.@";");
            return .{ .expression = expression };
        },
    }
}

/// Parses a program.
pub fn parse(p: *Parser) ![]ast.Statement {
    var statements = std.ArrayList(ast.Statement).init(p.arena);

    while (p.lex.token != .eof) {
        const statement = try p.acceptStatement();
        try statements.append(statement);
    }

    return statements.items;
}
