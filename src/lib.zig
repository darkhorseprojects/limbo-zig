const std = @import("std");

pub const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const Error = error{
    Error,
    Internal,
    Perm,
    Abort,
    Busy,
    Locked,
    NoMem,
    ReadOnly,
    Interrupt,
    IoErr,
    Corrupt,
    NotFound,
    Full,
    CantOpen,
    Protocol,
    Empty,
    Schema,
    TooBig,
    Constraint,
    Mismatch,
    Misuse,
    NoLFS,
    Auth,
    Format,
    Range,
    NotADB,
    Notice,
    Warning,
    Row,
    Done,
    Unknown,
};

pub fn checkCode(code: c_int) !void {
    const rc = code & 0xff;
    if (rc == c.SQLITE_OK or rc == c.SQLITE_ROW or rc == c.SQLITE_DONE) return;
    return switch (rc) {
        c.SQLITE_ERROR => error.Error,
        c.SQLITE_ABORT => error.Abort,
        c.SQLITE_BUSY => error.Busy,
        c.SQLITE_NOMEM => error.NoMem,
        c.SQLITE_INTERRUPT => error.Interrupt,
        c.SQLITE_NOTFOUND => error.NotFound,
        c.SQLITE_CANTOPEN => error.CantOpen,
        c.SQLITE_MISUSE => error.Misuse,
        else => error.Unknown,
    };
}

pub const Text = struct {
    data: []const u8,
};

pub fn text(data: []const u8) Text {
    return .{ .data = data };
}

pub const Database = struct {
    db: ?*c.sqlite3,

    pub fn open(options: struct { path: [:0]const u8, mode: enum { ReadWrite } = .ReadWrite, create: bool = true }) !Database {
        _ = options.mode;
        _ = options.create;
        var db: ?*c.sqlite3 = null;
        try checkCode(c.sqlite3_open(options.path.ptr, &db));
        return .{ .db = db };
    }

    pub fn close(self: *Database) void {
        if (self.db) |db| {
            _ = c.sqlite3_close_v2(db);
            self.db = null;
        }
    }

    pub fn exec(self: Database, sql: []const u8, args: anytype) !void {
        var stmt = try self.prepare(@TypeOf(args), struct {}, sql);
        defer stmt.finalize();
        try stmt.bind(args);
        _ = try stmt.step();
    }

    pub fn prepare(self: Database, comptime ArgsType: type, comptime RowType: type, sql: []const u8) !Statement(ArgsType, RowType) {
        var stmt_ptr: ?*c.sqlite3_stmt = null;
        try checkCode(c.sqlite3_prepare_v2(self.db, sql.ptr, @intCast(sql.len), &stmt_ptr, null));
        return .{
            .stmt = stmt_ptr.?,
        };
    }
};

const SQLITE_TRANSIENT = @as(?*anyopaque, @ptrFromInt(@as(usize, @bitCast(@as(isize, -1)))));

pub fn Statement(comptime ArgsType: type, comptime RowType: type) type {
    return struct {
        const Self = @This();
        stmt: *c.sqlite3_stmt,

        pub fn finalize(self: *Self) void {
            _ = c.sqlite3_finalize(self.stmt);
        }

        pub fn reset(self: *Self) void {
            _ = c.sqlite3_reset(self.stmt);
        }

        pub fn bind(self: *Self, args: ArgsType) !void {
            const fields = std.meta.fields(ArgsType);
            inline for (fields) |field| {
                const name = ":" ++ field.name;
                const index = c.sqlite3_bind_parameter_index(self.stmt, name.ptr);
                if (index > 0) {
                    const value = @field(args, field.name);
                    try self.bindValue(index, value);
                }
            }
        }

        fn bindValue(self: *Self, index: c_int, value: anytype) !void {
            const T = @TypeOf(value);
            if (T == Text) {
                try checkCode(c.sqlite3_bind_text(self.stmt, index, value.data.ptr, @intCast(value.data.len), SQLITE_TRANSIENT));
            } else if (T == []const u8 or T == []u8) {
                try checkCode(c.sqlite3_bind_text(self.stmt, index, value.ptr, @intCast(value.len), SQLITE_TRANSIENT));
            } else if (T == ?[]const u8 or T == ?[]u8) {
                if (value) |val| {
                    try checkCode(c.sqlite3_bind_text(self.stmt, index, val.ptr, @intCast(val.len), SQLITE_TRANSIENT));
                } else {
                    try checkCode(c.sqlite3_bind_null(self.stmt, index));
                }
            } else if (T == ?Text) {
                if (value) |val| {
                    try checkCode(c.sqlite3_bind_text(self.stmt, index, val.data.ptr, @intCast(val.data.len), SQLITE_TRANSIENT));
                } else {
                    try checkCode(c.sqlite3_bind_null(self.stmt, index));
                }
            } else switch (@typeInfo(T)) {
                .int, .comptime_int => {
                    try checkCode(c.sqlite3_bind_int64(self.stmt, index, @intCast(value)));
                },
                .float, .comptime_float => {
                    try checkCode(c.sqlite3_bind_double(self.stmt, index, @floatCast(value)));
                },
                .null => {
                    try checkCode(c.sqlite3_bind_null(self.stmt, index));
                },
                .optional => {
                    if (value) |val| {
                        try self.bindValue(index, val);
                    } else {
                        try checkCode(c.sqlite3_bind_null(self.stmt, index));
                    }
                },
                else => @compileError("Unsupported type for binding: " ++ @typeName(T)),
            }
        }

        pub fn step(self: *Self) !?RowType {
            const rc = c.sqlite3_step(self.stmt);
            if (rc == c.SQLITE_DONE) return null;
            if (rc == c.SQLITE_ROW) {
                var row: RowType = undefined;
                const fields = std.meta.fields(RowType);
                inline for (fields, 0..) |field, col_idx| {
                    @field(row, field.name) = self.getColumn(col_idx, field.type);
                }
                return row;
            }
            try checkCode(rc);
            return null;
        }

        fn getColumn(self: Self, col_idx: usize, comptime T: type) T {
            if (T == Text) {
                if (c.sqlite3_column_text(self.stmt, @intCast(col_idx))) |ptr| {
                    const bytes_len = c.sqlite3_column_bytes(self.stmt, @intCast(col_idx));
                    return .{ .data = ptr[0..@intCast(bytes_len)] };
                }
                return .{ .data = "" };
            } else if (T == []const u8) {
                if (c.sqlite3_column_text(self.stmt, @intCast(col_idx))) |ptr| {
                    const bytes_len = c.sqlite3_column_bytes(self.stmt, @intCast(col_idx));
                    return ptr[0..@intCast(bytes_len)];
                }
                return "";
            } else if (T == ?Text) {
                if (c.sqlite3_column_type(self.stmt, @intCast(col_idx)) == c.SQLITE_NULL) return null;
                if (c.sqlite3_column_text(self.stmt, @intCast(col_idx))) |ptr| {
                    const bytes_len = c.sqlite3_column_bytes(self.stmt, @intCast(col_idx));
                    return .{ .data = ptr[0..@intCast(bytes_len)] };
                }
                return null;
            } else if (T == ?[]const u8) {
                if (c.sqlite3_column_type(self.stmt, @intCast(col_idx)) == c.SQLITE_NULL) return null;
                if (c.sqlite3_column_text(self.stmt, @intCast(col_idx))) |ptr| {
                    const bytes_len = c.sqlite3_column_bytes(self.stmt, @intCast(col_idx));
                    return ptr[0..@intCast(bytes_len)];
                }
                return null;
            } else switch (@typeInfo(T)) {
                .int => {
                    return @intCast(c.sqlite3_column_int64(self.stmt, @intCast(col_idx)));
                },
                .float => {
                    return @floatCast(c.sqlite3_column_double(self.stmt, @intCast(col_idx)));
                },
                .optional => |opt| {
                    if (c.sqlite3_column_type(self.stmt, @intCast(col_idx)) == c.SQLITE_NULL) return null;
                    return self.getColumn(col_idx, opt.child);
                },
                else => @compileError("Unsupported column type: " ++ @typeName(T)),
            }
        }
    };
}
