const std = @import("std");
const root = @import("BiFrost");

pub fn main(init: std.process.Init) !void {
    var engine = root{};
    defer engine.deinitEngine(init.gpa);
    try engine.run(init.gpa);
}
