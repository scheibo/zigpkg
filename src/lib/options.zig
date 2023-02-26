const build_options = @import("zigpkg_options");
const root = @import("root");

pub const Options = struct {
    add: ?bool = null,
    subtract: ?bool = null,
    multiply: ?bool = null,
    divide: ?bool = null,
};

pub const add = get("add", false);
pub const subtract = get("subtract", false);
pub const multiply = get("multiply", false);
pub const divide = get("divide", false);

fn get(comptime name: []const u8, default: bool) bool {
    var build_enable: ?bool = null;
    var root_enable: ?bool = null;

    if (@hasDecl(root, "zigpkg_options")) {
        root_enable = @field(@as(Options, root.zigpkg_options), name);
    }
    if (@hasDecl(build_options, name)) {
        build_enable = @as(?bool, @field(build_options, name));
    }
    if (build_enable != null and root_enable != null) {
        if (build_enable.? != root_enable.?) {
            const r = name ++ " (" ++ (if (root_enable.?) "false" else "true") ++ ")";
            const b = name ++ " (" ++ (if (build_enable.?) "false" else "true") ++ ")";
            @compileError("root decl zigpkg_options." ++ r ++ " != build option " ++ b ++ ".");
        }
    }

    return root_enable orelse (build_enable orelse default);
}
