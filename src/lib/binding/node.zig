const std = @import("std");
const zigpkg = @import("../zigpkg.zig");

const c = @cImport({
    @cDefine("NAPI_VERSION", "8");
    @cInclude("node_api.h");
});

export fn napi_register_module_v1(env: c.napi_env, exports: c.napi_value) c.napi_value {
    const opts = options(env, "options") catch return null;
    const properties = [_]c.napi_property_descriptor{
        Property.init("compute", .{ .method = compute }),
        Property.init("options", .{ .value = opts }),
    };
    if (c.napi_define_properties(env, exports, properties.len, &properties) != c.napi_ok) {
        Error.throw(env, "Failed to set exports") catch return null;
    }
    return exports;
}

fn compute(env: c.napi_env, info: c.napi_callback_info) callconv(.C) c.napi_value {
    var argc: usize = 1;
    var argv: [1]c.napi_value = undefined;
    if (c.napi_get_cb_info(env, info, &argc, &argv, null, null) != c.napi_ok) {
        Error.throw(env, "Failed to get args") catch return null;
    }
    if (argc != 1) TypeError.throw(env, "compute requires exactly 1 argument") catch return null;
    const n = Number.get(env, argv[0], "n", u32) catch return null;
    const result = zigpkg.compute(n) catch |err| switch (err) {
        error.Overflow => return Error.throw(env, "Result overflow") catch return null,
    };
    return Number.init(env, result, "result") catch return null;
}

fn options(env: c.napi_env, comptime name: [:0]const u8) !c.napi_value {
    var object = try Object.init(env, name);
    const properties = [_]c.napi_property_descriptor{
        Property.init("add", .{
            .value = try Boolean.init(env, zigpkg.options.add, "add"),
        }),
        Property.init("subtract", .{
            .value = try Boolean.init(env, zigpkg.options.subtract, "subtract"),
        }),
    };
    if (c.napi_define_properties(env, object, properties.len, &properties) != c.napi_ok) {
        return Error.throw(env, "Failed to set fields of " ++ name);
    }
    return object;
}

const Property = union(enum) {
    method: c.napi_callback,
    value: c.napi_value,

    fn init(comptime name: [:0]const u8, property: Property) c.napi_property_descriptor {
        return .{
            .utf8name = name,
            .name = null,
            .method = switch (property) {
                .method => |m| m,
                .value => null,
            },
            .getter = null,
            .setter = null,
            .value = switch (property) {
                .method => null,
                .value => |v| v,
            },
            .attributes = switch (property) {
                .method => c.napi_default,
                .value => c.napi_enumerable,
            },
            .data = null,
        };
    }
};

const Error = struct {
    fn throw(env: c.napi_env, comptime message: [:0]const u8) error{Exception} {
        return switch (c.napi_throw_error(env, null, message)) {
            c.napi_ok, c.napi_pending_exception => error.Exception,
            else => unreachable,
        };
    }
};

const TypeError = struct {
    fn throw(env: c.napi_env, comptime message: [:0]const u8) error{Exception} {
        return switch (c.napi_throw_type_error(env, null, message)) {
            c.napi_ok, c.napi_pending_exception => error.Exception,
            else => unreachable,
        };
    }
};

const Number = struct {
    fn init(env: c.napi_env, value: anytype, comptime name: [:0]const u8) !c.napi_value {
        const T = @TypeOf(value);
        var result: c.napi_value = undefined;

        switch (@typeInfo(T)) {
            .Int => |info| switch (info.bits) {
                0...32 => switch (info.signedness) {
                    .signed => {
                        if (c.napi_create_int32(env, @as(i32, value), &result) != c.napi_ok) {
                            return Error.throw(env, "Failed to create int32 " ++ name);
                        }
                    },
                    .unsigned => {
                        if (c.napi_create_uint32(env, @as(u32, value), &result) != c.napi_ok) {
                            return Error.throw(env, "Failed to create int32 " ++ name);
                        }
                    },
                },
                33...52 => {
                    if (c.napi_create_int64(env, @as(i64, value), &result) != c.napi_ok) {
                        return Error.throw(env, "Failed to create int64 " ++ name);
                    }
                },
                else => @compileError("int can't be represented as JS number"),
            },
            .ComptimeInt => {
                if (value >= std.math.minInt(i32) and value <= std.math.maxInt(i32)) {
                    if (c.napi_create_int32(env, @as(i32, value), &result) != c.napi_ok) {
                        return Error.throw(env, "Failed to create int32 " ++ name);
                    }
                } else if (value >= std.math.minInt(i52) and value <= std.math.maxInt(i52)) {
                    if (c.napi_create_int64(env, @as(i64, value), &result) != c.napi_ok) {
                        return Error.throw(env, "Failed to create int64 " ++ name);
                    }
                } else {
                    @compileError("comptime_int can't be represented as JS number");
                }
            },
            .Float, .ComptimeFloat => {
                if (c.napi_create_double(env, @floatCast(value), &result) != c.napi_ok) {
                    return Error.throw(env, "Failed to create double " ++ name);
                }
            },
            else => @compileError("expected number, got: " ++ @typeName(T)),
        }

        return result;
    }

    fn get(env: c.napi_env, value: c.napi_value, comptime name: [:0]const u8, comptime T: type) !T {
        switch (@typeInfo(T)) {
            .Float => {
                var result: f64 = undefined;
                return switch (c.napi_get_value_double(env, value, &result)) {
                    c.napi_ok => @floatCast(result),
                    c.napi_number_expected => Error.throw(env, name ++ " must be a number"),
                    else => unreachable,
                };
            },
            .Int => |info| switch (info.bits) {
                0...32 => switch (info.signedness) {
                    .signed => {
                        var result: i32 = undefined;
                        return switch (c.napi_get_value_int32(env, value, &result)) {
                            c.napi_ok => if (info.bits == 32) result else @intCast(result),
                            c.napi_number_expected => Error.throw(env, name ++ " must be a number"),
                            else => unreachable,
                        };
                    },
                    .unsigned => {
                        var result: u32 = undefined;
                        return switch (c.napi_get_value_uint32(env, value, &result)) {
                            c.napi_ok => if (info.bits == 32) result else @intCast(result),
                            c.napi_number_expected => Error.throw(env, name ++ " must be a number"),
                            else => unreachable,
                        };
                    },
                },
                33...63 => {
                    var result: i64 = undefined;
                    return switch (c.napi_get_value_int64(env, value, &result)) {
                        c.napi_ok => @intCast(result),
                        c.napi_number_expected => Error.throw(env, name ++ " must be a number"),
                        else => unreachable,
                    };
                },
                else => {
                    var result: i64 = undefined;
                    return switch (c.napi_get_value_int64(env, value, &result)) {
                        c.napi_ok => switch (info.signedness) {
                            .signed => return value,
                            .unsigned => return if (0 <= value)
                                @intCast(value)
                            else
                                error.Overflow,
                        },
                        c.napi_number_expected => Error.throw(env, name ++ " must be a number"),
                        else => unreachable,
                    };
                },
            },
            else => @compileError("expected number, got: " ++ @typeName(T)),
        }
    }
};

const Object = struct {
    fn init(env: c.napi_env, comptime name: [:0]const u8) !c.napi_value {
        var result: c.napi_value = undefined;
        if (c.napi_create_object(env, &result) != c.napi_ok) {
            return Error.throw(env, "Failed to create object " ++ name);
        }
        return result;
    }
};

const Boolean = struct {
    fn init(env: c.napi_env, value: bool, comptime name: [:0]const u8) !c.napi_value {
        var result: c.napi_value = undefined;
        if (c.napi_get_boolean(env, value, &result) != c.napi_ok) {
            return Error.throw(env, "Failed to create boolean " ++ name);
        }
        return result;
    }

    fn get(env: c.napi_env, value: c.napi_value, comptime name: [:0]const u8) !bool {
        var result: u32 = undefined;
        return switch (c.napi_get_value_bool(env, value, &result)) {
            c.napi_ok => result,
            c.napi_boolean_expected => Error.throw(env, name ++ " must be a boolean"),
            else => unreachable,
        };
    }
};
