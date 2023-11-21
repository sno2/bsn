//! The virtual machine for running executables.

const std = @import("std");

const Executable = @import("Executable.zig");
const Heap = @import("Heap.zig");
const language = @import("../language.zig");
const Value = @import("value.zig").Value;

const Config = language.Config;
const Environment = Heap.Environment;

const VM = @This();

/// The configuration.
config: Config,

/// The heap.
heap: Heap,

/// The random number generator.
rng: std.rand.DefaultPrng,

/// The error context.
error_context: ?[]u8 = null,

pub const Error = std.mem.Allocator.Error || error{Exception};

pub const Arguments = struct {
    items: []const Value,

    pub fn get(args: Arguments, index: usize) Value {
        return if (index < args.items.len) args.items[index] else .null;
    }
};

fn writeInnerValue(vm: *VM, writer: anytype, value: Value) @TypeOf(writer).Error!void {
    switch (value) {
        .readonly_string => |string_index| try writer.print("\"{s}\"", .{vm.heap.readonly_strings.get(string_index)}),
        .string => |string_index| try writer.print("\"{s}\"", .{vm.heap.strings.get(string_index)}),
        else => try vm.writeValue(writer, value),
    }
}

/// Writes a string version of the value to the writer.
fn writeValue(vm: *VM, writer: anytype, value: Value) !void {
    switch (value) {
        .null => try writer.writeAll(switch (vm.config.syntax) {
            .bs => "null",
            .bsx => "fake",
        }),
        .boolean => |boolean| try writer.print("{}", .{boolean}),
        .number_i32 => |number| try writer.print("{}", .{number}),
        .number_f64 => |number_index| try writer.print("{d}", .{vm.heap.numbers.get(number_index)}),
        .readonly_string => |string_index| try writer.writeAll(vm.heap.readonly_strings.get(string_index)),
        .string => |string_index| try writer.writeAll(vm.heap.strings.get(string_index)),
        .object => |object_index| {
            const object: Heap.ObjectHeap.Item = vm.heap.objects.get(object_index);

            try writer.writeAll("{ ");

            var entries = object.iterator();
            var i: usize = 0;
            while (entries.next()) |entry| {
                if (i != 0) {
                    try writer.writeAll(", ");
                }

                try writer.print("{s}: ", .{entry.key_ptr.*});
                try vm.writeInnerValue(writer, entry.value_ptr.*);
                i += 1;
            }

            try writer.writeAll(" }");
        },
        .executable => |executable_index| try writer.print("[Object function: 0x{x}]", .{executable_index}),
        .builtin_function => |builtin_index| try writer.print("[Object function: 0x{x}]", .{builtin_index}),
    }
}

/// Prints a value to stdout.
fn println(vm: *VM, arguments: Arguments) Error!Value {
    var stdout = std.io.getStdOut().writer();

    for (arguments.items, 0..) |value, i| {
        if (i != 0)
            stdout.writeByte(' ') catch
                return error.OutOfMemory;

        vm.writeValue(stdout, value) catch
            return error.OutOfMemory;
    }

    stdout.writeByte('\n') catch
        return error.OutOfMemory;

    return .null;
}

/// Concatenates two values.
fn strcon(vm: *VM, arguments: Arguments) Error!Value {
    var result = std.ArrayList(u8).init(vm.heap.sparse);
    errdefer result.deinit();

    var writer = result.writer();

    vm.writeValue(writer, arguments.get(0)) catch
        try vm.throwException("Unable to print first value.", .{});

    vm.writeValue(writer, arguments.get(1)) catch
        try vm.throwException("Unable to print second value.", &.{});

    return .{ .string = try vm.heap.strings.create(&vm.heap, try result.toOwnedSlice()) };
}

/// Runs a command and returns the output.
fn exec(vm: *VM, arguments: Arguments) Error!Value {
    const message = arguments.get(0).getStringBytes(&vm.heap) orelse
        try vm.throwException("Expected a string argument, found %.", .{arguments.get(0)});

    if (!std.process.can_spawn) {
        try vm.throwException("Spawning platforms is unsupported on this platform.", &.{});
    }

    const result = std.ChildProcess.run(.{
        .allocator = vm.heap.sparse,
        .argv = &.{message},
    }) catch {
        try vm.throwException("Unable to run command.", &.{});
    };

    errdefer vm.heap.sparse.free(result.stdout);
    vm.heap.sparse.free(result.stderr);

    return .{ .string = try vm.heap.strings.create(&vm.heap, result.stdout) };
}

fn input(vm: *VM, arguments: Arguments) Error!Value {
    var stdout = std.io.getStdOut().writer();

    for (arguments.items) |value| {
        vm.writeValue(stdout, value) catch
            return error.OutOfMemory;
    }

    var reader = std.io.getStdIn().reader();
    var data = reader.readUntilDelimiterAlloc(vm.heap.sparse, '\n', 4096) catch
        return error.OutOfMemory;

    errdefer vm.heap.sparse.free(data);

    return .{ .string = try vm.heap.strings.create(&vm.heap, data) };
}

fn format(vm: *VM, arguments: Arguments) Error!Value {
    const format_string = arguments.get(0).getStringBytes(&vm.heap) orelse
        try vm.throwException("Expected a string argument, found %.", .{arguments.get(0)});

    var output = try std.ArrayList(u8).initCapacity(vm.heap.sparse, format_string.len);

    var last_skipped: usize = 0;
    var i: usize = 0;
    var argument_slice = arguments.items[1..];

    while (i < format_string.len) : (i += 1) {
        if (std.mem.startsWith(u8, format_string[i..], "${}")) {
            try output.appendSlice(format_string[last_skipped..i]);
            last_skipped = i + 3;

            const value = if (argument_slice.len == 0)
                try vm.throwException("Format argument count does not match string templates.", .{})
            else
                argument_slice[0];
            argument_slice = argument_slice[1..];

            vm.writeValue(output.writer(), value) catch
                return error.OutOfMemory;
        }
    }

    if (last_skipped < format_string.len) {
        try output.appendSlice(format_string[last_skipped..]);
    }

    return .{ .string = try vm.heap.strings.create(&vm.heap, try output.toOwnedSlice()) };
}

/// Gets the current time.
fn time(vm: *VM, _: Arguments) Error!Value {
    return .{ .number_f64 = try vm.heap.numbers.create(&vm.heap, @floatFromInt(std.time.timestamp())) };
}

/// Sets a random time.
fn random(vm: *VM, _: Arguments) Error!Value {
    return .{ .number_f64 = try vm.heap.numbers.create(&vm.heap, vm.rng.random().float(f64)) };
}

/// Gets the square root of the number.
fn sqrt(vm: *VM, arguments: Arguments) Error!Value {
    return switch (arguments.get(0)) {
        .number_i32 => |value| {
            // TODO: There is probably a faster way to get the square root if
            // the result is an integer.
            return .{ .number_f64 = try vm.heap.numbers.create(
                &vm.heap,
                @sqrt(@as(f64, @floatFromInt(value))),
            ) };
        },
        .number_f64 => |index| .{ .number_f64 = try vm.heap.numbers.create(
            &vm.heap,
            @sqrt(vm.heap.numbers.get(index)),
        ) },
        else => try vm.throwException("Expected a number argument.", &.{}),
    };
}

/// Creates a virtual machine with the default global environment.
pub fn init(initial_heap: Heap, config: Config) !VM {
    var heap = initial_heap;
    var environment = Environment{};

    try environment.put(
        heap.sparse,
        "println",
        .{ .value = .{ .builtin_function = try heap.builtin_functions.create(&heap, &println) } },
    );

    if (config.syntax == .bsx) {
        try environment.put(
            heap.sparse,
            "waffle",
            .{ .value = .{ .builtin_function = try heap.builtin_functions.create(&heap, &println) } },
        );
    }

    try environment.put(
        heap.sparse,
        "strcon",
        .{ .value = .{ .builtin_function = try heap.builtin_functions.create(&heap, &strcon) } },
    );

    try environment.put(
        heap.sparse,
        "exec",
        .{ .value = .{ .builtin_function = try heap.builtin_functions.create(&heap, &exec) } },
    );

    if (config.syntax == .bsx) {
        try environment.put(
            heap.sparse,
            "clapback",
            .{ .value = .{ .builtin_function = try heap.builtin_functions.create(&heap, &exec) } },
        );
    }

    try environment.put(
        heap.sparse,
        "input",
        .{ .value = .{ .builtin_function = try heap.builtin_functions.create(&heap, &input) } },
    );

    if (config.syntax == .bsx) {
        try environment.put(
            heap.sparse,
            "yap",
            .{ .value = .{ .builtin_function = try heap.builtin_functions.create(&heap, &input) } },
        );
    }

    try environment.put(
        heap.sparse,
        "format",
        .{ .value = .{ .builtin_function = try heap.builtin_functions.create(&heap, &format) } },
    );

    var math_object = std.StringHashMapUnmanaged(Value){};

    try math_object.put(
        heap.sparse,
        "pi",
        .{ .number_f64 = try heap.numbers.create(&heap, std.math.pi) },
    );

    try math_object.put(
        heap.sparse,
        "random",
        .{ .builtin_function = try heap.builtin_functions.create(&heap, &random) },
    );

    try math_object.put(
        heap.sparse,
        "sqrt",
        .{ .builtin_function = try heap.builtin_functions.create(&heap, &sqrt) },
    );

    try environment.put(
        heap.sparse,
        "math",
        .{ .value = .{ .object = try heap.objects.create(&heap, math_object) } },
    );

    if (config.syntax == .bsx) {
        try environment.put(
            heap.sparse,
            "nerd",
            .{ .value = .{ .object = try heap.objects.create(&heap, math_object) } },
        );
    }

    try environment.put(
        heap.sparse,
        "time",
        .{ .value = .{ .builtin_function = try heap.builtin_functions.create(&heap, &time) } },
    );

    try heap.environment_stack.append(heap.arena, environment);

    return .{
        .config = config,
        .heap = heap,
        .rng = std.rand.DefaultPrng.init(blk: {
            var buffer: [8]u8 = undefined;
            std.os.getrandom(&buffer) catch unreachable;
            break :blk std.mem.bytesAsValue(u64, &buffer).*;
        }),
    };
}

/// Gets a binding from the given environment index.
fn getBinding(vm: *VM, environment_index: u32, binding: []const u8) !Value {
    if (vm.heap.getEnvironmentPtr(environment_index).get(binding)) |entry| {
        return entry.value;
    }

    return if (environment_index != 0)
        vm.getBinding(environment_index - 1, binding)
    else
        try vm.throwException("\"%\" is not defined.", .{binding});
}

/// Assigns a value to an already created binding.
fn putBinding(vm: *VM, environment_index: u32, binding: []const u8, value: Value) !void {
    if (vm.heap.getEnvironmentPtr(environment_index).getPtr(binding)) |value_ptr| {
        if (!value_ptr.is_mutable) {
            try vm.throwException("Cannot assign to immutable binding \"%\".", .{binding});
        }

        value_ptr.value = value;
        return;
    }

    return if (environment_index != 0)
        vm.putBinding(environment_index - 1, binding, value)
    else
        try vm.throwException("\"%\" is not defined.", .{binding});
}

/// Creates a binding in the environment index.
fn createBinding(vm: *VM, environment_index: u32, binding: []const u8, value: Value, is_mutable: bool) !void {
    var status = try vm.heap.getEnvironmentPtr(environment_index).getOrPut(vm.heap.sparse, binding);
    if (status.found_existing) {
        try vm.throwException("\"%\" is already declared.", .{binding});
    }
    status.value_ptr.* = .{ .is_mutable = is_mutable, .value = value };
}

/// Throws an exception with the given message.
pub fn throwException(vm: *VM, message: []const u8, values: anytype) !noreturn {
    @setCold(true);

    var output = try std.ArrayList(u8).initCapacity(vm.heap.sparse, message.len);

    var output_writer = output.writer();

    var start_slice: usize = 0;

    var index: usize = 0;

    const values_info = @typeInfo(@TypeOf(values));

    inline for (values_info.Struct.fields) |entry| {
        while (index < message.len) : (index += 1) {
            const value = @field(values, entry.name);

            if (message[index] == '%') {
                try output.appendSlice(message[start_slice..index]);

                _ = switch (@TypeOf(value)) {
                    Value => vm.writeValue(output_writer, value),
                    []const u8 => output.appendSlice(value),
                    else => std.fmt.format(output_writer, "{}", .{value}),
                } catch
                    return error.OutOfMemory;

                start_slice = index + 1;
            }
        }
    }

    if (start_slice < message.len) {
        try output.appendSlice(message[start_slice..]);
    }

    vm.error_context = try output.toOwnedSlice();
    return error.Exception;
}

const FallibleData = struct {
    catch_index: usize,
    stack_size: u32,
    environment_stack_size: u32,
};

/// Executes the executable.
pub fn execute(vm: *VM, exe: *Executable) Error!void {
    var iter = Executable.BytecodeIterator{ .bytecode = exe.bytecode.items };

    var fallible_stack = std.ArrayList(FallibleData).init(vm.heap.sparse);
    defer fallible_stack.deinit();

    while (iter.next()) |insn| {
        vm.heap.maybeCollectGarbage();

        vm.executeInstruction(exe, &fallible_stack, &iter, insn) catch |e| switch (e) {
            error.Exception => {
                if (fallible_stack.popOrNull()) |data| {
                    iter.index = data.catch_index;
                    vm.heap.stack.shrinkRetainingCapacity(data.stack_size);

                    for (vm.heap.environment_stack.items[data.environment_stack_size..]) |*environment| {
                        environment.deinit(vm.heap.sparse);
                    }

                    vm.heap.environment_stack.shrinkRetainingCapacity(data.environment_stack_size);

                    // Magic error value is just assigned in the current scope.
                    vm.heap.getEnvironmentPtr(vm.heap.currentEnvironmentIndex()).put(vm.heap.sparse, "error", .{
                        .value = .{ .string = try vm.heap.strings.create(&vm.heap, vm.error_context.?) },
                    }) catch {};

                    vm.error_context = null;
                } else {
                    return e;
                }
            },
            else => return e,
        };
    }
}

fn executeInstruction(vm: *VM, exe: *Executable, fallible_stack: *std.ArrayList(FallibleData), iter: *Executable.BytecodeIterator, insn: anytype) !void {
    switch (insn.tag) {
        .put_function => {
            const function_index = insn.args[0];
            const function = &exe.functions.items[function_index];

            var function_exe = try Executable.compile(exe.allocator, function.node.block);
            function_exe.ast_node = function.node;

            var executable_index = try vm.heap.executables.create(&vm.heap, function_exe);

            try vm.createBinding(
                vm.heap.currentEnvironmentIndex(),
                function.node.name,
                .{ .executable = executable_index },
                true,
            );
        },
        .push_fallible => {
            try fallible_stack.append(.{
                .catch_index = insn.args[0],
                .stack_size = @intCast(vm.heap.stack.items.len),
                .environment_stack_size = @intCast(vm.heap.environment_stack.items.len),
            });
        },
        .pop_fallbile => {
            _ = fallible_stack.pop();
            try vm.heap.environment_stack.append(vm.heap.arena, .{});
        },
        .duplicate => {
            try vm.heap.stack.append(vm.heap.arena, vm.heap.stack.getLast());
        },
        .pop => {
            _ = vm.heap.stack.pop();
        },
        .push_null => {
            try vm.heap.stack.append(vm.heap.arena, .null);
        },
        .push_string => {
            const readonly_string_data = exe.strings.items[insn.args[0]];
            const readonly_string_index = try vm.heap.readonly_strings.create(&vm.heap, readonly_string_data);
            try vm.heap.stack.append(vm.heap.arena, .{ .readonly_string = readonly_string_index });
        },
        .push_constant => {
            try vm.heap.stack.append(vm.heap.arena, exe.constants.items[insn.args[0]]);
        },
        .push_binding => {
            const identifier = exe.identifiers.items[insn.args[0]];

            try vm.heap.stack.append(vm.heap.arena, try vm.getBinding(vm.heap.currentEnvironmentIndex(), identifier));
        },
        .put_binding => {
            const identifier = exe.identifiers.items[insn.args[0]];
            const value = vm.heap.stack.getLast();
            try vm.putBinding(vm.heap.currentEnvironmentIndex(), identifier, value);
        },
        .create_mutable_binding => {
            const identifier = exe.identifiers.items[insn.args[0]];
            const value = vm.heap.stack.pop();
            try vm.createBinding(vm.heap.currentEnvironmentIndex(), identifier, value, true);
        },
        .create_binding => {
            const identifier = exe.identifiers.items[insn.args[0]];
            const value = vm.heap.stack.pop();
            try vm.createBinding(vm.heap.currentEnvironmentIndex(), identifier, value, false);
        },
        .@"+" => {
            const right = vm.heap.stack.pop();
            const left = vm.heap.stack.pop();
            vm.heap.stack.appendAssumeCapacity(try Value.@"+"(vm, left, right));
        },
        .@"-" => {
            const right = vm.heap.stack.pop();
            const left = vm.heap.stack.pop();
            vm.heap.stack.appendAssumeCapacity(try Value.@"-"(vm, left, right));
        },
        .@"*" => {
            const right = vm.heap.stack.pop();
            const left = vm.heap.stack.pop();
            vm.heap.stack.appendAssumeCapacity(try Value.@"*"(vm, left, right));
        },
        .@"/" => {
            const right = vm.heap.stack.pop();
            const left = vm.heap.stack.pop();
            vm.heap.stack.appendAssumeCapacity(try Value.@"/"(vm, left, right));
        },
        .@"%" => {
            const right = vm.heap.stack.pop();
            const left = vm.heap.stack.pop();
            vm.heap.stack.appendAssumeCapacity(try Value.@"%"(vm, left, right));
        },
        .@"<" => {
            const right = vm.heap.stack.pop();
            const left = vm.heap.stack.pop();
            vm.heap.stack.appendAssumeCapacity(Value.from(try Value.@"<"(vm, left, right)));
        },
        .@">" => {
            const right = vm.heap.stack.pop();
            const left = vm.heap.stack.pop();
            vm.heap.stack.appendAssumeCapacity(Value.from(try Value.@">"(vm, left, right)));
        },
        .@">=" => {
            const right = vm.heap.stack.pop();
            const left = vm.heap.stack.pop();
            vm.heap.stack.appendAssumeCapacity(Value.from(try Value.@">="(vm, left, right)));
        },
        .@"<=" => {
            const right = vm.heap.stack.pop();
            const left = vm.heap.stack.pop();
            vm.heap.stack.appendAssumeCapacity(Value.from(try Value.@"<="(vm, left, right)));
        },
        .@"==" => {
            const right = vm.heap.stack.pop();
            const left = vm.heap.stack.pop();
            vm.heap.stack.appendAssumeCapacity(Value.from(Value.equalTo(&vm.heap, left, right)));
        },
        .@"!=" => {
            const right = vm.heap.stack.pop();
            const left = vm.heap.stack.pop();
            vm.heap.stack.appendAssumeCapacity(Value.from(!Value.equalTo(&vm.heap, left, right)));
        },
        .@"|" => {
            const right = vm.heap.stack.pop();
            const left = vm.heap.stack.pop();
            vm.heap.stack.appendAssumeCapacity(Value.from(try Value.@"|"(vm, left, right)));
        },
        .@"&&" => {
            const right = vm.heap.stack.pop();
            const left = vm.heap.stack.pop();
            vm.heap.stack.appendAssumeCapacity(Value.from(try Value.@"&&"(vm, left, right)));
        },
        .jump_if_not_true => {
            const condition = vm.heap.stack.pop();
            if (condition != .boolean or !condition.boolean) {
                iter.index = insn.args[0];
            }
        },
        .jump => {
            iter.index = insn.args[0];
        },
        .call => {
            const arguments_len = insn.args[0];

            // The stack will have the following layout: ... argument* callee
            const callee = vm.heap.stack.items[vm.heap.stack.items.len - arguments_len - 1];
            const arguments = vm.heap.stack.items[vm.heap.stack.items.len - arguments_len ..];

            const result = switch (callee) {
                .builtin_function => |function_index| blk: {
                    const ptr = vm.heap.builtin_functions.get(function_index);
                    const function_ptr: *const fn (*VM, Arguments) Error!Value = @ptrCast(ptr);
                    break :blk try function_ptr(vm, .{ .items = arguments });
                },
                .executable => |executable_index| blk: {
                    const executable: Executable = vm.heap.executables.get(executable_index);

                    var parameters = executable.ast_node.?.parameters;

                    if (parameters.len != arguments.len) {
                        return try vm.throwException("Expected % arguments, found %.", .{ parameters.len, arguments.len });
                    }

                    var function_environment = Environment{};
                    try function_environment.ensureTotalCapacity(vm.heap.sparse, @intCast(parameters.len));

                    for (parameters, arguments) |parameter, argument| {
                        function_environment.putAssumeCapacity(parameter, .{
                            .value = argument,
                            .is_mutable = true,
                        });
                    }

                    try vm.heap.environment_stack.append(vm.heap.arena, function_environment);
                    try vm.execute(vm.heap.executables.getPtr(executable_index));

                    var environment = vm.heap.environment_stack.pop();
                    environment.deinit(vm.heap.sparse);

                    break :blk vm.heap.stack.pop();
                },
                else => try vm.throwException("% is not a function.", .{callee}),
            };

            // Pop callee and arguments from the stack.
            vm.heap.stack.items.len -= arguments_len + 1;

            vm.heap.stack.appendAssumeCapacity(result);
        },
        .member => {
            const object = vm.heap.stack.pop();
            const member = exe.identifiers.items[insn.args[0]];

            const result = switch (object) {
                .object => |object_index| blk: {
                    const properties = vm.heap.objects.getPtr(object_index);
                    if (properties.get(member)) |value| {
                        break :blk value;
                    } else {
                        try vm.throwException("Property is not defined.", &.{});
                    }
                },
                else => try vm.throwException("Unable to get property of non-object.", &.{}),
            };

            vm.heap.stack.appendAssumeCapacity(result);
        },
        .create_object => {
            var map = std.StringHashMapUnmanaged(Value){};
            try map.ensureTotalCapacity(vm.heap.sparse, insn.args[0]);
            const object_index = try vm.heap.objects.create(&vm.heap, map);
            try vm.heap.stack.append(vm.heap.arena, .{ .object = object_index });
        },
        .put_property => {
            const value = vm.heap.stack.pop();
            const maybe_object = vm.heap.stack.getLast();
            const property = exe.identifiers.items[insn.args[0]];

            switch (maybe_object) {
                .object => |object_index| {
                    const object = vm.heap.objects.getPtr(object_index);
                    try object.put(vm.heap.sparse, property, value);
                },
                else => try vm.throwException("Unable to set property of non-object.", &.{}),
            }
        },
        .put_property_in_expression => {
            const maybe_object = vm.heap.stack.pop();
            const value = vm.heap.stack.getLast();
            const property = exe.identifiers.items[insn.args[0]];

            switch (maybe_object) {
                .object => |object_index| {
                    const object = vm.heap.objects.getPtr(object_index);
                    try object.put(vm.heap.sparse, property, value);
                },
                else => try vm.throwException("Unable to set property of non-object.", &.{}),
            }
        },
        .push_environment => {
            try vm.heap.environment_stack.append(vm.heap.arena, .{});
        },
        .pop_environment => {
            var environment = vm.heap.environment_stack.pop();
            environment.deinit(vm.heap.sparse);
        },
        .reset_environment => {
            var environment = vm.heap.getEnvironmentPtr(vm.heap.currentEnvironmentIndex());
            environment.clearRetainingCapacity();
        },
        .push_number_i32 => {
            var number_i32: i32 = @bitCast(insn.args[0]);
            try vm.heap.stack.append(vm.heap.arena, .{ .number_i32 = number_i32 });
        },
        .push_number_f32 => {
            var float: f32 = @bitCast(insn.args[0]);
            const value = .{ .number_f64 = try vm.heap.numbers.create(&vm.heap, @floatCast(float)) };
            try vm.heap.stack.append(vm.heap.arena, value);
        },
        .push_number_f64 => {
            var number_f64 = std.mem.bytesToValue(f64, std.mem.asBytes(insn.args[0..2]));
            const value = .{ .number_f64 = try vm.heap.numbers.create(&vm.heap, number_f64) };
            try vm.heap.stack.append(vm.heap.arena, value);
        },
    }
}
