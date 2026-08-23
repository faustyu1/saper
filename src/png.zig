//! A minimal RGBA PNG writer. Deflate is emitted as stored blocks, which keeps
//! the encoder tiny; the icon files it produces are small enough not to care.

const std = @import("std");

fn crc32(data: []const u8, seed: u32) u32 {
    var crc = ~seed;
    for (data) |byte| {
        crc ^= byte;
        for (0..8) |_| {
            crc = if (crc & 1 != 0) (crc >> 1) ^ 0xEDB88320 else crc >> 1;
        }
    }
    return ~crc;
}

fn adler32(data: []const u8) u32 {
    var a: u32 = 1;
    var b: u32 = 0;
    for (data) |byte| {
        a = (a + byte) % 65521;
        b = (b + a) % 65521;
    }
    return (b << 16) | a;
}

fn appendChunk(out: *std.ArrayList(u8), gpa: std.mem.Allocator, name: *const [4]u8, body: []const u8) !void {
    var length: [4]u8 = undefined;
    std.mem.writeInt(u32, &length, @intCast(body.len), .big);
    try out.appendSlice(gpa, &length);
    try out.appendSlice(gpa, name);
    try out.appendSlice(gpa, body);

    var crc = crc32(name, 0);
    crc = crc32(body, crc);
    var crc_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &crc_bytes, crc, .big);
    try out.appendSlice(gpa, &crc_bytes);
}

/// Encodes `pixels` (0xAARRGGBB, row major) as a PNG byte stream.
pub fn encode(gpa: std.mem.Allocator, pixels: []const u32, width: u32, height: u32) ![]u8 {
    // Raw image data: every scanline is prefixed with filter type 0.
    var raw = std.ArrayList(u8).empty;
    defer raw.deinit(gpa);
    try raw.ensureTotalCapacity(gpa, height * (1 + width * 4));
    for (0..height) |y| {
        raw.appendAssumeCapacity(0);
        for (0..width) |x| {
            const color = pixels[y * width + x];
            raw.appendAssumeCapacity(@intCast((color >> 16) & 0xff));
            raw.appendAssumeCapacity(@intCast((color >> 8) & 0xff));
            raw.appendAssumeCapacity(@intCast(color & 0xff));
            raw.appendAssumeCapacity(@intCast((color >> 24) & 0xff));
        }
    }

    // zlib stream with uncompressed deflate blocks.
    var zlib = std.ArrayList(u8).empty;
    defer zlib.deinit(gpa);
    try zlib.appendSlice(gpa, &[_]u8{ 0x78, 0x01 });
    var offset: usize = 0;
    while (offset < raw.items.len) {
        const block = @min(raw.items.len - offset, 65535);
        const last: u8 = if (offset + block >= raw.items.len) 1 else 0;
        try zlib.append(gpa, last);
        try zlib.appendSlice(gpa, &[_]u8{
            @intCast(block & 0xff),
            @intCast((block >> 8) & 0xff),
            @intCast(~block & 0xff),
            @intCast((~block >> 8) & 0xff),
        });
        try zlib.appendSlice(gpa, raw.items[offset..][0..block]);
        offset += block;
    }
    var checksum: [4]u8 = undefined;
    std.mem.writeInt(u32, &checksum, adler32(raw.items), .big);
    try zlib.appendSlice(gpa, &checksum);

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, &[_]u8{ 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a });

    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], width, .big);
    std.mem.writeInt(u32, ihdr[4..8], height, .big);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 6; // truecolour with alpha
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    try appendChunk(&out, gpa, "IHDR", &ihdr);
    try appendChunk(&out, gpa, "IDAT", zlib.items);
    try appendChunk(&out, gpa, "IEND", "");

    return out.toOwnedSlice(gpa);
}

test "encodes a decodable header" {
    const gpa = std.testing.allocator;
    const pixels = [_]u32{ 0xff112233, 0xff445566, 0xff778899, 0xffaabbcc };
    const png = try encode(gpa, &pixels, 2, 2);
    defer gpa.free(png);
    try std.testing.expect(png.len > 8);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x89, 'P', 'N', 'G' }, png[0..4]);
    try std.testing.expectEqualSlices(u8, "IHDR", png[12..16]);
    try std.testing.expectEqualSlices(u8, "IEND", png[png.len - 8 ..][0..4]);
}
