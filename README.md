<div align="center">
  
# Zigu

Yet another (Zig) (u)pdater

# Dependencies

</div>

### Runtime

- `tar` for extracting compressed archive (Runtime)

### Build

> No build dependencies other than `Zig compiler`

# <div align="center">Usage</div>


```pwsh
 Usage:
      zigu <command>

 Commands:
      list                    Show all available versions
      latest                  Install latest stable version
      nightly | master        Install latest nightly version
      [version]               Install specified version.
                              Will resolve to a latest version with the provided prefix
      help                    Show this help message

 Examples:
      zigu latest

      zigu 0                  Will resolve to latest 0.x.x version (i.e. 0.11.0) if any
      zigu 0.10               Will resolve to latest 0.10 version (i.e. 0.10.1) if any
      zigu 1                  Will resolve to latest 1.x.x version if any
```

# Screenshot

![image](https://github.com/Meonako/zigu/assets/76484203/82a45b53-8440-47a6-a4ee-86ba60bb95d6)
