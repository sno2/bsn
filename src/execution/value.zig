const std = @import("std");

const Heap = @import("Heap.zig");
const VM = @import("VM.zig");

const BuiltinFunctionHeap = Heap.BuiltinFunctionHeap;
const ExecutableHeap = Heap.ExecutableHeap;
const NumberHeap = Heap.NumberHeap;
const ObjectHeap = Heap.ObjectHeap;
const ReadonlyStringHeap = Heap.ReadonlyStringHeap;
const StringHeap = Heap.StringHeap;

/// A Bussin value.
pub const Value = union(enum) {
    null,
    boolean: bool,
    number_i32: i32,
    number_f64: NumberHeap.Index,
    string: StringHeap.Index,
    readonly_string: ReadonlyStringHeap.Index,
    object: ObjectHeap.Index,
    builtin_function: BuiltinFunctionHeap.Index,
    executable: ExecutableHeap.Index,

    pub fn from(value: anytype) Value {
        return switch (@TypeOf(value)) {
            bool => .{ .boolean = value },
            i32 => .{ .number_i32 = value },
            comptime_int => .{ .number_i32 = @intCast(value) },
            else => @compileError("Unsupported value type: " ++ @typeName(@TypeOf(value))),
        };
    }

    inline fn haveSameTag(left: Value, right: Value) bool {
        return @intFromEnum(left) == @intFromEnum(right);
    }

    inline fn toReal(value: Value, vm: *VM) ?f64 {
        return switch (value) {
            .number_i32 => |integer| @floatFromInt(integer),
            .number_f64 => |index| vm.heap.numbers.get(index),
            else => null,
        };
    }

    pub fn @"+"(vm: *VM, left: Value, right: Value) !Value {
        // OPTIMIZATION: Use integer addition if they are both integers.
        if (left == .number_i32 and right == .number_i32) {
            if (std.math.add(i32, left.number_i32, right.number_i32) catch null) |integer| {
                return Value.from(integer);
            }
        }

        const left_real = left.toReal(vm) orelse
            try vm.throwException("Left-hand side is not a number: %.", .{left});

        const right_real = right.toReal(vm) orelse
            try vm.throwException("Right-hand side is not a number: %.", .{right});

        return .{ .number_f64 = try vm.heap.numbers.create(&vm.heap, left_real + right_real) };
    }

    pub fn @"-"(vm: *VM, left: Value, right: Value) !Value {
        // OPTIMIZATION: Use integer subtraction if they are both integers.
        if (left == .number_i32 and right == .number_i32) {
            if (std.math.sub(i32, left.number_i32, right.number_i32) catch null) |integer| {
                return Value.from(integer);
            }
        }

        const left_real = left.toReal(vm) orelse
            try vm.throwException("Left-hand side is not a number: %.", .{left});

        const right_real = right.toReal(vm) orelse
            try vm.throwException("Right-hand side is not a number: %.", .{right});

        return .{ .number_f64 = try vm.heap.numbers.create(&vm.heap, left_real - right_real) };
    }

    pub fn @"*"(vm: *VM, left: Value, right: Value) !Value {
        // OPTIMIZATION: Use integer multiplication if they are both integers.
        if (left == .number_i32 and right == .number_i32) {
            if (std.math.mul(i32, left.number_i32, right.number_i32) catch null) |integer| {
                return Value.from(integer);
            }
        }

        const left_real = left.toReal(vm) orelse
            try vm.throwException("Left-hand side is not a number: %.", .{left});

        const right_real = right.toReal(vm) orelse
            try vm.throwException("Right-hand side is not a number: %.", .{right});

        return .{ .number_f64 = try vm.heap.numbers.create(&vm.heap, left_real * right_real) };
    }

    pub fn @"/"(vm: *VM, left: Value, right: Value) !Value {
        // OPTIMIZATION: Use integer division if they are both integers.
        if (left == .number_i32 and right == .number_i32) {
            if (std.math.divExact(i32, left.number_i32, right.number_i32) catch null) |integer| {
                return Value.from(integer);
            }
        }

        const left_real = left.toReal(vm) orelse
            try vm.throwException("Left-hand side is not a number: %.", .{left});

        const right_real = right.toReal(vm) orelse
            try vm.throwException("Right-hand side is not a number: %.", .{right});

        if (right_real == 0)
            return try vm.throwException("Division by zero.", &.{});

        return .{ .number_f64 = try vm.heap.numbers.create(&vm.heap, left_real / right_real) };
    }

    pub fn @"%"(vm: *VM, left: Value, right: Value) !Value {
        // OPTIMIZATION: Use integer modulo if they are both integers.
        if (left == .number_i32 and right == .number_i32) {
            if (std.math.rem(i32, left.number_i32, right.number_i32) catch null) |integer| {
                return Value.from(integer);
            }
        }

        const left_real = left.toReal(vm) orelse
            try vm.throwException("Left-hand side is not a number: %.", .{left});

        const right_real = right.toReal(vm) orelse
            try vm.throwException("Right-hand side is not a number: %.", .{right});

        if (right_real == 0) {
            return try vm.throwException("Division by zero.", &.{});
        }

        // NOTE: JavaScript does the absolute value on the right-hand side so
        // we will just blindly follow that :^)
        return .{ .number_f64 = try vm.heap.numbers.create(&vm.heap, @mod(left_real, @abs(right_real))) };
    }

    pub fn equalTo(heap: *Heap, left: Value, right: Value) bool {
        return switch (left) {
            .null => right == .null,
            .boolean => |left_value| switch (right) {
                .boolean => |right_value| left_value == right_value,
                else => false,
            },
            .number_i32 => |left_value| switch (right) {
                .number_i32 => |right_value| left_value == right_value,
                .number_f64 => |right_index| @as(f64, @floatFromInt(left_value)) == heap.numbers.get(right_index),
                else => false,
            },
            .number_f64 => |left_index| switch (right) {
                .number_i32 => |right_value| heap.numbers.get(left_index) == @as(f64, @floatFromInt(right_value)),
                .number_f64 => |right_index| left_index == right_index or heap.numbers.get(left_index) == heap.numbers.get(right_index),
                else => false,
            },
            .readonly_string, .string => {
                const left_bytes = switch (left) {
                    .readonly_string => heap.readonly_strings.get(left.readonly_string),
                    .string => heap.strings.get(left.string),
                    else => unreachable,
                };

                const right_bytes = switch (right) {
                    .readonly_string => heap.readonly_strings.get(right.readonly_string),
                    .string => heap.strings.get(right.string),
                    else => return false,
                };

                return std.mem.eql(u8, left_bytes, right_bytes);
            },
            .object => |left_index| switch (right) {
                .object => |right_index| left_index == right_index,
                else => false,
            },
            .builtin_function => |left_index| switch (right) {
                .builtin_function => |right_index| {
                    if (left_index == right_index) {
                        return true;
                    }

                    // NOTE: We may be able to remove this later if we make sure
                    // we don't create multiple builtin functions to the same
                    // function in the heap.
                    return heap.builtin_functions.get(left_index) == heap.builtin_functions.get(right_index);
                },
                else => false,
            },
            .executable => |left_index| switch (right) {
                .executable => |right_index| left_index == right_index,
                else => false,
            },
        };
    }

    pub fn @"<"(vm: *VM, left: Value, right: Value) !bool {
        return switch (left) {
            .number_i32 => |left_value| switch (right) {
                .number_i32 => |right_value| left_value < right_value,
                .number_f64 => |right_index| @as(f64, @floatFromInt(left_value)) < vm.heap.numbers.get(right_index),
                else => try vm.throwException("Right-hand side is not a number: %.", .{right}),
            },
            .number_f64 => |left_index| switch (right) {
                .number_i32 => |right_value| vm.heap.numbers.get(left_index) < @as(f64, @floatFromInt(right_value)),
                .number_f64 => |right_index| vm.heap.numbers.get(left_index) < vm.heap.numbers.get(right_index),
                else => try vm.throwException("Right-hand side is not a number: %.", .{right}),
            },
            else => try vm.throwException("Left-hand side is not a number: %.", .{left}),
        };
    }

    pub fn @">"(vm: *VM, left: Value, right: Value) !bool {
        return switch (left) {
            .number_i32 => |left_value| switch (right) {
                .number_i32 => |right_value| left_value > right_value,
                .number_f64 => |right_index| @as(f64, @floatFromInt(left_value)) > vm.heap.numbers.get(right_index),
                else => try vm.throwException("Right-hand side is not a number: %.", .{right}),
            },
            .number_f64 => |left_index| switch (right) {
                .number_i32 => |right_value| vm.heap.numbers.get(left_index) > @as(f64, @floatFromInt(right_value)),
                .number_f64 => |right_index| vm.heap.numbers.get(left_index) > vm.heap.numbers.get(right_index),
                else => try vm.throwException("Right-hand side is not a number: %.", .{right}),
            },
            else => try vm.throwException("Left-hand side is not a number: %.", .{left}),
        };
    }

    pub fn @"<="(vm: *VM, left: Value, right: Value) !bool {
        return switch (left) {
            .number_i32 => |left_value| switch (right) {
                .number_i32 => |right_value| left_value <= right_value,
                .number_f64 => |right_index| @as(f64, @floatFromInt(left_value)) <= vm.heap.numbers.get(right_index),
                else => try vm.throwException("Right-hand side is not a number: %.", .{right}),
            },
            .number_f64 => |left_index| switch (right) {
                .number_i32 => |right_value| vm.heap.numbers.get(left_index) <= @as(f64, @floatFromInt(right_value)),
                .number_f64 => |right_index| vm.heap.numbers.get(left_index) <= vm.heap.numbers.get(right_index),
                else => try vm.throwException("Right-hand side is not a number: %.", .{right}),
            },
            else => try vm.throwException("Left-hand side is not a number: %.", .{left}),
        };
    }

    pub fn @">="(vm: *VM, left: Value, right: Value) !bool {
        return switch (left) {
            .number_i32 => |left_value| switch (right) {
                .number_i32 => |right_value| left_value >= right_value,
                .number_f64 => |right_index| @as(f64, @floatFromInt(left_value)) >= vm.heap.numbers.get(right_index),
                else => try vm.throwException("Right-hand side is not a number: %.", .{right}),
            },
            .number_f64 => |left_index| switch (right) {
                .number_i32 => |right_value| vm.heap.numbers.get(left_index) >= @as(f64, @floatFromInt(right_value)),
                .number_f64 => |right_index| vm.heap.numbers.get(left_index) >= vm.heap.numbers.get(right_index),
                else => try vm.throwException("Right-hand side is not a number: %.", .{right}),
            },
            else => try vm.throwException("Left-hand side is not a number: %.", .{left}),
        };
    }

    pub fn @"|"(vm: *VM, left: Value, right: Value) !bool {
        return switch (left) {
            .boolean => |left_value| switch (right) {
                .boolean => |right_value| left_value or right_value,
                else => try vm.throwException("Right-hand side is not a boolean: %.", .{right}),
            },
            else => try vm.throwException("Left-hand side is not a boolean: %.", .{left}),
        };
    }

    pub fn @"&&"(vm: *VM, left: Value, right: Value) !bool {
        return switch (left) {
            .boolean => |left_value| switch (right) {
                .boolean => |right_value| left_value and right_value,
                else => try vm.throwException("Right-hand side is not a boolean: %.", .{right}),
            },
            else => try vm.throwException("Left-hand side is not a boolean: %.", .{left}),
        };
    }
};
