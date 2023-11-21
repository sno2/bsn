//! The heap for Bussin values.

const std = @import("std");

const Executable = @import("Executable.zig");
const Value = @import("value.zig").Value;
const VM = @import("VM.zig");

const Heap = @This();

pub const Environment = std.StringHashMapUnmanaged(struct {
    value: Value,
    is_mutable: bool = false,
});

pub const BuiltinFunctionHeap = HeapComponent(*const anyopaque, null);
pub const ExecutableHeap = HeapComponent(Executable, struct {
    fn free(heap: *Heap, index: usize) void {
        heap.executables.items.items(.value)[index].deinit();
    }
}.free);
pub const NumberHeap = HeapComponent(f64, null);
pub const ReadonlyStringHeap = HeapComponent([]const u8, null);
pub const StringHeap = HeapComponent([]u8, struct {
    fn free(heap: *Heap, index: usize) void {
        heap.sparse.free(heap.strings.items.items(.value)[index]);
    }
}.free);
pub const ObjectHeap = HeapComponent(std.StringHashMapUnmanaged(Value), struct {
    fn free(heap: *Heap, index: usize) void {
        heap.objects.items.items(.value)[index].deinit(heap.sparse);
    }
}.free);

/// The sparse allocator for data.
sparse: std.mem.Allocator,

/// The arena allocator.
arena: std.mem.Allocator,

/// A hacky method for fast determination of whether or not to garbage collect.
should_garbage_collect: bool = false,

/// The current executable's stack.
stack: std.ArrayListUnmanaged(Value) = .{},
environment_stack: std.ArrayListUnmanaged(Environment) = .{},

// Homogenous heaps
builtin_functions: BuiltinFunctionHeap = .{},
executables: ExecutableHeap = .{},
readonly_strings: ReadonlyStringHeap = .{},
strings: StringHeap = .{},
numbers: NumberHeap = .{},
objects: ObjectHeap = .{},

const Flags = struct {
    marked: bool = false,
};

fn HeapComponent(comptime T: type, comptime free_function: ?*const fn (*Heap, index: usize) void) type {
    return struct {
        const Self = @This();

        pub const Index = u32;

        pub const Item = T;

        items: std.MultiArrayList(struct {
            value: T,
            flags: ?Flags = null,
        }) = .{},

        pub fn create(self: *Self, heap: *Heap, value: T) !Index {
            if (self.items.len == self.items.capacity and self.items.len > 1024) {
                heap.should_garbage_collect = true;
            }

            try self.items.append(heap.arena, .{ .value = value, .flags = .{} });
            return @intCast(self.items.len - 1);
        }

        pub inline fn get(self: *Self, index: Index) T {
            return self.items.items(.value)[index];
        }

        pub inline fn getPtr(self: *Self, index: Index) *T {
            return &self.items.items(.value)[index];
        }

        pub inline fn free(_: *const Self, heap: *Heap, index: Index) void {
            if (free_function) |function| {
                function(heap, index);
            }
        }
    };
}

fn mark(heap: *Heap, value: *const Value) void {
    switch (value.*) {
        .object => |object_index| {
            const object_slices = heap.objects.items.slice();

            object_slices.items(.flags)[object_index].?.marked = true;

            const object = object_slices.items(.value)[object_index];

            var value_iter = object.valueIterator();
            while (value_iter.next()) |item| {
                heap.mark(item);
            }
        },
        .number_f64 => |number_index| {
            heap.numbers.items.items(.flags)[number_index].?.marked = true;
        },
        .builtin_function => |builtin_function_index| {
            heap.builtin_functions.items.items(.flags)[builtin_function_index].?.marked = true;
        },
        .readonly_string => |readonly_string_index| {
            heap.readonly_strings.items.items(.flags)[readonly_string_index].?.marked = true;
        },
        .string => |string_index| {
            heap.strings.items.items(.flags)[string_index].?.marked = true;
        },
        .executable => |executable_index| {
            heap.executables.items.items(.flags)[executable_index].?.marked = true;
        },
        else => {},
    }
}

fn markStackValues(heap: *Heap) void {
    // Mark all stack values.
    for (heap.stack.items) |*value| {
        heap.mark(value);
    }

    // Mark all environment values.
    for (heap.environment_stack.items) |environment| {
        var value_iter = environment.valueIterator();
        while (value_iter.next()) |value| {
            heap.mark(&value.value);
        }
    }
}

fn sweep(heap: *Heap) void {
    // Sweep all heap components.
    inline for (.{
        heap.builtin_functions,
        heap.executables,
        heap.numbers,
        heap.readonly_strings,
        heap.strings,
        heap.objects,
    }) |component| {
        for (component.items.items(.flags), 0..) |*maybe_flags, index| {
            if (maybe_flags.*) |*flags| {
                if (!flags.marked) {
                    component.free(heap, @intCast(index));
                    maybe_flags.* = null;
                } else {
                    flags.marked = false;
                }
            }
        }
    }
}

pub inline fn maybeCollectGarbage(heap: *Heap) void {
    if (!heap.should_garbage_collect) {
        return;
    }

    heap.should_garbage_collect = false;

    heap.markStackValues();
    heap.sweep();
}

pub fn deinit(heap: *Heap) void {
    heap.stack.deinit(heap.arena);

    for (heap.environment_stack.items) |*entry| {
        entry.deinit(heap.sparse);
    }

    heap.environment_stack.deinit(heap.arena);

    heap.sweep();

    heap.builtin_functions.items.deinit(heap.arena);
    heap.executables.items.deinit(heap.arena);
    heap.readonly_strings.items.deinit(heap.arena);
    heap.strings.items.deinit(heap.arena);
    heap.numbers.items.deinit(heap.arena);
    heap.objects.items.deinit(heap.arena);
}

pub fn currentEnvironmentIndex(heap: *Heap) u32 {
    return @intCast(heap.environment_stack.items.len - 1);
}

pub fn getEnvironmentPtr(heap: *Heap, environment_index: u32) *Environment {
    return &heap.environment_stack.items[environment_index];
}
