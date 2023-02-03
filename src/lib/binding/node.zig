const std = @import("std");
const zigpkg = @import("../zigpkg.zig");

const c = @cImport({
    @cDefine("NAPI_VERSION", "8");
    @cInclude("node_api.h");
});

export fn napi_register_module_v1(env: c.napi_env, exports: c.napi_value) c.napi_value {
    const opts = options(env, "options") catch return null;
    const properties = [_]c.napi_property_descriptor{
        prop("add", .{ .Method = add }),
        prop("options", .{ .Value = opts }),
    };
    if (c.napi_define_properties(env, exports, properties.len, &properties) != c.napi_ok) {
        throw(.Error, env, "Failed to set exports") catch return null;
    }
    return exports;
}

fn add(env: c.napi_env, info: c.napi_callback_info) callconv(.C) c.napi_value {
    var argc: usize = 1;
    var argv: [1]c.napi_value = undefined;
    if (c.napi_get_cb_info(env, info, &argc, &argv, null, null) != c.napi_ok) {
        throw(.Error, env, "Failed to get args") catch return null;
    }
    if (argc != 1) throw(.TypeError, env, "add requires exactly 1 argument") catch return null;
    const n = Read.uint8(env, argv[0], "n") catch return null;
    return Write.uint8(env, zigpkg.add(n), "result") catch return null;
}

fn options(env: c.napi_env, comptime name: [:0]const u8) !c.napi_value {
    var object = try Write.object(env, name);
    const properties = [_]c.napi_property_descriptor{
        prop("foo", .{ .Value = try Write.boolean(env, zigpkg.options.foo, "foo") }),
        prop("bar", .{ .Value = try Write.boolean(env, zigpkg.options.bar, "bar") }),
        prop("baz", .{ .Value = try Write.boolean(env, zigpkg.options.baz, "baz") }),
        prop("qux", .{ .Value = try Write.boolean(env, zigpkg.options.qux, "qux") }),
    };
    if (c.napi_define_properties(env, object, properties.len, &properties) != c.napi_ok) {
        return throw(.Error, env, "Failed to set fields of " ++ name);
    }
    return object;
}

const Property = union(enum) {
    Method: c.napi_callback,
    Value: c.napi_value,
};

fn prop(comptime name: [:0]const u8, property: Property) c.napi_property_descriptor {
    return .{
        .utf8name = name,
        .name = null,
        .method = switch (property) {
            .Method => |m| m,
            else => null,
        },
        .getter = null,
        .setter = null,
        .value = switch (property) {
            .Value => |v| v,
            else => null,
        },
        .attributes = c.napi_default,
        .data = null,
    };
}

const Kind = enum { Error, TypeError };
const TranslationError = error{ExceptionThrown};

fn throw(comptime kind: Kind, env: c.napi_env, comptime message: [:0]const u8) TranslationError {
    var result = switch (kind) {
        .Error => c.napi_throw_error(env, null, message),
        .TypeError => c.napi_throw_type_error(env, null, message),
    };
    switch (result) {
        c.napi_ok, c.napi_pending_exception => {},
        else => unreachable,
    }
    return TranslationError.ExceptionThrown;
}

const Read = struct {
    fn uint8(env: c.napi_env, value: c.napi_value, comptime name: [:0]const u8) !u8 {
        return @truncate(u8, try uint32(env, value, name));
    }

    fn uint32(env: c.napi_env, value: c.napi_value, comptime name: [:0]const u8) !u32 {
        var result: u32 = undefined;
        switch (c.napi_get_value_uint32(env, value, &result)) {
            c.napi_ok => {},
            c.napi_number_expected => return throw(.Error, env, name ++ " must be a number"),
            else => unreachable,
        }
        return result;
    }

    fn boolean(env: c.napi_env, value: c.napi_value, comptime name: [:0]const u8) !bool {
        var result: u32 = undefined;
        switch (c.napi_get_value_bool(env, value, &result)) {
            c.napi_ok => {},
            c.napi_boolean_expected => return throw(.Error, env, name ++ " must be a boolean"),
            else => unreachable,
        }
        return result;
    }
};

const Write = struct {
    fn uint8(env: c.napi_env, value: u8, comptime name: [:0]const u8) !c.napi_value {
        return uint32(env, @as(u32, value), name);
    }

    fn uint32(env: c.napi_env, value: u32, comptime name: [:0]const u8) !c.napi_value {
        var result: c.napi_value = undefined;
        if (c.napi_create_uint32(env, value, &result) != c.napi_ok) {
            return throw(.Error, env, "Failed to create number " ++ name);
        }
        return result;
    }

    fn boolean(env: c.napi_env, value: bool, comptime name: [:0]const u8) !c.napi_value {
        var result: c.napi_value = undefined;
        if (c.napi_get_boolean(env, value, &result) != c.napi_ok) {
            return throw(.Error, env, "Failed to create boolean " ++ name);
        }
        return result;
    }

    fn object(env: c.napi_env, comptime name: [:0]const u8) !c.napi_value {
        var result: c.napi_value = undefined;
        if (c.napi_create_object(env, &result) != c.napi_ok) {
            return throw(.Error, env, "Failed to create object " ++ name);
        }
        return result;
    }
};
