const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");

const VulkanTypes = @import("vulkan_types.zig");
const BaseDispatch = VulkanTypes.BaseDispatcher;
const InstanceDispatch = VulkanTypes.InstanceDispatcher;

pub const VulkanLoader = struct {
    const dll_names = switch (builtin.os.tag) {
        .windows => &[_][]const u8{
            "vulkan-1.dll",
        },
        .ios, .macos, .tvos, .watchos => &[_][]const u8{
            "libvulkan.dylib",
            "libvulkan.1.dylib",
            "libMoltenVK.dylib",
        },
        .linux => &[_][]const u8{
            "libvulkan.so.1",
            "libvulkan.so",
        },
        else => &[_][]const u8{
            "libvulkan.so.1",
            "libvulkan.so",
        },
    };

    handle: std.DynLib,
    get_instance_proc_addr: vk.PfnGetInstanceProcAddr,

    pub fn loadVulkan() !VulkanLoader {
        var handle: std.DynLib = undefined;
        var get_instance_proc_addr: vk.PfnGetInstanceProcAddr = undefined;

        for (dll_names) |name| {
            if (std.DynLib.open(name)) |library| {
                handle = library;
                break;
            } else |err| {
                std.log.err("{any}", .{err});
            }
        }

        errdefer handle.close();
        get_instance_proc_addr = handle.lookup(vk.PfnGetInstanceProcAddr, "vkGetInstanceProcAddr") orelse return error.LoadVulkanFailed;

        return VulkanLoader{
            .handle = handle,
            .get_instance_proc_addr = get_instance_proc_addr,
        };
    }
};

const severity_info = vk.DebugUtilsMessageSeverityFlagsEXT{ .info_bit_ext = true };
const severity_erro = vk.DebugUtilsMessageSeverityFlagsEXT{ .error_bit_ext = true };
const severity_warn = vk.DebugUtilsMessageSeverityFlagsEXT{ .warning_bit_ext = true };
const severity_verb = vk.DebugUtilsMessageSeverityFlagsEXT{ .verbose_bit_ext = true };

pub fn CreateDefaultDebugUtilsCreateInfo() vk.DebugUtilsMessengerCreateInfoEXT {
    const ci: vk.DebugUtilsMessengerCreateInfoEXT = .{
        .s_type = vk.StructureType.debug_utils_messenger_create_info_ext,
        .message_severity = vk.DebugUtilsMessageSeverityFlagsEXT{
            .warning_bit_ext = true,
            .info_bit_ext = true,
            .error_bit_ext = true,
            .verbose_bit_ext = true,
        },
        .message_type = vk.DebugUtilsMessageTypeFlagsEXT{
            .general_bit_ext = true,
            .validation_bit_ext = true,
            .performance_bit_ext = true,
        },
        .pfn_user_callback = debugCallBack,
        .p_user_data = null,
    };

    return ci;
}

pub fn createDebugUtilsMessenger(
    base_dispatcher: BaseDispatch,
    instance: vk.Instance,
    create_info: *vk.DebugUtilsMessengerCreateInfoEXT,
    debug_messenger: *vk.DebugUtilsMessengerEXT,
) void {
    const func: vk.PfnCreateDebugUtilsMessengerEXT = @ptrCast(base_dispatcher.getInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));
    _ = func(instance, create_info, null, debug_messenger);
}

pub fn destroyDebugUtilsMessenger(base_dispatcher: BaseDispatch, instance: vk.Instance, debug_messenger: vk.DebugUtilsMessengerEXT) void {
    const func: vk.PfnDestroyDebugUtilsMessengerEXT = @ptrCast(base_dispatcher.getInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"));
    _ = func(instance, debug_messenger, null);
}

pub fn debugCallBack(
    severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_type: vk.DebugUtilsMessageTypeFlagsEXT,
    cb_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    user_data: ?*anyopaque,
) callconv(.c) vk.Bool32 {
    // TODO: Do something with this data....
    _ = message_type;
    _ = user_data;

    const data = cb_data orelse null;
    if (data == null) {
        return vk.FALSE;
    }

    const message_severity = severity.toInt();
    switch (message_severity) {
        0...severity_info.toInt() => {
            std.log.info("{?s}", .{data.?.p_message});
        },
        severity_info.toInt() + 1...severity_warn.toInt() => {
            std.log.warn("{?s}", .{data.?.p_message});
        },
        severity_warn.toInt() + 1...severity_erro.toInt() => {
            std.log.err("{?s}", .{data.?.p_message});
        },
        else => {
            std.log.info("{?s}", .{data.?.p_message});
        },
    }

    // Application code should always return VK_FALSE
    return vk.FALSE;
}
