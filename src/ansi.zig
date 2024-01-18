const std = @import("std");
const Allocator = std.mem.Allocator;
const comp = std.fmt.comptimePrint;

const PREFIX = "\x1b[";

pub const RESET = "\x1b[0m";

pub const ClearLine = "\x1b[2K";
pub const EraseToEOL = "\x1b[K";

// pub const Style = struct {
//     pub const Underline = "\x1b[4m";
//     pub const RemoveUnderline = "\x1b[24m";

//     pub const Bold = "\x1b[1m";
//     pub const RemoveBold = "\x1b[22m";

//     pub fn underline(comptime text: []const u8) []const u8 {
//         return Underline ++ text ++ Reset;
//     }

//     pub fn bold(comptime text: []const u8) []const u8 {
//         return Bold ++ text ++ Reset;
//     }
// };

pub const Style = enum(u8) {
    Normal = 0,
    Bold = 1,
    Dim = 2,
    Italic = 3,
    Underline = 4,
};

pub const Fg = struct {
    const template = "{s}{d};{s}m{s}{s}";
    const RGB_TEMPLATE = "\x1b[38;2;{d};{d};{d}m";

    const BLACK_CODE = "30";
    const RED_CODE = "31";
    const GREEN_CODE = "32";
    const YELLOW_CODE = "33";
    const BLUE_CODE = "34";
    const MAGENTA_CODE = "35";
    const CYAN_CODE = "36";
    const WHITE_CODE = "37";

    const HIGH_BLACK_CODE = "90";
    const HIGH_RED_CODE = "91";
    const HIGH_GREEN_CODE = "92";
    const HIGH_YELLOW_CODE = "93";
    const HIGH_BLUE_CODE = "94";
    const HIGH_MAGENTA_CODE = "95";
    const HIGH_CYAN_CODE = "96";
    const HIGH_WHITE_CODE = "97";

    /// Colorize text with color code and reset at the end
    pub fn colorize(text: []const u8, color: []const u8, style: ?Style) []const u8 {
        if (style) |s| {
            return comp(template, .{ PREFIX, @intFromEnum(s), color, text, RESET });
        }
        return comp(template, .{ PREFIX, @intFromEnum(Style.Normal), color, text, RESET });
    }

    pub fn black(comptime text: []const u8, style: ?Style) []const u8 {
        return colorize(text, BLACK_CODE, style);
    }

    pub fn red(comptime text: []const u8, style: ?Style) []const u8 {
        return colorize(text, RED_CODE, style);
    }

    pub fn green(comptime text: []const u8, style: ?Style) []const u8 {
        return colorize(text, GREEN_CODE, style);
    }

    pub fn yellow(comptime text: []const u8, style: ?Style) []const u8 {
        return colorize(text, YELLOW_CODE, style);
    }

    pub fn blue(comptime text: []const u8, style: ?Style) []const u8 {
        return colorize(text, BLUE_CODE, style);
    }

    pub fn magenta(comptime text: []const u8, style: ?Style) []const u8 {
        return colorize(text, MAGENTA_CODE, style);
    }

    pub fn cyan(comptime text: []const u8, style: ?Style) []const u8 {
        return colorize(text, CYAN_CODE, style);
    }

    pub fn white(comptime text: []const u8, style: ?Style) []const u8 {
        return colorize(text, WHITE_CODE, style);
    }

    pub fn high_black(comptime text: []const u8, style: ?Style) []const u8 {
        return colorize(text, HIGH_BLACK_CODE, style);
    }

    pub fn high_red(comptime text: []const u8, style: ?Style) []const u8 {
        return colorize(text, HIGH_RED_CODE, style);
    }

    pub fn high_green(comptime text: []const u8, style: ?Style) []const u8 {
        return colorize(text, HIGH_GREEN_CODE, style);
    }

    pub fn high_yellow(comptime text: []const u8, style: ?Style) []const u8 {
        return colorize(text, HIGH_YELLOW_CODE, style);
    }

    pub fn high_blue(comptime text: []const u8, style: ?Style) []const u8 {
        return colorize(text, HIGH_BLUE_CODE, style);
    }

    pub fn high_magenta(comptime text: []const u8, style: ?Style) []const u8 {
        return colorize(text, HIGH_MAGENTA_CODE, style);
    }

    pub fn high_cyan(comptime text: []const u8, style: ?Style) []const u8 {
        return colorize(text, HIGH_CYAN_CODE, style);
    }

    pub fn rgb(comptime text: []const u8, r: u8, g: u8, b: u8) []const u8 {
        return formatRgb(r, g, b) ++ text ++ RESET;
    }

    /// # Example
    /// ```zig
    /// const stdout = std.io.getStdOut().writer();
    ///
    /// // Prefer comptime rather than runtime
    /// stdout.print(ansi.Fg.formatRgb(120, 120, 120) ++ "Hello, World!", .{}) catch {};
    /// stdout.print(ansi.Fg.rgb("Hello, World!", 120, 120, 120), .{}) catch {};
    /// stdout.print(std.fmt.comptimePrint("{s}Hello, World!", .{ansi.Fg.formatRgb(120, 120, 120)}), .{}) catch {};
    /// ```
    pub fn formatRgb(r: u8, g: u8, b: u8) []const u8 {
        return comp("\x1b[38;2;{d};{d};{d}m", .{ r, g, b });
    }
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
        return color ++ text ++ RESET;
    }
};
