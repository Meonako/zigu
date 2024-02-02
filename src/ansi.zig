const std = @import("std");
const Allocator = std.mem.Allocator;
const comp = std.fmt.comptimePrint;

const PREFIX = "\x1b[";

pub const RESET = "\x1b[0m";

pub const ClearLine = "\x1b[2K";
pub const EraseToEOL = "\x1b[K";

pub const Style = enum(u4) {
    Normal = 0,
    Bold = 1,
    Dim = 2,
    Italic = 3,
    Underline = 4,
};

pub const Fg = enum(u8) {
    const template = "{s}{d};{d}m{s}{s}";

    Black = 30,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    White,

    HighBlack = 90,
    HighRed,
    HighGreen,
    HighYellow,
    HighBlue,
    HighMagenta,
    HighCyan,
    HighWhite,

    /// Colorize text with color code and reset at the end
    ///
    /// # Examples
    ///
    /// ```zig
    /// const stdout = std.io.getStdOut().writer();
    ///
    /// // Prefer comptime > runtime
    /// stdout.print(ansi.Fg.paint(.Cyan));
    /// stdout.print(ansi.Fg.Cyan.paint("Hello I'm colored! and I'm pretty bold I'd say", .BOLD), .{});
    /// ```
    pub fn paint(color: Fg, text: []const u8, style: ?Style) []const u8 {
        if (style) |s| {
            return comp(template, .{ PREFIX, @intFromEnum(s), @intFromEnum(color), text, RESET });
        }
        return comp(template, .{ PREFIX, @intFromEnum(Style.Normal), @intFromEnum(color), text, RESET });
    }

    /// Equivalent to
    ///
    /// ```
    /// ansi.Fg.Black.paint(text, style); // or
    /// ansi.Fg.paint(.Black, text, style);
    /// ```
    pub fn black(comptime text: []const u8, style: ?Style) []const u8 {
        return paint(.Black, text, style);
    }

    /// Equivalent to
    ///
    /// ```
    /// ansi.Fg.Red.paint(text, style); // or
    /// ansi.Fg.paint(.Red, text, style);
    /// ```
    pub fn red(comptime text: []const u8, style: ?Style) []const u8 {
        return paint(.Red, text, style);
    }

    /// Equivalent to
    ///
    /// ```
    /// ansi.Fg.Green.paint(text, style); // or
    /// ansi.Fg.paint(.Green, text, style);
    /// ```
    pub fn green(comptime text: []const u8, style: ?Style) []const u8 {
        return paint(.Green, text, style);
    }

    /// Equivalent to
    ///
    /// ```
    /// ansi.Fg.Yellow.paint(text, style); // or
    /// ansi.Fg.paint(.Yellow, text, style);
    /// ```
    pub fn yellow(comptime text: []const u8, style: ?Style) []const u8 {
        return paint(.Yellow, text, style);
    }

    /// Equivalent to
    ///
    /// ```
    /// ansi.Fg.Blue.paint(text, style); // or
    /// ansi.Fg.paint(.Blue, text, style);
    /// ```
    pub fn blue(comptime text: []const u8, style: ?Style) []const u8 {
        return paint(.Blue, text, style);
    }

    /// Equivalent to
    ///
    /// ```
    /// ansi.Fg.Magenta.paint(text, style); // or
    /// ansi.Fg.paint(.Magenta, text, style);
    /// ```
    pub fn magenta(comptime text: []const u8, style: ?Style) []const u8 {
        return paint(.Magenta, text, style);
    }

    /// Equivalent to
    ///
    /// ```
    /// ansi.Fg.Cyan.paint(text, style); // or
    /// ansi.Fg.paint(.Cyan, text, style);
    /// ```
    pub fn cyan(comptime text: []const u8, style: ?Style) []const u8 {
        return paint(.Cyan, text, style);
    }

    /// Equivalent to
    ///
    /// ```
    /// ansi.Fg.White.paint(text, style); // or
    /// ansi.Fg.paint(.White, text, style);
    /// ```
    pub fn white(comptime text: []const u8, style: ?Style) []const u8 {
        return paint(.White, text, style);
    }

    /// Equivalent to
    ///
    /// ```
    /// ansi.Fg.HighBlack.paint(text, style); // or
    /// ansi.Fg.paint(.HighBlack, text, style);
    /// ```
    pub fn highBlack(comptime text: []const u8, style: ?Style) []const u8 {
        return paint(.HighBlack, text, style);
    }

    /// Equivalent to
    ///
    /// ```
    /// ansi.Fg.HighRed.paint(text, style); // or
    /// ansi.Fg.paint(.HighRed, text, style);
    /// ```
    pub fn highRed(comptime text: []const u8, style: ?Style) []const u8 {
        return paint(.HighRed, text, style);
    }

    pub fn highGreen(comptime text: []const u8, style: ?Style) []const u8 {
        return paint(.HighGreen, text, style);
    }

    /// Equivalent to
    ///
    /// ```
    /// ansi.Fg.HighYellow.paint(text, style); // or
    /// ansi.Fg.paint(.HighYellow, text, style);
    /// ```
    pub fn highYellow(comptime text: []const u8, style: ?Style) []const u8 {
        return paint(.HighYellow, text, style);
    }

    /// Equivalent to
    ///
    /// ```
    /// ansi.Fg.HighBlue.paint(text, style); // or
    /// ansi.Fg.paint(.HighBlue, text, style);
    /// ```
    pub fn highBlue(comptime text: []const u8, style: ?Style) []const u8 {
        return paint(.HighBlue, text, style);
    }

    /// Equivalent to
    ///
    /// ```
    /// ansi.Fg.HighMagenta.paint(text, style); // or
    /// ansi.Fg.paint(.HighMagenta, text, style);
    /// ```
    pub fn highMagenta(comptime text: []const u8, style: ?Style) []const u8 {
        return paint(.HighMagenta, text, style);
    }

    /// Equivalent to
    ///
    /// ```
    /// ansi.Fg.HighCyan.paint(text, style); // or
    /// ansi.Fg.paint(.HighCyan, text, style);
    /// ```
    pub fn highCyan(comptime text: []const u8, style: ?Style) []const u8 {
        return paint(.HighCyan, text, style);
    }

    /// # Example
    ///
    /// ```zig
    /// const stdout = std.io.getStdOut().writer();
    ///
    /// // Prefer comptime > runtime
    /// stdout.print(ansi.Fg.rgb("Hello in RGB", 100, 10, 200), .{})
    /// ```
    pub fn rgb(comptime text: []const u8, r: u8, g: u8, b: u8) []const u8 {
        return formatRgb(r, g, b) ++ text ++ RESET;
    }

    /// # Example
    ///
    /// ```zig
    /// const stdout = std.io.getStdOut().writer();
    ///
    /// // Prefer comptime > runtime
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
