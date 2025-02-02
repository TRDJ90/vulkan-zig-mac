A small test project for future references it uses the https://github.com/Snektron/vulkan-zig example triangle code.
But the glfw3 lib is replaced with zig-gamedev zglfw and made it runnable on macos.
To make the triangle example run on mac we need to set the correct vulkan instance and device extensions. 

compiled with zig verions: 0.14.0-dev.2851+b074fb7dd

builds debug build and run it.
```
  zig build run
```


If just is installed we can use these commands

runs debug build
```
  just run
```

runs release safe build
```
  just release
```
