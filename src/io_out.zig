const std = @import("std");

pub const StdoutWriter = std.fs.File.DeprecatedWriter;

pub fn stdoutWriter() StdoutWriter {
    return std.fs.File.stdout().deprecatedWriter();
}