const vk = @import("vulkan");

const base_commands: vk.BaseCommandFlags = .{
    .createInstance = true,
    .getInstanceProcAddr = true,
    .enumerateInstanceLayerProperties = true,
};

const instance_commands: vk.InstanceCommandFlags = .{
    .createDevice = true,
    .destroyInstance = true,
    .enumeratePhysicalDevices = true,
    .getDeviceProcAddr = true,
    .getPhysicalDeviceProperties = true,
    .getPhysicalDeviceFeatures = true,
    .getPhysicalDeviceQueueFamilyProperties = true,
    .enumerateDeviceExtensionProperties = true,
    .getPhysicalDeviceMemoryProperties = true,
};

const device_commands: vk.DeviceCommandFlags = .{
    .destroyDevice = true,
    .getDeviceQueue = true,
    .queueSubmit = true,
    .queueWaitIdle = true,
    .deviceWaitIdle = true,
    .allocateMemory = true,
    .freeMemory = true,
    .mapMemory = true,
    .unmapMemory = true,
    .getBufferMemoryRequirements = true,
    .bindBufferMemory = true,
    .createFence = true,
    .destroyFence = true,
    .destroyBuffer = true,
    .createImageView = true,
    .resetFences = true,
    .waitForFences = true,
    .createSemaphore = true,
    .destroySemaphore = true,
    .createBuffer = true,
    .destroyImageView = true,
    .createShaderModule = true,
    .destroyShaderModule = true,
    .createGraphicsPipelines = true,
    .destroyPipeline = true,
    .createPipelineLayout = true,
    .destroyPipelineLayout = true,
    .createFramebuffer = true,
    .destroyFramebuffer = true,
    .createRenderPass = true,
    .destroyRenderPass = true,
    .createCommandPool = true,
    .destroyCommandPool = true,
    .allocateCommandBuffers = true,
    .freeCommandBuffers = true,
    .beginCommandBuffer = true,
    .endCommandBuffer = true,
    .cmdBindPipeline = true,
    .cmdSetViewport = true,
    .cmdSetScissor = true,
    .cmdDraw = true,
    .cmdCopyBuffer = true,
    .cmdBeginRenderPass = true,
    .cmdEndRenderPass = true,
    .cmdBindVertexBuffers = true,
};

pub const apis: []const vk.ApiInfo = &.{
    .{
        .base_commands = base_commands,
        .instance_commands = instance_commands,
        .device_commands = device_commands,
    },
    vk.extensions.khr_surface,
    vk.extensions.khr_swapchain,
};

pub const BaseDispatcher = vk.BaseWrapper(apis);
pub const InstanceDispatcher = vk.InstanceWrapper(apis);
pub const DeviceDispatcher = vk.DeviceWrapper(apis);

pub const Instance = vk.InstanceProxy(apis);
pub const Device = vk.DeviceProxy(apis);
pub const CommandBuffer = vk.CommandBufferProxy(apis);
