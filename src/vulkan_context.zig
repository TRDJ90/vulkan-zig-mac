const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const zglfw = @import("zglfw");
const vulkan_util = @import("vulkan_util.zig");
const VulkanTypes = @import("vulkan_types.zig");

const BaseDispatcher = VulkanTypes.BaseDispatcher;
const InstanceDispatcher = VulkanTypes.InstanceDispatcher;
const DeviceDispatcher = VulkanTypes.DeviceDispatcher;

const Instance = VulkanTypes.Instance;
const Device = VulkanTypes.Device;

const Allocator = std.mem.Allocator;
const VulkanLoader = vulkan_util.VulkanLoader;

const required_device_extensions = [_][*:0]const u8{
    vk.extensions.khr_swapchain.name,
    vk.extensions.khr_portability_subset.name,
};

const validation_layers = [_][]const u8{
    "VK_LAYER_KHRONOS_validation",
};

pub const InstanceConfig = struct {
    app_name: [*:0]const u8,
    engine_name: [*:0]const u8,
    use_default_debug_messenger: bool,
    use_debug_messenger: bool,
};

pub const GraphicsContext = struct {
    pub const CommandBuffer = VulkanTypes.CommandBuffer;

    allocator: Allocator,

    vkb: VulkanTypes.BaseDispatcher,

    instance: VulkanTypes.Instance,
    surface: vk.SurfaceKHR,
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    mem_props: vk.PhysicalDeviceMemoryProperties,

    dev: VulkanTypes.Device,
    graphics_queue: Queue,
    present_queue: Queue,

    debug_messenger: vk.DebugUtilsMessengerEXT,
    debug_messenger_used: bool = false,

    pub fn init(allocator: Allocator, config: InstanceConfig, window: *zglfw.Window) !GraphicsContext {
        const vulkan_loader = try VulkanLoader.loadVulkan();

        var self: GraphicsContext = undefined;
        self.allocator = allocator;
        self.vkb = try BaseDispatcher.load(vulkan_loader.get_instance_proc_addr);

        const glfw_exts = try zglfw.getRequiredInstanceExtensions();
        _ = glfw_exts;

        var extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, 4);
        defer extensions.deinit();

        // Add OS specific instance extensions.
        switch (builtin.target.os.tag) {
            .macos => {
                try extensions.append(vk.extensions.ext_metal_surface.name);
                try extensions.append(vk.extensions.khr_portability_enumeration.name);
            },
            .windows => {
                try extensions.append(vk.extensions.khr_win_32_surface.name);
            },
            .linux => {
                try extensions.append(vk.extensions.khr_xcb_surface.name);
                try extensions.append(vk.extensions.khr_xlib_surface.name);
                try extensions.append(vk.extensions.khr_wayland_surface.name);
            },
            else => {
                std.log.err("Unsupported platform/os", .{});
            },
        }

        if (config.use_debug_messenger) {
            try extensions.append(vk.extensions.ext_debug_utils.name);
        }

        try extensions.append(vk.extensions.khr_surface.name);

        const app_info = vk.ApplicationInfo{
            .p_application_name = config.app_name,
            .application_version = vk.makeApiVersion(0, 0, 0, 0),
            .p_engine_name = config.engine_name,
            .engine_version = vk.makeApiVersion(0, 0, 0, 0),
            .api_version = vk.API_VERSION_1_3,
        };

        var instance_ci: vk.InstanceCreateInfo = .{
            .p_application_info = &app_info,
            .enabled_extension_count = @intCast(extensions.items.len),
            .pp_enabled_extension_names = @ptrCast(extensions.items),
            .enabled_layer_count = @intCast(validation_layers.len),
            .pp_enabled_layer_names = @ptrCast(&validation_layers),
            .flags = vk.InstanceCreateFlags{
                .enumerate_portability_bit_khr = true,
            },
        };

        if (config.use_default_debug_messenger) {
            var default_debug_messenger_ci: vk.DebugUtilsMessengerCreateInfoEXT = .{
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
                .pfn_user_callback = vulkan_util.debugCallBack,
                .p_user_data = null,
            };
            instance_ci.p_next = @as(*vk.DebugUtilsMessengerCreateInfoEXT, &default_debug_messenger_ci);
            // TODO: should add debug layer over here.
        }

        const instance = try self.vkb.createInstance(@ptrCast(&instance_ci), null);

        const vki = try allocator.create(InstanceDispatcher);
        errdefer allocator.destroy(vki);
        vki.* = try InstanceDispatcher.load(instance, self.vkb.dispatch.vkGetInstanceProcAddr);
        self.instance = Instance.init(instance, vki);
        errdefer self.instance.destroyInstance(null);

        // Initialize debug messenger.
        var debug_messenger: vk.DebugUtilsMessengerEXT = undefined;
        if (config.use_debug_messenger) {
            var debug_messenger_ci = vulkan_util.CreateDefaultDebugUtilsCreateInfo();
            vulkan_util.createDebugUtilsMessenger(self.vkb, instance, &debug_messenger_ci, &debug_messenger);
            self.debug_messenger = debug_messenger;
            self.debug_messenger_used = true;
        }
        errdefer vulkan_util.destroyDebugUtilsMessenger(self.vkb, instance, debug_messenger);

        // Initialize surface.
        self.surface = try createSurface(self.instance, window);
        errdefer self.instance.destroySurfaceKHR(self.surface, null);

        // Select candidate physical device.
        const candidate = try pickPhysicalDevice(self.instance, allocator, self.surface);
        self.pdev = candidate.pdev;
        self.props = candidate.props;

        const dev = try initializeCandidate(self.instance, candidate);

        const vkd = try allocator.create(DeviceDispatcher);
        errdefer allocator.destroy(vkd);
        vkd.* = try DeviceDispatcher.load(dev, self.instance.wrapper.dispatch.vkGetDeviceProcAddr);
        self.dev = Device.init(dev, vkd);
        errdefer self.dev.destroyDevice(null);

        self.graphics_queue = Queue.init(self.dev, candidate.queues.graphics_family);
        self.present_queue = Queue.init(self.dev, candidate.queues.present_family);

        self.mem_props = self.instance.getPhysicalDeviceMemoryProperties(self.pdev);

        return self;
    }

    pub fn deinit(self: GraphicsContext) void {
        self.dev.destroyDevice(null);
        self.instance.destroySurfaceKHR(self.surface, null);

        if (self.debug_messenger_used) {
            vulkan_util.destroyDebugUtilsMessenger(self.vkb, self.instance.handle, self.debug_messenger);
        }

        self.instance.destroyInstance(null);

        // Don't forget to free the tables to prevent a memory leak.
        self.allocator.destroy(self.dev.wrapper);
        self.allocator.destroy(self.instance.wrapper);
    }

    pub fn deviceName(self: *const GraphicsContext) []const u8 {
        return std.mem.sliceTo(&self.props.device_name, 0);
    }

    pub fn findMemoryTypeIndex(self: GraphicsContext, memory_type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
        for (self.mem_props.memory_types[0..self.mem_props.memory_type_count], 0..) |mem_type, i| {
            if (memory_type_bits & (@as(u32, 1) << @truncate(i)) != 0 and mem_type.property_flags.contains(flags)) {
                return @truncate(i);
            }
        }

        return error.NoSuitableMemoryType;
    }

    pub fn allocate(self: GraphicsContext, requirements: vk.MemoryRequirements, flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
        return try self.dev.allocateMemory(&.{
            .allocation_size = requirements.size,
            .memory_type_index = try self.findMemoryTypeIndex(requirements.memory_type_bits, flags),
        }, null);
    }
};

pub const Queue = struct {
    handle: vk.Queue,
    family: u32,

    fn init(device: Device, family: u32) Queue {
        return .{
            .handle = device.getDeviceQueue(family, 0),
            .family = family,
        };
    }
};

fn createSurface(instance: Instance, window: *zglfw.Window) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;
    if (glfwCreateWindowSurface(instance.handle, window, null, &surface) != .success) {
        return error.SurfaceInitFailed;
    }

    return surface;
}

fn initializeCandidate(instance: Instance, candidate: DeviceCandidate) !vk.Device {
    const priority = [_]f32{1};
    const qci = [_]vk.DeviceQueueCreateInfo{
        .{
            .queue_family_index = candidate.queues.graphics_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
        .{
            .queue_family_index = candidate.queues.present_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
    };

    const queue_count: u32 = if (candidate.queues.graphics_family == candidate.queues.present_family)
        1
    else
        2;

    return try instance.createDevice(candidate.pdev, &.{
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &qci,
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = @ptrCast(&required_device_extensions),
    }, null);
}

const DeviceCandidate = struct {
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    queues: QueueAllocation,
};

const QueueAllocation = struct {
    graphics_family: u32,
    present_family: u32,
};

fn pickPhysicalDevice(
    instance: Instance,
    allocator: Allocator,
    surface: vk.SurfaceKHR,
) !DeviceCandidate {
    const pdevs = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(pdevs);

    for (pdevs) |pdev| {
        if (try checkSuitable(instance, pdev, allocator, surface)) |candidate| {
            return candidate;
        }
    }

    return error.NoSuitableDevice;
}

fn checkSuitable(
    instance: Instance,
    pdev: vk.PhysicalDevice,
    allocator: Allocator,
    surface: vk.SurfaceKHR,
) !?DeviceCandidate {
    if (!try checkExtensionSupport(instance, pdev, allocator)) {
        return null;
    }

    if (!try checkSurfaceSupport(instance, pdev, surface)) {
        return null;
    }

    if (try allocateQueues(instance, pdev, allocator, surface)) |allocation| {
        const props = instance.getPhysicalDeviceProperties(pdev);
        return DeviceCandidate{
            .pdev = pdev,
            .props = props,
            .queues = allocation,
        };
    }

    return null;
}

fn allocateQueues(instance: Instance, pdev: vk.PhysicalDevice, allocator: Allocator, surface: vk.SurfaceKHR) !?QueueAllocation {
    const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
    defer allocator.free(families);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);

        if (graphics_family == null and properties.queue_flags.graphics_bit) {
            graphics_family = family;
        }

        if (present_family == null and (try instance.getPhysicalDeviceSurfaceSupportKHR(pdev, family, surface)) == vk.TRUE) {
            present_family = family;
        }
    }

    if (graphics_family != null and present_family != null) {
        return QueueAllocation{
            .graphics_family = graphics_family.?,
            .present_family = present_family.?,
        };
    }

    return null;
}

fn checkSurfaceSupport(instance: Instance, pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR) !bool {
    var format_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &format_count, null);

    var present_mode_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(pdev, surface, &present_mode_count, null);

    return format_count > 0 and present_mode_count > 0;
}

fn checkExtensionSupport(
    instance: Instance,
    pdev: vk.PhysicalDevice,
    allocator: Allocator,
) !bool {
    const propsv = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator);
    defer allocator.free(propsv);

    for (required_device_extensions) |ext| {
        for (propsv) |props| {
            if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&props.extension_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }

    return true;
}

// usually the GLFW vulkan functions are exported if vulkan is included,
// but since that's not the case here, they are manually imported.
pub extern fn glfwGetPhysicalDevicePresentationSupport(instance: vk.Instance, pdev: vk.PhysicalDevice, queuefamily: u32) c_int;
pub extern fn glfwCreateWindowSurface(instance: vk.Instance, window: *zglfw.Window, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;
