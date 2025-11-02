const std = @import("std");
const gl = @import("gl");
const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
});

pub const std_options: std.Options = .{ .log_level = .debug };

const sdl_log = std.log.scoped(.sdl);

// ============================================================================
// GLOBAL STATE
// ============================================================================

var window: *c.SDL_Window = undefined;
var gl_context: c.SDL_GLContext = undefined;
var gl_procs: gl.ProcTable = undefined;

// ============================================================================
// INITIALIZATION
// ============================================================================

fn initSDL() !void {
    sdl_log.info("Initializing SDL...", .{});
    
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        sdl_log.err("SDL_Init failed: {s}", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    
    sdl_log.info("SDL initialized successfully", .{});
}

fn createWindow() !void {
    sdl_log.info("Creating window...", .{});
    
    // Request OpenGL 3.3 Core Profile
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 3);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);
    
    window = c.SDL_CreateWindow(
        "Learn OpenGL",
        800,
        600,
        c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE,
    ) orelse {
        sdl_log.err("SDL_CreateWindow failed: {s}", .{c.SDL_GetError()});
        return error.WindowCreationFailed;
    };
    
    sdl_log.info("Window created successfully", .{});
}

fn createOpenGLContext() !void {
    sdl_log.info("Creating OpenGL context...", .{});
    
    gl_context = c.SDL_GL_CreateContext(window) orelse {
        sdl_log.err("SDL_GL_CreateContext failed: {s}", .{c.SDL_GetError()});
        return error.GLContextFailed;
    };
    
    if (!c.SDL_GL_MakeCurrent(window, gl_context)) {
        sdl_log.err("SDL_GL_MakeCurrent failed: {s}", .{c.SDL_GetError()});
        return error.MakeCurrentFailed;
    }
    
    sdl_log.info("OpenGL context created successfully", .{});
}

fn loadOpenGLFunctions() !void {
    sdl_log.info("Loading OpenGL functions...", .{});
    
    if (!gl_procs.init(&c.SDL_GL_GetProcAddress)) {
        sdl_log.err("Failed to load OpenGL functions", .{});
        return error.GlInitFailed;
    }
    
    gl.makeProcTableCurrent(&gl_procs);
    
    sdl_log.info("OpenGL functions loaded successfully", .{});
    
    // Print OpenGL info
    if (gl.GetString(gl.VERSION)) |version| {
        sdl_log.info("OpenGL Version: {s}", .{version});
    }
    if (gl.GetString(gl.SHADING_LANGUAGE_VERSION)) |glsl| {
        sdl_log.info("GLSL Version: {s}", .{glsl});
    }
    if (gl.GetString(gl.RENDERER)) |renderer| {
        sdl_log.info("Renderer: {s}", .{renderer});
    }
}

// ============================================================================
// OPENGL CODE - Add your Learn OpenGL code here!
// ============================================================================

fn initOpenGL() !void {
    // TODO: Add your OpenGL initialization code here
    // This is where you'll create shaders, buffers, etc.
    
    std.debug.print("\n", .{});
    std.debug.print("==============================================\n", .{});
    std.debug.print("  OpenGL Setup Complete!\n", .{});
    std.debug.print("  Ready to follow Learn OpenGL tutorials\n", .{});
    std.debug.print("==============================================\n", .{});
    std.debug.print("\n", .{});
}

fn render() !void {
    // TODO: Add your rendering code here
    
    // Clear the screen to a nice color
    gl.ClearColor(0.2, 0.3, 0.3, 1.0);
    gl.Clear(gl.COLOR_BUFFER_BIT);
    
    // Your OpenGL drawing code goes here!
    
    // Swap buffers
    if (!c.SDL_GL_SwapWindow(window)) {
        return error.SwapWindowFailed;
    }
}

fn cleanup() void {
    // TODO: Add your OpenGL cleanup code here (delete buffers, shaders, etc.)
    
    gl.makeProcTableCurrent(null);
    _ = c.SDL_GL_DestroyContext(gl_context);
    c.SDL_DestroyWindow(window);
    c.SDL_Quit();
    
    sdl_log.info("Cleanup complete", .{});
}

// ============================================================================
// MAIN LOOP
// ============================================================================

pub fn main() !void {
    // Initialize everything
    try initSDL();
    defer c.SDL_Quit();
    
    try createWindow();
    defer c.SDL_DestroyWindow(window);
    
    try createOpenGLContext();
    defer _ = c.SDL_GL_DestroyContext(gl_context);
    
    try loadOpenGLFunctions();
    defer gl.makeProcTableCurrent(null);
    
    try initOpenGL();
    
    // Main loop
    var running = true;
    while (running) {
        // Handle events
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) {
                running = false;
            }
            
            // TODO: Add your event handling code here
            // (keyboard input, mouse input, etc.)
        }
        
        // Render
        try render();
    }
    
    std.debug.print("Exiting...\n", .{});
}
