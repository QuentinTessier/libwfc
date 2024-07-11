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
extern var wfcRandPtr: ?*const fn (?*anyopaque) callconv(.C) f32;

const Context = struct {
    allocator: std.mem.Allocator,
    memAllocs: std.AutoHashMapUnmanaged(usize, usize) = .{},
    rng: std.Random,

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

    pub fn rand(self: *Context) callconv(.C) f32 {
        return self.rng.float(f32);
    }
};

var globalContext: Context = undefined;

pub fn init(allocator: std.mem.Allocator, rng: std.Random) *Context {
    globalContext.allocator = allocator;
    globalContext.rng = rng;
    wfcMallocPtr = @ptrCast(&Context.alloc);
    wfcFreePtr = @ptrCast(&Context.free);
    wfcRandPtr = @ptrCast(&Context.rand);
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

extern fn wfc_patternPresentAt(*const InternalState, patt: i32, x: i32, y: i32) callconv(.C) i32;
extern fn wfc_modifiedAt(*const InternalState, x: i32, y: i32) callconv(.C) i32;
extern fn wfc_pixelToBlitAt(*const InternalState, [*]const u8, patt: i32, x: i32, y: i32) callconv(.C) ?*const u8;

pub const PatternPresentAtResult = enum(u32) {
    NotPresent,
    Present,
};

pub const ModifiedAtResult = enum(u8) {
    NotModified,
    Modified,
};

pub const State = struct {
    internal: *InternalState,

    pub inline fn init(n: i32, options: Options, bytesPerPixel: i32, srcW: i32, srcH: i32, src: []const u8, dstW: i32, dstH: i32, dst: []u8, keep: []const bool) Error!State {
        const internal = wfc_initEx(
            n,
            options,
            bytesPerPixel,
            srcW,
            srcH,
            src.ptr,
            dstW,
            dstH,
            dst.ptr,
            &globalContext,
            keep.ptr,
        );
        if (internal == null) return error.FailedToCreateState;
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

    pub fn patternPresentAt(self: *const State, patt: i32, x: i32, y: i32) Error!PatternPresentAtResult {
        const res = wfc_patternPresentAt(self.internal, patt, x, y);
        return switch (res) {
            0 => .NotPresent,
            1 => .Present,
            else => error.ParameterError,
        };
    }

    pub fn modifiedAt(self: *const State, x: i32, y: i32) Error!ModifiedAtResult {
        const res = wfc_modifiedAt(self.internal, x, y);
        return switch (res) {
            0 => .NotModified,
            1 => .Modified,
            else => error.ParameterError,
        };
    }

    pub fn pixelToBlitAt(self: *const State, src: []const u8, patt: i32, x: i32, y: i32) *const u8 {
        const res = wfc_pixelToBlitAt(self.internal, src.ptr, patt, x, y);
        return if (res) |r| r else error.ParameterError;
    }
};

const PipelineOption = union(enum(u8)) {
    static: usize,
    dynamic: void,
};

pub const Error = error{
    FailedToCreateState,
    ParameterError,
};

pub fn Pipeline(comptime opt: PipelineOption) type {
    return switch (opt.storage) {
        .static => |n| StaticPipeline(n),
        .dynamic => @panic("Not impl"),
    };
}

// TODO: Use std.BoundedArray
pub fn StaticPipeline(comptime N: usize) type {
    return struct {
        dstW: i32,
        dstH: i32,

        states: [N]State,
        len: usize,
        counter: i32,

        bytesPerPixel: i32 = 4,

        pub fn init(n: i32, options: Options, bytesPerPixel: i32, srcDim: [2]i32, src: []const u8, dstDim: [2]i32, dst: []u8, keep: []const bool) Error!@This() {
            const state = try State.init(
                n,
                options,
                bytesPerPixel,
                srcDim[0],
                srcDim[1],
                src,
                dstDim[0],
                dstDim[1],
                dst,
                keep,
            );
            return .{
                .dstH = dstDim[1],
                .dstW = dstDim[0],
                .len = 1,
                .states = [1]State{state} ++ [1]State{undefined} ** (N - 1),
                .counter = 0,
                .bytesPerPixel = bytesPerPixel,
            };
        }

        pub fn deinit(self: *@This()) void {
            for (self.states[0..self.len]) |*st| {
                st.deinit();
            }
        }

        pub fn patternCount(self: *const @This()) i32 {
            return self.states[self.len - 1].patternCount();
        }

        pub fn status(self: *const @This()) Status {
            return self.states[self.len - 1].status();
        }

        pub fn step(self: *@This()) Status {
            const st = self.states[self.len - 1].step();
            if (st != .notCompleted) return st;

            if (self.len < N) {
                self.counter += 1;
                if (self.counter == 1000) {
                    self.states[self.len] = self.states[self.len - 1].clone();
                    self.len += 1;
                    self.counter = 0;
                }
            }
            return .notCompleted;
        }

        pub fn backtrack(self: *@This()) Status {
            if (self.len <= 1) return .failed;

            self.states[self.len - 1].deinit();
            self.len -= 1;
            self.counter = 0;
            return .notCompleted;
        }

        pub fn blit(self: *@This(), src: []const u8, dst: []u8) Status {
            return self.states[self.len - 1].blit(src, dst);
        }
    };
}
