const std = @import("std");

pub const Status = enum(i32) {
    completed = 1,
    notCompleted = 0,
    failed = -1,
    callerError = -2,
};

pub const Options = packed struct(i32) {
    optFlipV: bool = false,
    optFlipH: bool = false,
    optRotate: bool = false,
    optEdgeFixV: bool = false,
    optEdgeFixH: bool = false,
    padding: i27 = 0,
};

pub const InternalState = opaque {};

extern var wfcMallocPtr: ?*const fn (?*anyopaque, usize) callconv(.C) ?*anyopaque;
extern var wfcFreePtr: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.C) void;

const Context = struct {
    allocator: std.mem.Allocator,
    memAllocs: std.AutoHashMapUnmanaged(usize, usize) = .{},

    pub fn alloc(self: *Context, size: usize) callconv(.C) ?*anyopaque {
        const mem = self.allocator.alignedAlloc(u8, 16, size) catch @panic("wfc: Out of Memory");

        self.memAllocs.put(self.allocator, @intFromPtr(mem.ptr), size) catch @panic("wfc: Out of Memory");

        return mem.ptr;
    }

    pub fn free(self: *Context, ptr: ?*anyopaque) callconv(.C) void {
        if (ptr) |p| {
            const size = self.memAllocs.fetchRemove(@intFromPtr(p)).?.value;
            const mem = @as([*]align(16) u8, @ptrCast(@alignCast(p)))[0..size];
            self.allocator.free(mem);
        }
    }
};

var globalContext: Context = undefined;

pub fn init(allocator: std.mem.Allocator) *Context {
    globalContext.allocator = allocator;
    wfcMallocPtr = @ptrCast(&Context.alloc);
    wfcFreePtr = @ptrCast(&Context.free);
    return &globalContext;
}

pub fn deinit() void {
    globalContext.memAllocs.deinit(globalContext.allocator);
}

extern fn wfc_generate(n: i32, options: Options, bytesPerPixel: i32, srcW: i32, srcH: i32, src: [*]const u8, dstW: i32, dstH: i32, dst: [*]u8) callconv(.C) i32;

extern fn wfc_generateEx(
    n: i32,
    options: Options,
    bytesPerPixel: i32,
    srcW: i32,
    srcH: i32,
    src: [*]const u8,
    dstW: i32,
    dstH: i32,
    dst: [*]u8,
    ctx: ?*anyopaque,
    keep: ?[*]const bool,
) callconv(.C) i32;

extern fn wfc_init(
    n: i32,
    options: Options,
    bytesPerPixel: i32,
    srcW: i32,
    srcH: i32,
    src: [*]const u8,
    dstW: i32,
    dstH: i32,
) callconv(.C) ?*InternalState;

extern fn wfc_initEx(
    n: i32,
    options: Options,
    bytesPerPixel: i32,
    srcW: i32,
    srcH: i32,
    src: [*]const u8,
    dstW: i32,
    dstH: i32,
    dst: [*]u8,
    ctx: ?*anyopaque,
    keep: ?[*]const bool,
) callconv(.C) ?*InternalState;

extern fn wfc_status(*const InternalState) callconv(.C) Status;
extern fn wfc_step(*InternalState) callconv(.C) Status;
extern fn wfc_blit(*const InternalState, [*]const u8, [*]u8) callconv(.C) Status;
extern fn wfc_clone(*const InternalState) callconv(.C) ?*InternalState;
extern fn wfc_free(*InternalState) callconv(.C) void;
extern fn wfc_collapsedCount(*const InternalState) callconv(.C) i32;
extern fn wfc_patternCount(*const InternalState) callconv(.C) i32;

pub const State = struct {
    internal: *InternalState,

    pub inline fn init(n: i32, options: Options, bytesPerPixel: i32, srcW: i32, srcH: i32, src: [*]const u8, dstW: i32, dstH: i32, dst: [*]u8) State {
        const internal = wfc_initEx(n, options, bytesPerPixel, srcW, srcH, src, dstW, dstH, dst, &globalContext, null) orelse unreachable;
        return .{
            .internal = internal,
        };
    }

    pub fn clone(self: *const State) State {
        return .{
            .internal = wfc_clone(self.internal),
        };
    }

    pub inline fn deinit(self: *const State) void {
        wfc_free(self.internal);
    }

    pub inline fn status(self: *const State) Status {
        return wfc_status(self.internal);
    }

    pub inline fn step(self: *State) Status {
        return wfc_step(self.internal);
    }

    pub fn blit(self: *const State, src: []const u8, dst: []u8) Status {
        return wfc_blit(self.internal, src.ptr, dst.ptr);
    }

    pub fn collapsedCount(self: *const State) i32 {
        return wfc_collapsedCount(self.internal);
    }

    pub fn patternCount(self: *const State) i32 {
        return wfc_patternCount(self.internal);
    }
};
