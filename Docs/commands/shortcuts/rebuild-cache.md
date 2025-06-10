# Rebuild-Cache Command

The `rebuild-cache` command is a shortcut that combines the `rebuild` and `use` commands. It allows you to rebuild and cache specific podspecs even when the project is already using Rugby, which is particularly useful when developers modify local podspecs.

## Usage

```bash
rugby rebuild-cache [options]
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
- `-r, --rollback`: Restore projects state before the last Rugby usage.
- `--ignore-cache`: Ignore shared cache.
- `--result-bundle-path <path>`: Path to xcresult bundle.
- `--delete-sources`: Delete target groups from project.
- `--archive-type <type>`: Binary archive file type to use: zip or 7z. Default: zip.
- `-o, --output <output>`: Output type: auto, simple or json. Default: auto.
- `-l, --log-level <level>`: Log level: verbose, info, warning, error or silent. Default: info.

## Examples

Rebuild and cache a specific podspec:

```bash
rugby rebuild-cache -t BaseFeatureInterface
```

Rebuild and cache multiple podspecs:

```bash
rugby rebuild-cache -t BaseFeatureInterface -t AnotherPodspec
```

Rebuild and cache podspecs matching a pattern:

```bash
rugby rebuild-cache -g "Base.*Interface"
```

## Notes

- This command will work even when the project is already using Rugby.
- After rebuilding, the command will ensure the project is still using Rugby binaries.
- This is the recommended command for rebuilding and caching modified local podspecs.
