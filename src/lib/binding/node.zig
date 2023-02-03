const std = @import("std");
const zigpkg = @import("../zigpkg.zig");

const c = @cImport({
    @cDefine("NAPI_VERSION", "8");
    @cInclude("node_api.h");
});

export fn napi_register_module_v1(env: c.napi_env, exports: c.napi_value) c.napi_value {
    registerFunction(env, exports, "add", add) catch return null;
    registerOptions(env, exports, "options") catch return null;
    return exports;
}

fn add(env: c.napi_env, info: c.napi_callback_info) callconv(.C) c.napi_value {
    var argc: usize = 1;
    var argv: [1]c.napi_value = undefined;
    if (c.napi_get_cb_info(env, info, &argc, &argv, null, null) != c.napi_ok) {
        throw(env, "Failed to get args") catch return null;
    }
    if (argc != 1) throw(env, "add requires exactly 1 argument") catch return null;
    const n = Read.uint8(env, argv[0], "n") catch return null;
    return Write.uint8(env, zigpkg.add(n), "result") catch return null;
}

fn registerFunction(
    env: c.napi_env,
    exports: c.napi_value,
    comptime name: [:0]const u8,
    function: *const fn (env: c.napi_env, info: c.napi_callback_info) callconv(.C) c.napi_value,
) !void {
    var napi_function: c.napi_value = undefined;
    if (c.napi_create_function(env, null, 0, function, null, &napi_function) != c.napi_ok) {
        return throw(env, "Failed to create function " ++ name ++ "().");
    }
    if (c.napi_set_named_property(env, exports, name, napi_function) != c.napi_ok) {
        return throw(env, "Failed to add " ++ name ++ "() to exports.");
    }
}

fn registerOptions(env: c.napi_env, exports: c.napi_value, comptime name: [:0]const u8) !void {
    var object = try Write.object(env, name);

    // inline for (@typeInfo(zigpkg.Options).Struct.fields) |field| {
    //     const value = Write.boolean(env, @field(zigpkg.options, field.name), field.name);
    //     if (c.napi_set_named_property(env, object, field.name, value) != c.napi_ok) {
    //       return throw(env, "Failed to set property '" ++ field.name ++ "' of " ++ name);
    //   }
    // }

    if (c.napi_set_named_property(env, exports, name, object) != c.napi_ok) {
        return throw(env, "Failed to add " ++ name ++ " to exports.");
    }
}

const TranslationError = error{ExceptionThrown};

fn throw(env: c.napi_env, comptime message: [:0]const u8) TranslationError {
    var result = c.napi_throw_error(env, null, message);
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
            c.napi_number_expected => return throw(env, name ++ " must be a number"),
            else => unreachable,
        }
        return result;
    }

    fn boolean(env: c.napi_env, value: c.napi_value, comptime name: [:0]const u8) !bool {
        var result: u32 = undefined;
        switch (c.napi_get_value_bool(env, value, &result)) {
            c.napi_ok => {},
            c.napi_boolean_expected => return throw(env, name ++ " must be a boolean"),
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
            return throw(env, "Failed to create number " ++ name);
        }
        return result;
    }

    fn boolean(env: c.napi_env, value: bool, comptime name: [:0]const u8) !c.napi_value {
        var result: c.napi_value = undefined;
        if (c.napi_get_boolean(env, value, &result) != c.napi_ok) {
            return throw(env, "Failed to create boolean " ++ name);
        }
        return result;
    }

    fn object(env: c.napi_env, comptime name: [:0]const u8) !c.napi_value {
        var result: c.napi_value = undefined;
        if (c.napi_create_object(env, &result) != c.napi_ok) {
            return throw(env, "Failed to create object " ++ name);
        }
        return result;
    }
};
