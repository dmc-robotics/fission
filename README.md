## WARNING: Beta Software
This code is a hobby project, a work in progress, and should be considered beta software. It has only been lightly tested. Like any CNC code, its output should be verified with a simulator and/or on your machine before trusting the code.

# Fission

Fission combines separate [Fusion 360](https://www.autodesk.com/products/fusion-360) CNC files into a single G-code program for the [Makera Carvera](https://www.makera.com/).

The free version of Fusion 360 doesn't support tool changers or 4th axis machining. Fission works around these limitations by stitching together multiple operations into one program that's ready to send to your Carvera.

## What It Does

**Tool changes** — Combine multiple Fusion setups that use different tools into a single file. Fission strips the duplicate headers and footers and produces a unified program with proper tool change commands (`T<n> M6`).

**4th axis rotations** — Combine setups with A-axis rotations in between. Fission inserts the rotation commands (`G0 A<angle>`) with automatic spindle stop and Z retract for safety, so you can machine multiple faces of a part without manually editing G-code.

## Installation

This gem is not yet on Rubygems. You have to build and install it locally:

```bash
# from the gem's root directory:
gem build fission.gemspec
gem install fission-0.2.0.gem

```

## Usage

### Combining files

Arguments are a free-form mix of files and angles. Numbers are treated as A-axis rotation commands; everything else is a file path. Files are concatenated in order, keeping the header from the first file and the footer from the last.

```bash
# Simple tool change — just list the files
fission combine -o merged.nc roughing.nc finishing.nc

# Any number of files
fission combine -o merged.nc op1.nc op2.nc op3.nc op4.nc

# 4th axis — numbers are rotation angles inserted between files
fission combine -o part.nc front.nc 90 right.nc 180 back.nc 270 left.nc

# Multiple operations per face, then rotate
fission combine -o part.nc front_rough.nc front_finish.nc 90 right_rough.nc right_finish.nc

# Decimal angles
fission combine -o part.nc front.nc 45.5 angled.nc
```

Each angle inserts:
1. `M5` — stop spindle
2. `G28 G91 Z0` — retract Z to machine home
3. `G0 A<angle>` — rotate 4th axis

### Options

```
-o, --output FILE    Write output to a file (default: stdout)
-h, --help           Show help
-v, --version        Show version
```

## Validation

Fission validates G-code files for Carvera compatibility. Validation runs automatically during `combine`, and is also available as a standalone command:

```bash
fission validate roughing.nc finishing.nc
```

This is a sanity check, not a full G-code simulator. Always verify output with a simulator and/or dry run on your machine.

When validation passes, Fission prints a summary showing the detected units (mm/in) and the tools used in each file:

```
roughing.nc: ok
  Units: mm
  T1 - T1 D=6.35 CR=0 - ZMIN=-3 - flat end mill
```

**Errors** halt output and exit with code 1. **Warnings** print to stderr but still produce output.

### Errors

| Check | Description |
|-------|-------------|
| Unsupported G-code | G-code not in the Carvera's supported set |
| Unsupported M-code | M-code not in the Carvera's supported set |
| Missing axis word | G0/G1 without at least one of X, Y, Z, or A |
| Missing arc parameters | G2/G3 without I/J or R |
| Missing dwell time | G4 without P parameter |
| Missing spindle speed | M3/M4 without S set on the same or any prior line |
| Missing tool number | M6 without T set on the same or any prior line |
| Cutting with spindle off | G1/G2/G3 move when spindle has not been started (M3/M4) or was stopped (M5) |
| No feed rate before cut | G1/G2/G3 move without F set on any prior line |
| Spindle on during tool change | M6 while spindle is still running (no prior M5) |

### Warnings

| Check | Description |
|-------|-------------|
| No tool before spindle start | M3/M4 without a prior tool change (T/M6) |
| Air blast not on | G1/G2/G3 cutting move without M7 (air blast) active |
| Tool outside ATC range | Tool number T7-T99 requires manual tool change (ATC supports T1-T6) |

## Supported Codes

List all G-codes and M-codes supported by the Carvera:

```bash
fission codes
```

## Workflow

A typical workflow looks like this:

1. Design your part in Fusion 360
2. Create separate Manufacturing setups for each tool or each face of the part
3. Post-process each setup individually using the Carvera post processor, producing separate `.nc` files
4. Use Fission to combine them into a single program
5. Upload the combined file to your Carvera

## How It Works

Fission parses each G-code file into three sections:

- **Header** — Setup commands (G90, G17, G21, coordinate system, etc.)
- **Body** — Tool calls, spindle commands, and cutting moves
- **Footer** — Spindle stop, retract, and program end (M30)

When combining, it keeps the first file's header and last file's footer, concatenating the bodies. When angles are present, it inserts safety commands (M5 spindle stop, G28 Z retract to home) and the A-axis rotation between bodies.
