//! The Bussin configuration.

/// The syntax variant.
syntax: Syntax,

pub const Syntax = enum(u8) {
    bs = 0,
    bsx = 1,
};
