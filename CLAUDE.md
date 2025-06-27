# Rugby Build Commands Guide

## rugby build full vs rugby build pre

### rugby build full
Builds complete targets with all build phases (sources, resources, scripts) and supports caching.

**When to use:**
- Normal development (90% of the time)
- When your pods don't have code generation scripts
- For fresh/clean builds: `rugby build full --ignore-cache`
- In CI/CD pipelines for complete binaries

**Examples of pods that only need full:**
- Alamofire, SnapKit, RxSwift (most third-party libraries)
- Pods without code generation scripts

### rugby build pre
Runs only pre-source build phases (like code generation scripts) while ignoring actual source compilation.

**When to use:**
- When pods have code generation that runs BEFORE source compilation
- For pods using: SwiftGen, Sourcery, R.swift, Apollo GraphQL, Protobuf/gRPC
- When you see build scripts with `execution_position: :before_compile`

### Common Workflow
If you have code generation:
```bash
rugby build pre    # Generate code first
rugby build full   # Then build everything
```

### Quick Decision Guide
**Do your pods generate code?**
- ❌ No → Use `rugby build full` directly
- ✅ Yes → Use `rugby build pre` first, then `rugby build full`

### Why prebuild exists
Without prebuild, Rugby would:
1. Calculate target hash before code generation
2. Generate new source files during build
3. End up with a different hash than expected
4. Be unable to reuse cached binaries

Prebuild ensures all generated code exists before calculating hashes, making caching reliable.

### Local Podspecs
Check your podspec's `script_phases`:
- If they create `.swift` files → Use `pre` then `full`
- If they copy resources or do post-processing → Use only `full`

When in doubt, running both won't hurt - prebuild will skip targets without pre-compile scripts.