const std = @import("std");
const builtin = @import("builtin");
const gl = @import("gl");
const imgui = @import("imgui");
const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cDefine("SDL_MAIN_HANDLED", {}); // We are providing our own entry point
    @cInclude("SDL3/SDL_main.h");
});

pub const std_options: std.Options = .{ .log_level = .debug };

const target_triple: [:0]const u8 = x: {
    var buf: [256]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buf);
    break :x (builtin.target.zigTriple(fba.allocator()) catch unreachable) ++ "";
};

const sdl_log = std.log.scoped(.sdl);
const gl_log = std.log.scoped(.gl);

/// ```txt
///               (5)
///             ..'''..
///         ..''       ''..
/// (3) ._'_________________'_. (4)
///     |\                   /|
///     |  \               /  |
///     |    \           /    |
///     |     \         /     |
/// (1) ''..    \     /    ..'' (2)
///         ''..  \ /  ..''
///             ''.V.''
///               (0)
/// ```
const hexagon_mesh = struct {
    // zig fmt: off
    const vertices = [_]Vertex{
        .{ .position = .{  0,                        -1   }, .color = .{ 0, 1, 1 } },
        .{ .position = .{ -(@sqrt(@as(f32, 3)) / 2), -0.5 }, .color = .{ 0, 0, 1 } },
        .{ .position = .{  (@sqrt(@as(f32, 3)) / 2), -0.5 }, .color = .{ 0, 1, 0 } },
        .{ .position = .{ -(@sqrt(@as(f32, 3)) / 2),  0.5 }, .color = .{ 1, 0, 1 } },
        .{ .position = .{  (@sqrt(@as(f32, 3)) / 2),  0.5 }, .color = .{ 1, 1, 0 } },
        .{ .position = .{  0,                         1   }, .color = .{ 1, 0, 0 } },
    };
    // zig fmt: on

    const indices = [_]u8{
        0, 3, 1,
        0, 4, 3,
        0, 2, 4,
        3, 4, 5,
    };

    const Vertex = extern struct {
        position: [2]f32,
        color: [3]f32,
    };
};

var fully_initialized = false;

var window: *c.SDL_Window = undefined;
var gl_context: c.SDL_GLContext = undefined;
var gl_procs: gl.ProcTable = undefined;

var program: c_uint = undefined;

var framebuffer_size_uniform: c_int = undefined;
var angle_uniform: c_int = undefined;

/// Vertex Array Object (VAO). Holds information on how vertex data is laid out in memory.
/// Using VAOs is strictly required in modern OpenGL.
var vao: c_uint = undefined;

/// Vertex Buffer Object (VBO). Holds vertex data.
var vbo: c_uint = undefined;

/// Index Buffer Object (IBO). Maps indices to vertices, to enable reusing vertex data.
var ibo: c_uint = undefined;

var uptime: std.time.Timer = undefined;

// ============================================================================
// WINDOW MANAGEMENT FUNCTIONS
// ============================================================================

/// Initialize SDL and print version info
fn initSDL() !void {
    const platform: [*:0]const u8 = c.SDL_GetPlatform();
    sdl_log.debug("SDL platform: {s}", .{platform});
    sdl_log.debug("SDL build time version: {d}.{d}.{d}", .{
        c.SDL_MAJOR_VERSION,
        c.SDL_MINOR_VERSION,
        c.SDL_MICRO_VERSION,
    });
    sdl_log.debug("SDL build time revision: {s}", .{c.SDL_REVISION});
    
    const version = c.SDL_GetVersion();
    sdl_log.debug("SDL runtime version: {d}.{d}.{d}", .{
        c.SDL_VERSIONNUM_MAJOR(version),
        c.SDL_VERSIONNUM_MINOR(version),
        c.SDL_VERSIONNUM_MICRO(version),
    });
    const revision: [*:0]const u8 = c.SDL_GetRevision();
    sdl_log.debug("SDL runtime revision: {s}", .{revision});

    try errify(c.SDL_SetAppMetadata("Hexagon!", "0.0.0", "example.zig-examples.opengl-hexagon"));
    try errify(c.SDL_Init(c.SDL_INIT_VIDEO));
}

/// Configure OpenGL context attributes based on the API version
fn configureOpenGLAttributes() !void {
    try errify(c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, gl.info.version_major));
    try errify(c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, gl.info.version_minor));
    try errify(c.SDL_GL_SetAttribute(
        c.SDL_GL_CONTEXT_PROFILE_MASK,
        switch (gl.info.api) {
            .gl => if (gl.info.profile) |profile| switch (profile) {
                .core => c.SDL_GL_CONTEXT_PROFILE_CORE,
                .compatibility => c.SDL_GL_CONTEXT_PROFILE_COMPATIBILITY,
                else => comptime unreachable,
            } else 0,
            .gles, .glsc => c.SDL_GL_CONTEXT_PROFILE_ES,
        },
    ));
    try errify(c.SDL_GL_SetAttribute(
        c.SDL_GL_CONTEXT_FLAGS,
        if (gl.info.api == .gl and gl.info.version_major >= 3) c.SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG else 0,
    ));
}

/// Create the window and OpenGL context
fn createWindow() !void {
    window = try errify(c.SDL_CreateWindow("Hexagon!", 640, 480, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE));
    gl_context = try errify(c.SDL_GL_CreateContext(window));
    try errify(c.SDL_GL_MakeCurrent(window, gl_context));
}

/// Load OpenGL function pointers
fn initOpenGL() !void {
    if (!gl_procs.init(&c.SDL_GL_GetProcAddress)) return error.GlInitFailed;
    gl.makeProcTableCurrent(&gl_procs);
}

// ============================================================================
// GRAPHICS FUNCTIONS
// ============================================================================

/// Compile a shader and check for errors
fn compileShader(shader_type: c_uint, version: [:0]const u8, source: [:0]const u8) !c_uint {
    var success: c_int = undefined;
    var info_log_buf: [512:0]u8 = undefined;

    const shader = gl.CreateShader(shader_type);
    if (shader == 0) return error.GlCreateShaderFailed;
    errdefer gl.DeleteShader(shader);

    const sources = [_][*:0]const u8{ version.ptr, source.ptr };
    const lengths = [_]c_int{ @intCast(version.len), @intCast(source.len) };

    gl.ShaderSource(shader, 2, &sources, &lengths);
    gl.CompileShader(shader);
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, (&success)[0..1]);
    
    if (success == gl.FALSE) {
        gl.GetShaderInfoLog(shader, info_log_buf.len, null, &info_log_buf);
        gl_log.err("{s}", .{std.mem.sliceTo(&info_log_buf, 0)});
        return error.GlCompileShaderFailed;
    }

    return shader;
}

/// Create and link the shader program
fn createShaderProgram() !c_uint {
    // Shader version header
    const shader_version: [:0]const u8 = switch (gl.info.api) {
        .gl => "#version 410 core\n",
        .gles, .glsc => "#version 300 es\n",
    };

    // Vertex shader source
    const vertex_shader_source =
        \\// Width/height of the framebuffer
        \\uniform vec2 u_FramebufferSize;
        \\
        \\// Amount (in radians) to rotate the object
        \\uniform float u_Angle;
        \\
        \\// Vertex attributes
        \\in vec4 a_Position;
        \\in vec4 a_Color;
        \\
        \\// Color output to pass to fragment shader
        \\out vec4 v_Color;
        \\
        \\void main() {
        \\    vec2 scale = min(u_FramebufferSize.yx / u_FramebufferSize.xy, vec2(1));
        \\    scale *= 0.875;
        \\    float s = sin(u_Angle);
        \\    float c = cos(u_Angle);
        \\    gl_Position = vec4(
        \\        (a_Position.x * c + a_Position.y * -s) * scale.x,
        \\        (a_Position.x * s + a_Position.y * c) * scale.y,
        \\        a_Position.zw
        \\    );
        \\    v_Color = a_Color;
        \\}
        \\
    ;

    // Fragment shader source
    const fragment_shader_source =
        \\precision highp float;
        \\precision highp int;
        \\in vec4 v_Color;
        \\out vec4 f_Color;
        \\
        \\void main() {
        \\    f_Color = v_Color;
        \\}
        \\
    ;

    // Compile shaders
    const vertex_shader = try compileShader(gl.VERTEX_SHADER, shader_version, vertex_shader_source);
    defer gl.DeleteShader(vertex_shader);

    const fragment_shader = try compileShader(gl.FRAGMENT_SHADER, shader_version, fragment_shader_source);
    defer gl.DeleteShader(fragment_shader);

    // Create and link program
    const prog = gl.CreateProgram();
    if (prog == 0) return error.GlCreateProgramFailed;
    errdefer gl.DeleteProgram(prog);

    gl.AttachShader(prog, vertex_shader);
    gl.AttachShader(prog, fragment_shader);
    gl.LinkProgram(prog);

    // Check link status
    var success: c_int = undefined;
    var info_log_buf: [512:0]u8 = undefined;
    gl.GetProgramiv(prog, gl.LINK_STATUS, (&success)[0..1]);
    if (success == gl.FALSE) {
        gl.GetProgramInfoLog(prog, info_log_buf.len, null, &info_log_buf);
        gl_log.err("{s}", .{std.mem.sliceTo(&info_log_buf, 0)});
        return error.LinkProgramFailed;
    }

    return prog;
}

/// Setup vertex buffers and attributes
fn setupBuffers(shader_program: c_uint) !void {
    // Generate buffers
    gl.GenVertexArrays(1, (&vao)[0..1]);
    gl.GenBuffers(1, (&vbo)[0..1]);
    gl.GenBuffers(1, (&ibo)[0..1]);

    // Bind VAO
    gl.BindVertexArray(vao);
    defer gl.BindVertexArray(0);

    // Setup VBO with vertex data
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(hexagon_mesh.vertices)), &hexagon_mesh.vertices, gl.STATIC_DRAW);

    // Configure vertex attributes
    const position_attrib: c_uint = @intCast(gl.GetAttribLocation(shader_program, "a_Position"));
    gl.EnableVertexAttribArray(position_attrib);
    gl.VertexAttribPointer(
        position_attrib,
        @typeInfo(@FieldType(hexagon_mesh.Vertex, "position")).array.len,
        gl.FLOAT,
        gl.FALSE,
        @sizeOf(hexagon_mesh.Vertex),
        @offsetOf(hexagon_mesh.Vertex, "position"),
    );

    const color_attrib: c_uint = @intCast(gl.GetAttribLocation(shader_program, "a_Color"));
    gl.EnableVertexAttribArray(color_attrib);
    gl.VertexAttribPointer(
        color_attrib,
        @typeInfo(@FieldType(hexagon_mesh.Vertex, "color")).array.len,
        gl.FLOAT,
        gl.FALSE,
        @sizeOf(hexagon_mesh.Vertex),
        @offsetOf(hexagon_mesh.Vertex, "color"),
    );

    // Setup IBO with index data
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo);
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(hexagon_mesh.indices)), &hexagon_mesh.indices, gl.STATIC_DRAW);
}

/// Render one frame
fn renderFrame() !void {
    // Clear screen
    gl.ClearColor(1, 1, 1, 1);
    gl.Clear(gl.COLOR_BUFFER_BIT);

    // Use shader program
    gl.UseProgram(program);
    defer gl.UseProgram(0);

    // Update viewport and uniforms
    var fb_width: c_int = undefined;
    var fb_height: c_int = undefined;
    try errify(c.SDL_GetWindowSizeInPixels(window, &fb_width, &fb_height));
    gl.Viewport(0, 0, fb_width, fb_height);
    gl.Uniform2f(framebuffer_size_uniform, @floatFromInt(fb_width), @floatFromInt(fb_height));

    // Rotate hexagon (one revolution per minute)
    const seconds = @as(f32, @floatFromInt(uptime.read())) / std.time.ns_per_s;
    gl.Uniform1f(angle_uniform, seconds / 60 * -std.math.tau);

    // Draw hexagon
    gl.BindVertexArray(vao);
    defer gl.BindVertexArray(0);
    gl.DrawElements(gl.TRIANGLES, hexagon_mesh.indices.len, gl.UNSIGNED_BYTE, 0);

    // Swap buffers
    try errify(c.SDL_GL_SwapWindow(window));
}

// ============================================================================
// SDL APPLICATION LIFECYCLE
// ============================================================================

fn sdlAppInit(appstate: ?*?*anyopaque, argv: [][*:0]u8) !c.SDL_AppResult {
    _ = appstate;
    _ = argv;

    std.log.debug("{s} {s}", .{ target_triple, @tagName(builtin.mode) });

    // Initialize SDL and window
    try initSDL();
    try configureOpenGLAttributes();
    try createWindow();
    errdefer {
        errify(c.SDL_GL_DestroyContext(gl_context)) catch {};
        c.SDL_DestroyWindow(window);
    }

    // Initialize OpenGL
    try initOpenGL();
    errdefer gl.makeProcTableCurrent(null);

    // Create graphics resources
    program = try createShaderProgram();
    errdefer gl.DeleteProgram(program);

    framebuffer_size_uniform = gl.GetUniformLocation(program, "u_FramebufferSize");
    angle_uniform = gl.GetUniformLocation(program, "u_Angle");

    try setupBuffers(program);
    errdefer {
        gl.DeleteBuffers(1, (&ibo)[0..1]);
        gl.DeleteBuffers(1, (&vbo)[0..1]);
        gl.DeleteVertexArrays(1, (&vao)[0..1]);
    }

    uptime = try std.time.Timer.start();
    fully_initialized = true;

    return c.SDL_APP_CONTINUE;
}

fn sdlAppIterate(appstate: ?*anyopaque) !c.SDL_AppResult {
    _ = appstate;
    try renderFrame();
    return c.SDL_APP_CONTINUE;
}

fn sdlAppEvent(appstate: ?*anyopaque, event: *c.SDL_Event) !c.SDL_AppResult {
    _ = appstate;

    if (event.type == c.SDL_EVENT_QUIT) {
        return c.SDL_APP_SUCCESS;
    }

    return c.SDL_APP_CONTINUE;
}

fn sdlAppQuit(appstate: ?*anyopaque, result: anyerror!c.SDL_AppResult) void {
    _ = appstate;

    _ = result catch |err| if (err == error.SdlError) {
        sdl_log.err("{s}", .{c.SDL_GetError()});
    };

    if (fully_initialized) {
        gl.DeleteBuffers(1, (&ibo)[0..1]);
        gl.DeleteBuffers(1, (&vbo)[0..1]);
        gl.DeleteVertexArrays(1, (&vao)[0..1]);
        gl.DeleteProgram(program);
        gl.makeProcTableCurrent(null);
        errify(c.SDL_GL_MakeCurrent(window, null)) catch {};
        errify(c.SDL_GL_DestroyContext(gl_context)) catch {};
        c.SDL_DestroyWindow(window);
        fully_initialized = false;
    }
}

/// Converts the return value of an SDL function to an error union.
inline fn errify(value: anytype) error{SdlError}!switch (@typeInfo(@TypeOf(value))) {
    .bool => void,
    .pointer, .optional => @TypeOf(value.?),
    .int => |info| switch (info.signedness) {
        .signed => @TypeOf(@max(0, value)),
        .unsigned => @TypeOf(value),
    },
    else => @compileError("unerrifiable type: " ++ @typeName(@TypeOf(value))),
} {
    return switch (@typeInfo(@TypeOf(value))) {
        .bool => if (!value) error.SdlError,
        .pointer, .optional => value orelse error.SdlError,
        .int => |info| switch (info.signedness) {
            .signed => if (value >= 0) @max(0, value) else error.SdlError,
            .unsigned => if (value != 0) value else error.SdlError,
        },
        else => comptime unreachable,
    };
}

//#region SDL main callbacks boilerplate

pub fn main() !u8 {
    app_err.reset();
    var empty_argv: [0:null]?[*:0]u8 = .{};
    const status: u8 = @truncate(@as(c_uint, @bitCast(c.SDL_RunApp(empty_argv.len, @ptrCast(&empty_argv), sdlMainC, null))));
    return app_err.load() orelse status;
}

fn sdlMainC(argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c_int {
    return c.SDL_EnterAppMainCallbacks(argc, @ptrCast(argv), sdlAppInitC, sdlAppIterateC, sdlAppEventC, sdlAppQuitC);
}

fn sdlAppInitC(appstate: ?*?*anyopaque, argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c.SDL_AppResult {
    return sdlAppInit(appstate.?, @ptrCast(argv.?[0..@intCast(argc)])) catch |err| app_err.store(err);
}

fn sdlAppIterateC(appstate: ?*anyopaque) callconv(.c) c.SDL_AppResult {
    return sdlAppIterate(appstate) catch |err| app_err.store(err);
}

fn sdlAppEventC(appstate: ?*anyopaque, event: ?*c.SDL_Event) callconv(.c) c.SDL_AppResult {
    return sdlAppEvent(appstate, event.?) catch |err| app_err.store(err);
}

fn sdlAppQuitC(appstate: ?*anyopaque, result: c.SDL_AppResult) callconv(.c) void {
    sdlAppQuit(appstate, app_err.load() orelse result);
}

var app_err: ErrorStore = .{};

const ErrorStore = struct {
    const status_not_stored = 0;
    const status_storing = 1;
    const status_stored = 2;

    status: c.SDL_AtomicInt = .{},
    err: anyerror = undefined,
    trace_index: usize = undefined,
    trace_addrs: [32]usize = undefined,

    fn reset(es: *ErrorStore) void {
        _ = c.SDL_SetAtomicInt(&es.status, status_not_stored);
    }

    fn store(es: *ErrorStore, err: anyerror) c.SDL_AppResult {
        if (c.SDL_CompareAndSwapAtomicInt(&es.status, status_not_stored, status_storing)) {
            es.err = err;
            if (@errorReturnTrace()) |src_trace| {
                es.trace_index = src_trace.index;
                const len = @min(es.trace_addrs.len, src_trace.instruction_addresses.len);
                @memcpy(es.trace_addrs[0..len], src_trace.instruction_addresses[0..len]);
            }
            _ = c.SDL_SetAtomicInt(&es.status, status_stored);
        }
        return c.SDL_APP_FAILURE;
    }

    fn load(es: *ErrorStore) ?anyerror {
        if (c.SDL_GetAtomicInt(&es.status) != status_stored) return null;
        if (@errorReturnTrace()) |dst_trace| {
            dst_trace.index = es.trace_index;
            const len = @min(dst_trace.instruction_addresses.len, es.trace_addrs.len);
            @memcpy(dst_trace.instruction_addresses[0..len], es.trace_addrs[0..len]);
        }
        return es.err;
    }
};

//#endregion SDL main callbacks boilerplate
