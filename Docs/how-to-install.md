[< Documentation](README.md)

# 📦 How to install

### Introduction

There were four ways to install the previous version:

1. **Package managers**:
    1. 🌱 **Mint**. Allows selecting any git reference, cloning it, and building Rugby from\
    source code. There are two disadvantages. First of all, users should have the right Xcode\
    version and CLT. It’s not so convenient. Sometimes users have to use older Xcode versions.\
    And it also limits me from upgrading to the latest version and using the newest features\
    for development. The second problem is I’m not ready to publish the source code of the new version;
    2. 🍺 **Brew**. Allows to download only the latest Rugby binary and only from the default branch.\
    It’s not suitable for the distribution of pre-release versions. And users can’t get the previous\
    version if the latest one is broken.
2. **W/o package managers**:
    1. 📑 **Source**. Everybody can clone any git reference without package managers and build Rugby from\
    the source. There is only one problem — I’m not ready to share the source code of the new version 😅;
    2. 📦 **Binary**. Everybody can download a zip file, unarchive it and use the Rugby binary.\
    It’s pretty easy, but still, users have to call a bunch of commands, like adding Rugby location\
    to the `$PATH` environment variable.

I thought about all these options and decided that there should be a better way to install Rugby.\
And I found it. Maybe it’s not ideal, but it’s good enough.

It’s all about downloading binary. The first-time users should install it manually, and after that,\
they can use the new command `rugby update` for Rugby self-updating. It’s similar to the package manager,\
but it's right inside Rugby.

<br>

## First Install (zsh)

First of all, if you have the first version Rugby 1.x, you need to delete it.\
Then call `where rugby` command and be sure that there are no any of paths to rugby.

#### Running script (Recommended) 🚀

For the official SwiftyFinch version:
```sh
curl -Ls https://swiftyfinch.github.io/rugby/install.sh | bash
```

For the `thorprogramador/rugby-ios` fork (ensure the `RELEASE_TAG` in the script points to a valid release with assets on this fork):
```sh
curl -Ls https://raw.githubusercontent.com/thorprogramador/rugby-ios/main/releases/install.sh | bash
```

<hr>
</p>
</details>

<details><summary><code>arm64 (M1+)</code></summary>
<p>

```bash
curl -LO https://github.com/swiftyfinch/Rugby/releases/download/2.0.0/arm64.zip
```

```bash
unzip arm64.zip
```

<hr>
</p>
</details>

```bash
cp rugby ~/.rugby/clt
```

```bash
echo '\nexport PATH=$PATH:~/.rugby/clt' >> ~/.zshrc
```
Open a new window or tab in terminal.

<br>

## Self-Update

If you already have Rugby, which version is at least `2.0.0b2`, you can use such a command.\
But it will work only if you install rugby to `~/.rugby/clt/rugby` path as I recommended above.

Getting the latest version including pre-release ones:

```bash
> rugby update --beta
```

If you want to install a specific version:

```bash
> rugby update --version 2.0.0
```

If you want to find out which versions are available:

```bash
> rugby update list
```

<br>

## Install in CI Environment

You can install Rugby with common `curl` and `unzip` commands.\
For example, check out [this workflow file](https://github.com/swiftyfinch/Rugby/blob/main/.github/workflows/checks.yml#L18) of Rugby regress.

---
<br>

🚀 I hope you successfully installed Rugby!\
Contact me if you have any questions.

Now, you can find more information in [> Commands Help](commands-help/README.md) 📚.\
If you used the previous version, there is [> Migration Guide](migration-guide.md) 🚏.
