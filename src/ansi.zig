const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Reset = "\x1b[0m";

pub const ClearLine = "\x1b[2K";
pub const EraseToEOL = "\x1b[K";

pub const Style = struct {
    pub const Underline = "\x1b[4m";
    pub const RemoveUnderline = "\x1b[24m";

    pub const Bold = "\x1b[1m";
    pub const RemoveBold = "\x1b[22m";

    pub fn underline(comptime text: []const u8) []const u8 {
        return Underline ++ text ++ Reset;
    }

    pub fn bold(comptime text: []const u8) []const u8 {
        return Bold ++ text ++ Reset;
    }
};

pub const Fg = struct {
    const template = "{s}{s}{s}";
    pub const RgbPrefixTemplate = "\x1b[38;2;{d};{d};{d}m";

    pub const Black = "\x1b[30m";
    pub const Red = "\x1b[31m";
    pub const Green = "\x1b[32m";
    pub const Yellow = "\x1b[33m";
    pub const Blue = "\x1b[34m";
    pub const Magenta = "\x1b[35m";
    pub const Cyan = "\x1b[36m";
    pub const White = "\x1b[37m";

    /// Colorize text with color code and reset at the end
    pub fn colorize(text: []const u8, color: []const u8) []const u8 {
        return color ++ text ++ Reset;
    }

    pub fn black(comptime text: []const u8) []const u8 {
        return Black ++ text ++ Reset;
    }

    pub fn red(comptime text: []const u8) []const u8 {
        return Red ++ text ++ Reset;
    }

    pub fn green(comptime text: []const u8) []const u8 {
        return Green ++ text ++ Reset;
    }

    pub fn yellow(comptime text: []const u8) []const u8 {
        return Yellow ++ text ++ Reset;
    }

    pub fn blue(comptime text: []const u8) []const u8 {
        return Blue ++ text ++ Reset;
    }

    pub fn magenta(comptime text: []const u8) []const u8 {
        return Magenta ++ text ++ Reset;
    }

    pub fn cyan(comptime text: []const u8) []const u8 {
        return Cyan ++ text ++ Reset;
    }

    pub fn rgb(comptime text: []const u8, r: u8, g: u8, b: u8) []const u8 {
        return formatRgb(r, g, b) ++ text ++ Reset;
    }

    /// # Example
    /// ```zig
    /// const stdout = std.io.getStdOut().writer();
    ///
    /// stdout.print(ansi.Fg.formatRgb(120, 120, 120) ++ "Hello, World!", .{}) catch {};
    /// stdout.print(ansi.Fg.rgb("Hello, World!", 120, 120, 120), .{}) catch {};
    /// stdout.print(std.fmt.comptimePrint("{s}Hello, World!", .{ansi.Fg.rgb("", 120, 120, 120)}), .{}) catch {};
    /// ```
    pub fn formatRgb(r: u8, g: u8, b: u8) []const u8 {
        return std.fmt.comptimePrint("\x1b[38;2;{d};{d};{d}m", .{ r, g, b });
    }

    // pub fn allocBlack(allocator: Allocator, text: []const u8) ![]const u8 {
    //     return try std.fmt.allocPrint(allocator, template, .{ Black, text, Reset });
    // }

    // pub fn allocRed(allocator: Allocator, text: []const u8) ![]const u8 {
    //     return try std.fmt.allocPrint(allocator, template, .{ Red, text, Reset });
    // }

    // pub fn allocGreen(allocator: Allocator, text: []const u8) ![]const u8 {
    //     return try std.fmt.allocPrint(allocator, template, .{ Green, text, Reset });
    // }

    // pub fn allocYellow(allocator: Allocator, text: []const u8) ![]const u8 {
    //     return try std.fmt.allocPrint(allocator, template, .{ Yellow, text, Reset });
    // }

    // pub fn allocBlue(allocator: Allocator, text: []const u8) ![]const u8 {
    //     return try std.fmt.allocPrint(allocator, template, .{ Blue, text, Reset });
    // }

    // pub fn allocMagenta(allocator: Allocator, text: []const u8) ![]const u8 {
    //     return try std.fmt.allocPrint(allocator, template, .{ Magenta, text, Reset });
    // }

    // pub fn allocCyan(allocator: Allocator, text: []const u8) ![]const u8 {
    //     return try std.fmt.allocPrint(allocator, template, .{ Cyan, text, Reset });
    // }

    // /// # Example
    // ///
    // ///
    // /// ```zig
    // /// const red = allocRgb(allocator, "yay this text is red", .{ 255, 0, 0 });
    // /// ```
    // ///
    // pub fn allocRgb(allocator: Allocator, text: []const u8, color: anytype) ![]const u8 {
    //     return try std.fmt.allocPrint(allocator, "\x1b[38;2;{d};{d};{d}m{s}{s}", .{ color, text, Reset });
    // }
};

pub const Bg = struct {
    pub const Black = "\x1b[40m";
    pub const Red = "\x1b[41m";
    pub const Green = "\x1b[42m";
    pub const Yellow = "\x1b[43m";
    pub const Blue = "\x1b[44m";
    pub const Magenta = "\x1b[45m";
    pub const Cyan = "\x1b[46m";
    pub const White = "\x1b[47m";

    /// Colorize background with color code and reset at the end
    pub fn colorize(text: []const u8, color: []const u8) []const u8 {
        return color ++ text ++ Reset;
    }
};
