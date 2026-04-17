#!/usr/bin/env python3
"""
run_tests.py - CACHE.v trace-driven test runner.

Usage:
    python3 run_tests.py [--case NAME] [--verbose]

For each trace pair (inputs_*.txt / outputs_*.txt):
  1. Parses input trace → hex stimulus file
  2. Compiles CACHE.v + CACHE_TB.v with iverilog (parameters from filename)
  3. Runs simulation with vvp
  4. Parses DUT output CSV
  5. Compares against expected output (checks hit, miss, cpu_data, mem_rd, mem_wr, mem_rd_addr)
  6. Reports PASS / FAIL with first mismatch details
"""

import os
import re
import sys
import argparse
import subprocess
import tempfile
import struct
from pathlib import Path

SCRIPT_DIR   = Path(__file__).resolve().parent
TRACE_IN_DIR = SCRIPT_DIR.parent / "attached_assets" / "input traces"
TRACE_OUT_DIR= SCRIPT_DIR.parent / "attached_assets" / "output traces"

# =========================================================
# Helpers
# =========================================================

def parse_input_trace(path):
    """Return list of dicts for each cycle."""
    rows = []
    with open(path) as f:
        lines = f.readlines()
    # Skip header
    for line in lines[1:]:
        line = line.strip()
        if not line:
            continue
        # cycle,i_read,i_write,i_funct,i_addr,i_cpu_data,i_mem_ready,i_mem_valid,i_mem_data
        # i_mem_data is space-separated bytes in the last field
        parts = line.split(',', 8)   # max 9 fields
        cycle        = int(parts[0])
        i_read       = int(parts[1])
        i_write      = int(parts[2])
        i_funct      = int(parts[3])
        i_addr       = int(parts[4])
        i_cpu_data   = int(parts[5]) & 0xFFFFFFFF
        i_mem_ready  = int(parts[6])
        i_mem_valid  = int(parts[7])
        # i_mem_data: space-separated decimal bytes, LSB first
        byte_strs = parts[8].strip().split()
        block_val = 0
        for i, b in enumerate(byte_strs):
            block_val |= (int(b) & 0xFF) << (i * 8)
        rows.append({
            'cycle':       cycle,
            'i_read':      i_read,
            'i_write':     i_write,
            'i_funct':     i_funct,
            'i_addr':      i_addr,
            'i_cpu_data':  i_cpu_data,
            'i_mem_ready': i_mem_ready,
            'i_mem_valid': i_mem_valid,
            'i_mem_data':  block_val,
            'n_bytes':     len(byte_strs),
        })
    return rows


def parse_output_trace(path):
    """Return list of dicts for each cycle."""
    rows = []
    with open(path) as f:
        lines = f.readlines()
    for line in lines[1:]:
        line = line.strip()
        if not line:
            continue
        # cycle,o_hit,o_miss,o_cpu_data,o_mem_rd,o_mem_wr,o_mem_rd_addr,o_mem_rd_data
        parts = line.split(',', 7)
        rows.append({
            'cycle':       int(parts[0]),
            'o_hit':       int(parts[1]),
            'o_miss':      int(parts[2]),
            'o_cpu_data':  int(parts[3]) & 0xFFFFFFFF,
            'o_mem_rd':    int(parts[4]),
            'o_mem_wr':    int(parts[5]),
            'o_mem_rd_addr': int(parts[6].split(',')[0]),
            # o_mem_rd_data always 0 – not checked
        })
    return rows


def write_stimulus(rows, block_bits, path):
    """Write hex stimulus file for Verilog $fscanf."""
    with open(path, 'w') as f:
        for r in rows:
            # Fields: cycle read write funct addr cpu_data ready valid mem_data
            # All hex, 512-bit mem_data (padded) for the testbench
            mem_hex = format(r['i_mem_data'], '0128x')  # 512 bits = 128 hex chars
            f.write(
                f"{r['cycle']:x} "
                f"{r['i_read']:x} "
                f"{r['i_write']:x} "
                f"{r['i_funct']:x} "
                f"{r['i_addr']:08x} "
                f"{r['i_cpu_data']:08x} "
                f"{r['i_mem_ready']:x} "
                f"{r['i_mem_valid']:x} "
                f"{mem_hex}\n"
            )


def extract_params(filename):
    """
    Extract (evict_policy, ways, cache_size, block_size) from trace filename.
    e.g. inputs_lru_ways4_size32_block8.txt → (0, 4, 32, 8)
    """
    m = re.search(r'(lru|plru)_ways(\d+)_size(\d+)_block(\d+)', filename, re.I)
    if not m:
        raise ValueError(f"Cannot parse params from {filename}")
    policy     = 0 if m.group(1).lower() == 'lru' else 1
    ways       = int(m.group(2))
    cache_size = int(m.group(3))
    block_size = int(m.group(4))
    return policy, ways, cache_size, block_size


def compile_sim(policy, ways, cache_size, block_size, sim_bin):
    """Compile Verilog with iverilog, return (ok, stderr)."""
    cmd = [
        'iverilog',
        '-o', str(sim_bin),
        f'-DEVICT_POLICY={policy}',
        f'-DWAYS={ways}',
        f'-DCACHE_SIZE={cache_size}',
        f'-DBLOCK_SIZE={block_size}',
        '-P', f'CACHE_TB.EVICT_POLICY={policy}',
        '-P', f'CACHE_TB.WAYS={ways}',
        '-P', f'CACHE_TB.CACHE_SIZE={cache_size}',
        '-P', f'CACHE_TB.BLOCK_SIZE={block_size}',
        str(SCRIPT_DIR / 'CACHE.v'),
        str(SCRIPT_DIR / 'CACHE_TB.v'),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0, result.stderr


def run_sim(sim_bin, stim_file, out_file, n_cycles):
    """Run vvp simulation, return (ok, stderr)."""
    cmd = [
        'vvp', str(sim_bin),
        f'+stim={stim_file}',
        f'+out={out_file}',
        f'+ncycles={n_cycles}',
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    return result.returncode == 0, result.stderr + result.stdout


def parse_dut_output(path):
    """Parse DUT output CSV, return list of dicts."""
    rows = []
    with open(path) as f:
        lines = f.readlines()
    for line in lines[1:]:
        line = line.strip()
        if not line:
            continue
        parts = line.split(',')
        if len(parts) < 7:
            continue
        rows.append({
            'cycle':        int(parts[0]),
            'o_hit':        int(parts[1]),
            'o_miss':       int(parts[2]),
            'o_cpu_data':   int(parts[3]) & 0xFFFFFFFF,
            'o_mem_rd':     int(parts[4]),
            'o_mem_wr':     int(parts[5]),
            'o_mem_rd_addr':int(parts[6]),
        })
    return rows


CHECKED_FIELDS = ['o_hit', 'o_miss', 'o_cpu_data', 'o_mem_rd', 'o_mem_wr', 'o_mem_rd_addr']


def compare(dut_rows, exp_rows, verbose=False):
    """Compare DUT vs expected. Return (pass, n_checked, n_mismatch, mismatches)."""
    mismatches = []
    n_checked  = min(len(dut_rows), len(exp_rows))
    for i in range(n_checked):
        d = dut_rows[i]
        e = exp_rows[i]
        if d['cycle'] != e['cycle']:
            mismatches.append(f"Cycle mismatch: dut={d['cycle']} exp={e['cycle']}")
            break
        for f in CHECKED_FIELDS:
            if d[f] != e[f]:
                mismatches.append(
                    f"cycle={d['cycle']} {f}: got={d[f]} exp={e[f]}"
                )
        if mismatches and not verbose:
            break
    ok = len(mismatches) == 0 and len(dut_rows) >= len(exp_rows)
    return ok, n_checked, len(mismatches), mismatches


def run_one(in_file, out_file, verbose, tmpdir):
    """Run a single test case. Return (pass, msg)."""
    policy, ways, cache_size, block_size = extract_params(in_file.name)
    tag = in_file.stem.replace('inputs_', '')

    in_rows  = parse_input_trace(in_file)
    exp_rows = parse_output_trace(out_file)

    stim_path = tmpdir / f'{tag}_stim.txt'
    sim_bin   = tmpdir / f'{tag}.vvp'
    dut_out   = tmpdir / f'{tag}_dut_out.csv'

    write_stimulus(in_rows, block_size * 8, stim_path)

    ok, errs = compile_sim(policy, ways, cache_size, block_size, sim_bin)
    if not ok:
        return False, f"COMPILE ERROR:\n{errs}"

    ok, log = run_sim(sim_bin, stim_path, dut_out, len(in_rows))
    if not ok or not dut_out.exists():
        return False, f"SIM ERROR:\n{log}"

    dut_rows = parse_dut_output(dut_out)
    passed, n_checked, n_miss, mismatches = compare(dut_rows, exp_rows, verbose)

    if passed:
        return True, f"PASS  ({n_checked} cycles checked)"
    else:
        detail = '\n  '.join(mismatches[:10])
        return False, f"FAIL  ({n_miss} mismatches in {n_checked} cycles)\n  {detail}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--case',    help='Run only cases matching this substring')
    parser.add_argument('--verbose', action='store_true')
    args = parser.parse_args()

    in_files = sorted(TRACE_IN_DIR.glob('inputs_*.txt'))
    if args.case:
        in_files = [f for f in in_files if args.case in f.name]

    if not in_files:
        print("No trace files found.")
        sys.exit(1)

    tmpdir = Path(tempfile.mkdtemp(prefix='cache_test_'))
    print(f"Temp dir: {tmpdir}\n")

    results = []
    for in_f in in_files:
        out_f = TRACE_OUT_DIR / in_f.name.replace('inputs_', 'outputs_')
        if not out_f.exists():
            print(f"  [SKIP] no expected output for {in_f.name}")
            continue
        tag = in_f.stem.replace('inputs_', '')
        print(f"Testing {tag} ...", flush=True)
        passed, msg = run_one(in_f, out_f, args.verbose, tmpdir)
        results.append((tag, passed))
        status = "PASS" if passed else "FAIL"
        print(f"  [{status}] {msg}\n")

    n_pass = sum(1 for _, p in results if p)
    n_fail = len(results) - n_pass
    print(f"\n{'='*50}")
    print(f"Results: {n_pass}/{len(results)} passed, {n_fail} failed")
    if n_fail > 0:
        sys.exit(1)


if __name__ == '__main__':
    main()
