const build_options = @import("build_options");
const root = @import("root");

pub const Options = extern struct {
    foo: bool = false,
    bar: bool = false,
    baz: bool = true,
    qux: bool = true,
};

pub const foo = get("foo", false);
pub const bar = get("bar", false);
pub const baz = get("baz", true);
pub const qux = get("qux", true);

fn get(comptime name: []const u8, default: bool) bool {
    var build_enable: ?bool = null;
    var root_enable: ?bool = null;

    if (@hasDecl(root, "zigpkg_options")) {
        root_enable = @field(@as(Options, root.zigpkg_options), name);
    }
    if (@hasDecl(build_options, name)) {
        build_enable = @as(bool, @field(build_options, name));
    }
    if (build_enable != null and root_enable != null) {
        if (build_enable.? != root_enable.?) {
            const r = name ++ " (" ++ (if (root_enable.?) "false" else "true") ++ ")";
            const b = name ++ " (" ++ (if (build_enable.?) "false" else "true") ++ ")";
            @compileError("root.zigpkg_options." ++ r ++ " != build_options." ++ b ++ ".");
        }
    }

    return root_enable orelse (build_enable orelse default);
}
