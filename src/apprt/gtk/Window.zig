/// A Window is a single, real GTK window that holds terminal surfaces.
///
/// A Window always contains a notebook (what GTK calls a tabbed container)
/// even while no tabs are in use, because a notebook without a tab bar has
/// no visible UI chrome.
const Window = @This();

const std = @import("std");
const builtin = @import("builtin");
const build_config = @import("../../build_config.zig");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const configpkg = @import("../../config.zig");
const font = @import("../../font/main.zig");
const input = @import("../../input.zig");
const CoreSurface = @import("../../Surface.zig");

const App = @import("App.zig");
const Color = configpkg.Config.Color;
const Surface = @import("Surface.zig");
const Tab = @import("Tab.zig");
const c = @import("c.zig").c;
const adwaita = @import("adwaita.zig");
const Notebook = @import("./notebook.zig").Notebook;

const log = std.log.scoped(.gtk);

app: *App,

/// Our window
window: *c.GtkWindow,

/// The notebook (tab grouping) for this window.
/// can be either c.GtkNotebook or c.AdwTabView.
notebook: Notebook,

context_menu: *c.GtkWidget,

pub fn create(alloc: Allocator, app: *App) !*Window {
    // Allocate a fixed pointer for our window. We try to minimize
    // allocations but windows and other GUI requirements are so minimal
    // compared to the steady-state terminal operation so we use heap
    // allocation for this.
    //
    // The allocation is owned by the GtkWindow created. It will be
    // freed when the window is closed.
    var window = try alloc.create(Window);
    errdefer alloc.destroy(window);
    try window.init(app);
    return window;
}

pub fn init(self: *Window, app: *App) !void {
    // Set up our own state
    self.* = .{
        .app = app,
        .window = undefined,
        .notebook = undefined,
        .context_menu = undefined,
    };

    // Create the window
    const adw_window =
        (comptime adwaita.versionAtLeast(1, 4, 0)) and
        adwaita.enabled(&app.config) and
        app.config.@"gtk-titlebar" and
        adwaita.versionAtLeast(1, 4, 0);
    const window: *c.GtkWidget = if (adw_window)
        c.adw_application_window_new(app.app)
    else
        c.gtk_application_window_new(app.app);

    const gtk_window: *c.GtkWindow = @ptrCast(window);
    errdefer if (adw_window) c.adw_application_window_destroy(window) else c.gtk_application_window_destroy(gtk_window);
    self.window = gtk_window;
    c.gtk_window_set_title(gtk_window, "Ghostty");
    c.gtk_window_set_default_size(gtk_window, 1000, 600);

    // GTK4 grabs F10 input by default to focus the menubar icon. We want
    // to disable this so that terminal programs can capture F10 (such as htop)
    c.gtk_window_set_handle_menubar_accel(gtk_window, 0);

    c.gtk_window_set_icon_name(gtk_window, "com.mitchellh.ghostty");

    // Apply background opacity if we have it
    if (app.config.@"background-opacity" < 1) {
        c.gtk_widget_set_opacity(@ptrCast(window), app.config.@"background-opacity");
    }

    var header: ?*c.GtkHeaderBar = null;

    // Internally, GTK ensures that only one instance of this provider exists in the provider list
    // for the display.
    const display = c.gdk_display_get_default();
    c.gtk_style_context_add_provider_for_display(display, @ptrCast(app.css_provider), c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

    // gtk-titlebar can be used to disable the header bar (but keep
    // the window manager's decorations). We create this no matter if we
    // are decorated or not because we can have a keybind to toggle the
    // decorations.
    if (app.config.@"gtk-titlebar") {
        header = @ptrCast(c.gtk_header_bar_new());
        {
            const btn = c.gtk_menu_button_new();
            c.gtk_widget_set_tooltip_text(btn, "Main Menu");
            c.gtk_menu_button_set_icon_name(@ptrCast(btn), "open-menu-symbolic");
            c.gtk_menu_button_set_menu_model(@ptrCast(btn), @ptrCast(@alignCast(app.menu)));
            c.gtk_header_bar_pack_end(@ptrCast(header), btn);
        }
        {
            const btn = c.gtk_button_new_from_icon_name("tab-new-symbolic");
            c.gtk_widget_set_tooltip_text(btn, "New Tab");
            c.gtk_header_bar_pack_end(@ptrCast(header), btn);
            _ = c.g_signal_connect_data(btn, "clicked", c.G_CALLBACK(&gtkTabNewClick), self, null, c.G_CONNECT_DEFAULT);
        }
    }

    // If we are disabling decorations then disable them right away.
    if (!app.config.@"window-decoration") {
        c.gtk_window_set_decorated(gtk_window, 0);
    }

    // Create our box which will hold our widgets.
    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);

    // In debug we show a warning and apply the 'devel' class to the window.
    // This is a really common issue where people build from source in debug and performance is really bad.
    if (comptime std.debug.runtime_safety) {
        const warning_text = "⚠️ You're running a debug build of Ghostty! Performance will be degraded.";
        if ((comptime adwaita.versionAtLeast(1, 3, 0)) and
            adwaita.enabled(&app.config) and
            adwaita.versionAtLeast(1, 3, 0))
        {
            const banner = c.adw_banner_new(warning_text);
            c.adw_banner_set_revealed(@ptrCast(banner), 1);
            c.gtk_box_append(@ptrCast(box), @ptrCast(banner));
        } else {
            const warning = c.gtk_label_new(warning_text);
            c.gtk_widget_set_margin_top(warning, 10);
            c.gtk_widget_set_margin_bottom(warning, 10);
            c.gtk_box_append(@ptrCast(box), warning);
        }
        c.gtk_widget_add_css_class(@ptrCast(gtk_window), "devel");
    }

    self.notebook = Notebook.create(self, box);

    self.context_menu = c.gtk_popover_menu_new_from_model(@ptrCast(@alignCast(self.app.context_menu)));
    c.gtk_widget_set_parent(self.context_menu, window);
    c.gtk_popover_set_has_arrow(@ptrCast(@alignCast(self.context_menu)), c.False);
    c.gtk_widget_set_halign(self.context_menu, c.GTK_ALIGN_START);

    // If we are in fullscreen mode, new windows start fullscreen.
    if (app.config.fullscreen) c.gtk_window_fullscreen(self.window);

    // All of our events
    _ = c.g_signal_connect_data(self.context_menu, "closed", c.G_CALLBACK(&gtkRefocusTerm), self, null, c.G_CONNECT_DEFAULT);
    _ = c.g_signal_connect_data(window, "close-request", c.G_CALLBACK(&gtkCloseRequest), self, null, c.G_CONNECT_DEFAULT);
    _ = c.g_signal_connect_data(window, "destroy", c.G_CALLBACK(&gtkDestroy), self, null, c.G_CONNECT_DEFAULT);

    // Our actions for the menu
    initActions(self);

    if ((comptime adwaita.versionAtLeast(1, 4, 0)) and
        adwaita.enabled(&app.config) and
        adwaita.versionAtLeast(1, 4, 0) and
        app.config.@"gtk-titlebar" and
        header != null)
    {
        const toolbar_view: *c.AdwToolbarView = @ptrCast(c.adw_toolbar_view_new());

        const header_widget: *c.GtkWidget = @ptrCast(@alignCast(header.?));
        c.adw_toolbar_view_add_top_bar(toolbar_view, header_widget);
        const tab_bar = c.adw_tab_bar_new();
        c.adw_tab_bar_set_view(tab_bar, self.notebook.adw_tab_view);

        if (!app.config.@"gtk-wide-tabs") c.adw_tab_bar_set_expand_tabs(tab_bar, 0);

        const tab_bar_widget: *c.GtkWidget = @ptrCast(@alignCast(tab_bar));
        switch (self.app.config.@"gtk-tabs-location") {
            // left and right is not supported in libadwaita.
            .top, .left, .right => c.adw_toolbar_view_add_top_bar(toolbar_view, tab_bar_widget),
            .bottom => c.adw_toolbar_view_add_bottom_bar(toolbar_view, tab_bar_widget),
        }
        c.adw_toolbar_view_set_content(toolbar_view, box);

        const toolbar_style: c.AdwToolbarStyle = switch (self.app.config.@"adw-toolbar-style") {
            .flat => c.ADW_TOOLBAR_FLAT,
            .raised => c.ADW_TOOLBAR_RAISED,
            .@"raised-border" => c.ADW_TOOLBAR_RAISED_BORDER,
        };
        c.adw_toolbar_view_set_top_bar_style(toolbar_view, toolbar_style);
        c.adw_toolbar_view_set_bottom_bar_style(toolbar_view, toolbar_style);

        c.adw_application_window_set_content(@ptrCast(gtk_window), @ptrCast(@alignCast(toolbar_view)));
    } else {
        // The box is our main child
        c.gtk_window_set_child(gtk_window, box);
        if (header) |h| c.gtk_window_set_titlebar(gtk_window, @ptrCast(@alignCast(h)));
    }

    // Show the window
    c.gtk_widget_show(window);
}

/// Sets up the GTK actions for the window scope. Actions are how GTK handles
/// menus and such. The menu is defined in App.zig but the action is defined
/// here. The string name binds them.
fn initActions(self: *Window) void {
    const actions = .{
        .{ "about", &gtkActionAbout },
        .{ "close", &gtkActionClose },
        .{ "new_window", &gtkActionNewWindow },
        .{ "new_tab", &gtkActionNewTab },
        .{ "split_right", &gtkActionSplitRight },
        .{ "split_down", &gtkActionSplitDown },
        .{ "toggle_inspector", &gtkActionToggleInspector },
        .{ "copy", &gtkActionCopy },
        .{ "paste", &gtkActionPaste },
        .{ "reset", &gtkActionReset },
    };

    inline for (actions) |entry| {
        const action = c.g_simple_action_new(entry[0], null);
        defer c.g_object_unref(action);
        _ = c.g_signal_connect_data(
            action,
            "activate",
            c.G_CALLBACK(entry[1]),
            self,
            null,
            c.G_CONNECT_DEFAULT,
        );
        c.g_action_map_add_action(@ptrCast(self.window), @ptrCast(action));
    }
}

pub fn deinit(self: *Window) void {
    c.gtk_widget_unparent(@ptrCast(self.context_menu));
}

/// Add a new tab to this window.
pub fn newTab(self: *Window, parent: ?*CoreSurface) !void {
    const alloc = self.app.core_app.alloc;
    _ = try Tab.create(alloc, self, parent);

    // TODO: When this is triggered through a GTK action, the new surface
    // redraws correctly. When it's triggered through keyboard shortcuts, it
    // does not (cursor doesn't blink) unless reactivated by refocusing.
}

/// Close the tab for the given notebook page. This will automatically
/// handle closing the window if there are no more tabs.
pub fn closeTab(self: *Window, tab: *Tab) void {
    self.notebook.closeTab(tab);
}

/// Returns true if this window has any tabs.
pub fn hasTabs(self: *const Window) bool {
    return self.notebook.nPages() > 0;
}

/// Go to the previous tab for a surface.
pub fn gotoPreviousTab(self: *Window, surface: *Surface) void {
    const tab = surface.container.tab() orelse {
        log.info("surface is not attached to a tab bar, cannot navigate", .{});
        return;
    };
    self.notebook.gotoPreviousTab(tab);
    self.focusCurrentTab();
}

/// Go to the next tab for a surface.
pub fn gotoNextTab(self: *Window, surface: *Surface) void {
    const tab = surface.container.tab() orelse {
        log.info("surface is not attached to a tab bar, cannot navigate", .{});
        return;
    };
    self.notebook.gotoNextTab(tab);
    self.focusCurrentTab();
}

/// Go to the next tab for a surface.
pub fn gotoLastTab(self: *Window) void {
    const max = self.notebook.nPages() -| 1;
    self.gotoTab(@intCast(max));
}

/// Go to the specific tab index.
pub fn gotoTab(self: *Window, n: usize) void {
    if (n == 0) return;
    const max = self.notebook.nPages();
    const page_idx = std.math.cast(c_int, n - 1) orelse return;
    if (page_idx < max) {
        self.notebook.gotoNthTab(page_idx);
        self.focusCurrentTab();
    }
}

/// Toggle fullscreen for this window.
pub fn toggleFullscreen(self: *Window, _: configpkg.NonNativeFullscreen) void {
    const is_fullscreen = c.gtk_window_is_fullscreen(self.window);
    if (is_fullscreen == 0) {
        c.gtk_window_fullscreen(self.window);
    } else {
        c.gtk_window_unfullscreen(self.window);
    }
}

/// Toggle the window decorations for this window.
pub fn toggleWindowDecorations(self: *Window) void {
    if (c.gtk_window_get_decorated(self.window) == 0) {
        c.gtk_window_set_decorated(self.window, 1);
    } else {
        c.gtk_window_set_decorated(self.window, 0);
    }
}

/// Grabs focus on the currently selected tab.
pub fn focusCurrentTab(self: *Window) void {
    const tab = self.notebook.currentTab() orelse return;
    const gl_area = @as(*c.GtkWidget, @ptrCast(tab.focus_child.gl_area));
    _ = c.gtk_widget_grab_focus(gl_area);
}

// Note: we MUST NOT use the GtkButton parameter because gtkActionNewTab
// sends an undefined value.
fn gtkTabNewClick(_: *c.GtkButton, ud: ?*anyopaque) callconv(.C) void {
    const self: *Window = @ptrCast(@alignCast(ud orelse return));
    const surface = self.actionSurface() orelse return;
    _ = surface.performBindingAction(.{ .new_tab = {} }) catch |err| {
        log.warn("error performing binding action error={}", .{err});
        return;
    };
}

fn gtkRefocusTerm(v: *c.GtkWindow, ud: ?*anyopaque) callconv(.C) bool {
    _ = v;
    log.debug("refocus term request", .{});
    const self = userdataSelf(ud.?);

    self.focusCurrentTab();

    return true;
}

fn gtkCloseRequest(v: *c.GtkWindow, ud: ?*anyopaque) callconv(.C) bool {
    _ = v;
    log.debug("window close request", .{});
    const self = userdataSelf(ud.?);

    // If none of our surfaces need confirmation, we can just exit.
    for (self.app.core_app.surfaces.items) |surface| {
        if (surface.container.window()) |window| {
            if (window == self and
                surface.core_surface.needsConfirmQuit()) break;
        }
    } else {
        c.gtk_window_destroy(self.window);
        return true;
    }

    // Setup our basic message
    const alert = c.gtk_message_dialog_new(
        self.window,
        c.GTK_DIALOG_MODAL,
        c.GTK_MESSAGE_QUESTION,
        c.GTK_BUTTONS_YES_NO,
        "Close this window?",
    );
    c.gtk_message_dialog_format_secondary_text(
        @ptrCast(alert),
        "All terminal sessions in this window will be terminated.",
    );

    // We want the "yes" to appear destructive.
    const yes_widget = c.gtk_dialog_get_widget_for_response(
        @ptrCast(alert),
        c.GTK_RESPONSE_YES,
    );
    c.gtk_widget_add_css_class(yes_widget, "destructive-action");

    // We want the "no" to be the default action
    c.gtk_dialog_set_default_response(
        @ptrCast(alert),
        c.GTK_RESPONSE_NO,
    );

    _ = c.g_signal_connect_data(alert, "response", c.G_CALLBACK(&gtkCloseConfirmation), self, null, c.G_CONNECT_DEFAULT);

    c.gtk_widget_show(alert);
    return true;
}

fn gtkCloseConfirmation(
    alert: *c.GtkMessageDialog,
    response: c.gint,
    ud: ?*anyopaque,
) callconv(.C) void {
    c.gtk_window_destroy(@ptrCast(alert));
    if (response == c.GTK_RESPONSE_YES) {
        const self = userdataSelf(ud.?);
        c.gtk_window_destroy(self.window);
    }
}

/// "destroy" signal for the window
fn gtkDestroy(v: *c.GtkWidget, ud: ?*anyopaque) callconv(.C) void {
    _ = v;
    log.debug("window destroy", .{});

    const self = userdataSelf(ud.?);
    const alloc = self.app.core_app.alloc;
    self.deinit();
    alloc.destroy(self);
}

fn gtkActionAbout(
    _: *c.GSimpleAction,
    _: *c.GVariant,
    ud: ?*anyopaque,
) callconv(.C) void {
    const self: *Window = @ptrCast(@alignCast(ud orelse return));

    c.gtk_show_about_dialog(
        self.window,
        "program-name",
        "Ghostty",
        "logo-icon-name",
        "com.mitchellh.ghostty",
        "title",
        "About Ghostty",
        "version",
        build_config.version_string.ptr,
        "website",
        "https://github.com/ghostty-org/ghostty",
        @as(?*anyopaque, null),
    );
}

fn gtkActionClose(
    _: *c.GSimpleAction,
    _: *c.GVariant,
    ud: ?*anyopaque,
) callconv(.C) void {
    const self: *Window = @ptrCast(@alignCast(ud orelse return));
    const surface = self.actionSurface() orelse return;
    _ = surface.performBindingAction(.{ .close_surface = {} }) catch |err| {
        log.warn("error performing binding action error={}", .{err});
        return;
    };
}

fn gtkActionNewWindow(
    _: *c.GSimpleAction,
    _: *c.GVariant,
    ud: ?*anyopaque,
) callconv(.C) void {
    const self: *Window = @ptrCast(@alignCast(ud orelse return));
    const surface = self.actionSurface() orelse return;
    _ = surface.performBindingAction(.{ .new_window = {} }) catch |err| {
        log.warn("error performing binding action error={}", .{err});
        return;
    };
}

fn gtkActionNewTab(
    _: *c.GSimpleAction,
    _: *c.GVariant,
    ud: ?*anyopaque,
) callconv(.C) void {
    // We can use undefined because the button is not used.
    gtkTabNewClick(undefined, ud);
}

fn gtkActionSplitRight(
    _: *c.GSimpleAction,
    _: *c.GVariant,
    ud: ?*anyopaque,
) callconv(.C) void {
    const self: *Window = @ptrCast(@alignCast(ud orelse return));
    const surface = self.actionSurface() orelse return;
    _ = surface.performBindingAction(.{ .new_split = .right }) catch |err| {
        log.warn("error performing binding action error={}", .{err});
        return;
    };
}

fn gtkActionSplitDown(
    _: *c.GSimpleAction,
    _: *c.GVariant,
    ud: ?*anyopaque,
) callconv(.C) void {
    const self: *Window = @ptrCast(@alignCast(ud orelse return));
    const surface = self.actionSurface() orelse return;
    _ = surface.performBindingAction(.{ .new_split = .down }) catch |err| {
        log.warn("error performing binding action error={}", .{err});
        return;
    };
}

fn gtkActionToggleInspector(
    _: *c.GSimpleAction,
    _: *c.GVariant,
    ud: ?*anyopaque,
) callconv(.C) void {
    const self: *Window = @ptrCast(@alignCast(ud orelse return));
    const surface = self.actionSurface() orelse return;
    _ = surface.performBindingAction(.{ .inspector = .toggle }) catch |err| {
        log.warn("error performing binding action error={}", .{err});
        return;
    };
}

fn gtkActionCopy(
    _: *c.GSimpleAction,
    _: *c.GVariant,
    ud: ?*anyopaque,
) callconv(.C) void {
    const self: *Window = @ptrCast(@alignCast(ud orelse return));
    const surface = self.actionSurface() orelse return;
    _ = surface.performBindingAction(.{ .copy_to_clipboard = {} }) catch |err| {
        log.warn("error performing binding action error={}", .{err});
        return;
    };
}

fn gtkActionPaste(
    _: *c.GSimpleAction,
    _: *c.GVariant,
    ud: ?*anyopaque,
) callconv(.C) void {
    const self: *Window = @ptrCast(@alignCast(ud orelse return));
    const surface = self.actionSurface() orelse return;
    _ = surface.performBindingAction(.{ .paste_from_clipboard = {} }) catch |err| {
        log.warn("error performing binding action error={}", .{err});
        return;
    };
}

fn gtkActionReset(
    _: *c.GSimpleAction,
    _: *c.GVariant,
    ud: ?*anyopaque,
) callconv(.C) void {
    const self: *Window = @ptrCast(@alignCast(ud orelse return));
    const surface = self.actionSurface() orelse return;
    _ = surface.performBindingAction(.{ .reset = {} }) catch |err| {
        log.warn("error performing binding action error={}", .{err});
        return;
    };
}

/// Returns the surface to use for an action.
fn actionSurface(self: *Window) ?*CoreSurface {
    const tab = self.notebook.currentTab() orelse return null;
    return &tab.focus_child.core_surface;
}

fn userdataSelf(ud: *anyopaque) *Window {
    return @ptrCast(@alignCast(ud));
}
