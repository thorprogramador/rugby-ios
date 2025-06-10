# Rebuild Command

The `rebuild` command allows you to rebuild specific podspecs even when the project is already using Rugby. This is particularly useful when developers modify local podspecs and need to rebuild and cache them without encountering the "project is already using Rugby" error.

## Usage

```bash
rugby build rebuild [options]
```

## Options

- `-t, --targets <targets>`: Target names to select. Empty means all targets.
- `-g, --targets-as-regex <patterns>`: Regular expression patterns to select targets.
- `-e, --except <targets>`: Target names to exclude.
- `-x, --except-as-regex <patterns>`: Regular expression patterns to exclude targets.
- `--try`: Run command in mode where only selected targets are printed.
- `-s, --sdk <sdk>`: Build SDK: sim or ios. Default: sim.
- `-a, --arch <arch>`: Build architecture: auto, x86_64 or arm64. Default: auto.
- `-c, --config <config>`: Build configuration. Default: Debug.
- `--ignore-cache`: Ignore shared cache.
- `--result-bundle-path <path>`: Path to xcresult bundle.
- `-o, --output <output>`: Output type: auto, simple or json. Default: auto.
- `-l, --log-level <level>`: Log level: verbose, info, warning, error or silent. Default: info.

## Examples

Rebuild a specific podspec:

```bash
rugby build rebuild -t BaseFeatureInterface
```

Rebuild multiple podspecs:

```bash
rugby build rebuild -t BaseFeatureInterface -t AnotherPodspec
```

Rebuild podspecs matching a pattern:

```bash
rugby build rebuild -g "Base.*Interface"
```

## Notes

- This command will work even when the project is already using Rugby.
- After rebuilding, the command will ensure the project is still using Rugby binaries.
