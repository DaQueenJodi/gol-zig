const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("raylib.h");
});

const Cell = bool;
const SCREEN_W: usize = 1028;
const SCREEN_H: usize = 720;
const CELL_W: usize = 20;
const CELL_H: usize = 20;

const Point = struct {
    x: usize,
    y: usize,
};
const colors = [_]c.Color{
    c.RED,
    c.ORANGE,
    c.YELLOW,
    c.GREEN,
    c.BLUE,
    c.PURPLE,
    c.VIOLET,
};
const Gui = struct {
    camera: c.Camera2D,
    lastMousePos: c.Vector2,
    currentColor: usize,
    pub fn start() Gui {
        c.InitWindow(SCREEN_W, SCREEN_H, "uwu");
        c.SetTargetFPS(60);
        var cam = std.mem.zeroes(c.Camera2D);
        cam.zoom = 1;
        return .{
            .currentColor = 0,
            .camera = cam,
            .lastMousePos = c.GetMousePosition()
        };
    }
    pub fn stop() void {
        c.CloseWindow();
    }
    pub fn draw_board(self: *Gui, board: *Board) void {
        c.BeginDrawing();
        c.ClearBackground(c.GREEN);
        c.BeginMode2D(self.camera);
        for (board.grid, 0..) |cell, i| {
            const point = board.idx_to_coord(i);
            const color = if (cell) colors[self.currentColor] else c.WHITE;
            c.DrawRectangle(
                @intCast(c_int, (point.x * CELL_W)),
                @intCast(c_int, (point.y * CELL_H)),
                CELL_W,
                CELL_H,
                color
            );
        }
        c.EndMode2D();
        c.EndDrawing();
    }
};
const Board = struct {
    grid: []Cell,
    size: Point,
    allocator: Allocator,
    const Self = @This();
    pub fn init(allocator: Allocator, size: Point) !Self {
        const buff = try allocator.alloc(Cell, size.x * size.y);
        return .{
            .size = size,
            .grid = buff,
            .allocator = allocator
        };
    }
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.grid);
    }
    pub fn coord_to_idx(self: *Self, x: usize, y: usize) usize {
         return x + (y * self.size.y);
    }
    pub fn idx_to_coord(self: *Self, idx: usize) Point {
        const y = idx / self.size.y;
        const x = idx - (y * self.size.y);
        return .{ .x = x, .y = y };
    }
    pub fn get_neighbors(self: *Self, cell: Point) ![]Cell {
        const buff = try self.allocator.alloc(Cell, 8);
        var counter: usize = 0;
        const offsets: [3]i8 = .{-1, 0, 1};
        for (offsets) |offsetY| {
            for (offsets) |offsetX| {
                if (offsetY == 0 and offsetX == 0) continue;
                    const newX = @intCast(i8, cell.x) + offsetX;
                    const newY = @intCast(i8, cell.y) + offsetY;
                    if (
                        newX < 0 or 
                        newY < 0 or 
                        newX > (self.size.x - 1) or 
                        newY > (self.size.y - 1)
                    ) continue;
                    buff[counter] = self.grid[self.coord_to_idx(@intCast(usize, newX), @intCast(usize, newY))];
                    counter += 1;
            }
        }
        return buff[0..counter];
    }
    pub fn next(self: *Self) !void {
        const neighborsArray = try self.allocator.alloc([]Cell, self.grid.len);
        defer self.allocator.free(neighborsArray);
        for (0..self.grid.len) |i| {
            neighborsArray[i] = try self.get_neighbors(self.idx_to_coord(i));
        }
        for (self.grid, neighborsArray) |*cell, neighbors| {
            var aliveCount: u8 = 0;
            var deadCount: u8 = 0;
            for (neighbors) |n| {
                if (n) aliveCount += 1 else deadCount += 1;
            }
            switch (cell.*) {
                true => {
                    if (aliveCount < 2) cell.* = false; // die from underpopulation
                    if (aliveCount > 3) cell.* = false; // die from overpopulation
                },
                false => {
                    if (aliveCount == 3) cell.* = true; // birthenafy
                }
            }
        }
        for (neighborsArray) |n| {
            self.allocator.free(n);
        }
    }
};

test "neighbors" {
    var buff: [100000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(buff[0..]);
    const allocator = fba.allocator();
    var board = try Board.init(allocator);
    defer board.deinit();
    var neighbors = try board.get_neighbors(.{ .x = 1, .y = 5});
    defer allocator.free(neighbors);
    try std.testing.expectEqual(
        neighbors.len,
        8
    );
    try std.testing.expectEqual(
        std.mem.indexOfScalar(bool, neighbors, true),
        null
    );
    board.grid[0] = true;
    board.grid[1] = true;
    const neighbors2 = try board.get_neighbors(.{ .x = 1, .y = 0 });
    defer allocator.free(neighbors2);
    try std.testing.expect(
        std.mem.indexOfScalar(bool, neighbors2, true) != null
    );
}

fn mousePosToCoord(board: *Board, pos: c.Vector2) ?Point {
    if (pos.x < 0 or pos.y < 0) return null;
    const y = @floatToInt(usize, pos.y) / CELL_H;
    const x = @floatToInt(usize, pos.x) / CELL_W;
    if (x >= board.size.x or y >= board.size.y) return null;
    return .{
        .x =  x,
        .y = y
    };
}

const DEFAULT_SAVE = "welp.sav";
pub fn saveBoard(board: *Board) !void {
    const file = try std.fs.cwd().openFile(DEFAULT_SAVE, .{.mode = .write_only});
    defer file.close();
    for (board.grid) |b| {
        try file.writer().writeByte(if (b) 1 else 0);
    }
}
pub fn restoreBoard(board: *Board) !void {
    const file = try std.fs.cwd().openFile(DEFAULT_SAVE, .{});
    defer file.close();
    for (board.grid) |*b| {
        const char = try file.reader().readByte();
        std.debug.assert(char == 0 or char == 1);
        b.* = if (char == 1) true else false;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    var board = try Board.init(allocator, .{.x = 50, .y = 50});
    defer board.deinit();
    @memset(board.grid, false);

    var gui = Gui.start();
    defer Gui.stop();
    while (true) {
        gui.draw_board(&board);
        if (c.WindowShouldClose()) return;
        if (c.IsKeyPressed(c.KEY_SPACE)) {
            break;
        }
        if (c.IsKeyPressed(c.KEY_S)) {
            try saveBoard(&board);
        }
        if (c.IsKeyPressed(c.KEY_R)) {
            try restoreBoard(&board);
        }
        if (c.IsMouseButtonDown(c.MOUSE_BUTTON_LEFT)) {
            const pos = c.GetMousePosition();
            const point = mousePosToCoord(&board, pos) orelse continue;
            const idx = board.coord_to_idx(point.x, point.y);
            board.grid[idx] = true;
        } else if (c.IsMouseButtonDown(c.MOUSE_BUTTON_RIGHT)) {
            const pos = c.GetMousePosition();
            const point = mousePosToCoord(&board, pos) orelse continue;
            const idx = board.coord_to_idx(point.x, point.y);
            board.grid[idx] = false;
        }
    }
    while (!c.WindowShouldClose()) {
        std.time.sleep(100000000);
        try board.next();
        gui.currentColor = (gui.currentColor + 1) % (colors.len - 1);
        gui.draw_board(&board);
    }
}
