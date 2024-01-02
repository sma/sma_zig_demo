const std = @import("std");
const SDL = @cImport(@cInclude("SDL2/SDL.h"));

// brew install sdl2
//
// zig run -I/usr/local/include -L/usr/local/lib -lSDL2 src/sdldemo.zig

pub fn main() !void {
    // setup SDL subsystems
    if (SDL.SDL_Init(SDL.SDL_INIT_VIDEO | SDL.SDL_INIT_EVENTS | SDL.SDL_INIT_AUDIO) < 0)
        sdlPanic();
    defer SDL.SDL_Quit();

    // open a window, centered, resizable within fixed bounds
    // var window = sdl.createWindow(
    //     "SDL2 Zig Demo",
    //     SDL.SDL_WINDOWPOS_CENTERED,
    //     SDL.SDL_WINDOWPOS_CENTERED,
    //     640,
    //     480,
    //     SDL.SDL_WINDOW_SHOWN | SDL.SDL_WINDOW_RESIZABLE,
    // ) orelse sdlPanic();
    // defer _ = sdl.destroyWindow(window);
    var window = try sdl.Window.create("SDL2 Zig Demo");
    defer window.destroy();

    SDL.SDL_SetWindowMinimumSize(window.window, 320, 240);
    SDL.SDL_SetWindowMaximumSize(window.window, 640, 480);

    // setup a renderer to draw something
    var renderer = try window.createRenderer();
    defer renderer.destroy();

    // wait for closing the window
    mainLoop: while (true) {
        while (sdl.pollEvent()) |ev| {
            switch (ev.type) {
                SDL.SDL_QUIT => break :mainLoop,
                SDL.SDL_MOUSEBUTTONDOWN => {
                    std.debug.print("x={}, y={}\n", .{ ev.button.x, ev.button.y });
                },
                else => {},
            }
        }

        // render the scene
        renderer.setColor(0xF7, 0xA4, 0x1D, 0xFF);
        renderer.clear();

        // present it, double-buffering
        renderer.present();
    }
}

fn sdlPanic() noreturn {
    // pointer magic ... to crash with a nice error message
    const str = @as(?[*:0]const u8, SDL.SDL_GetError()) orelse "unknown error";
    @panic(std.mem.sliceTo(str, 0));
}

// nicer API
pub const sdl = struct {
    const Error = error{CannotCreate};

    // even nicer
    const Window = struct {
        window: *SDL.SDL_Window,

        fn create(title: [:0]const u8) !Window {
            return Window{
                .window = SDL.SDL_CreateWindow(
                    title,
                    SDL.SDL_WINDOWPOS_CENTERED,
                    SDL.SDL_WINDOWPOS_CENTERED,
                    640,
                    480,
                    SDL.SDL_WINDOW_SHOWN | SDL.SDL_WINDOW_RESIZABLE,
                ) orelse return Error.CannotCreate,
            };
        }

        fn destroy(self: *Window) void {
            SDL.SDL_DestroyWindow(self.window);
        }

        fn createRenderer(self: *Window) !Renderer {
            return Renderer{
                .renderer = SDL.SDL_CreateRenderer(
                    self.window,
                    -1,
                    SDL.SDL_RENDERER_ACCELERATED,
                ) orelse return Error.CannotCreate,
            };
        }
    };

    const Renderer = struct {
        renderer: *SDL.SDL_Renderer,

        inline fn destroy(self: *Renderer) void {
            _ = SDL.SDL_DestroyRenderer(self.renderer);
        }

        inline fn setColor(self: *Renderer, r: u8, g: u8, b: u8, a: u8) void {
            _ = SDL.SDL_SetRenderDrawColor(self.renderer, r, g, b, a);
        }

        inline fn clear(self: *Renderer) void {
            _ = SDL.SDL_RenderClear(self.renderer);
        }

        inline fn present(self: *Renderer) void {
            _ = SDL.SDL_RenderPresent(self.renderer);
        }
    };

    pub const createWindow = SDL.SDL_CreateWindow;
    pub const destroyWindow = SDL.SDL_DestroyWindow;

    pub fn pollEvent() ?SDL.SDL_Event {
        var ev: SDL.SDL_Event = undefined;
        return if (SDL.SDL_PollEvent(&ev) != 0) ev else null;
    }
};
