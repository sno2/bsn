pub fn blue(comptime string: []const u8) []const u8 {
    return "\x1b[34m" ++ string ++ "\x1b[0m";
}

pub fn green(comptime string: []const u8) []const u8 {
    return "\x1b[32m" ++ string ++ "\x1b[0m";
}

pub fn lightGreen(comptime string: []const u8) []const u8 {
    return "\x1b[92m" ++ string ++ "\x1b[0m";
}
