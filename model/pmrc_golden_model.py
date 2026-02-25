#-----------------------------------------------------------------------------
# Copyright (c) 2026 Jonathan Alan Reed
# Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
#
# Module: pmrc_golden_model.py
# Description: Architectural Reference Model for Parallel Mixed-Radix 
#              Conversion (PMRC). Provides bit-accurate verification 
#              vectors for hardware and software simulations.
#-----------------------------------------------------------------------------

# ==============================================================================
# GLOBAL CONFIGURATION HEADER
# ==============================================================================
K_TARGET    = 128   # Set this to match your test requirements
PRIME_START = 1000003  # Starting value for prime generation
# ==============================================================================

import random
import time
import sys

def generate_parameterized_moduli(count, start_val):
    primes = []
    num = start_val
    while len(primes) < count:
        if all(num % i != 0 for i in range(2, int(num**0.5) + 1)):
            primes.append(num)
        num += 1
    return primes

def get_tree_lut(moduli):
    """
    Recursively calculates the modular inverses required for a parallel 
    binary tree merge. Matches the LUT_BASE logic in pmrc_core_top.sv.
    """
    k = len(moduli)
    if k <= 1: 
        return [], moduli[0]
    
    mid = k // 2
    left_lut, M_left = get_tree_lut(moduli[:mid])
    right_lut, M_right = get_tree_lut(moduli[mid:])
    
    current_inv = pow(int(M_left), -1, int(M_right))
    return left_lut + right_lut + [current_inv], M_left * M_right

def reconstruct_parallel(moduli, residues, lut, offset=0):
    """
    Hardware-aligned reconstruction. Correctly tracks LUT offsets to 
    match the (LUT_BASE + K - 2) logic in pmrc_parallel_tree.sv.
    """
    k = len(moduli)
    if k == 1:
        return residues[0], moduli[0]
    
    mid = k // 2
    left_tree_lut_size = mid - 1 if mid > 1 else 0
    v_l, p_l = reconstruct_parallel(moduli[:mid], residues[:mid], lut, offset)
    v_r, p_r = reconstruct_parallel(moduli[mid:], residues[mid:], lut, offset + left_tree_lut_size)
    
    inv_idx = offset + k - 2
    inv = lut[inv_idx]
    
    diff = (v_r - v_l) % p_r
    v_out = v_l + (p_l * ((diff * inv) % p_r))
    p_out = p_l * p_r
    
    return v_out, p_out

def run_architectural_reference_model():
    # 1. --- Setup ---
    k = K_TARGET
    moduli = generate_parameterized_moduli(k, PRIME_START)
    
    # 2. --- Timing ---
    start_perf = time.perf_counter()
    
    # 3. --- Math Initialization ---
    M = 1
    for m in moduli: M *= m
    
    inverses = [[0]*k for _ in range(k)]
    for i in range(k):
        for j in range(i):
            inverses[i][j] = pow(moduli[j], -1, moduli[i])

    target_number = random.randint(M // 10, M - 1)
    residues = [target_number % m for m in moduli]
    
    # 4. --- Sequential Reference ---
    a = [0] * k
    a[0] = residues[0]
    for i in range(1, k):
        temp = residues[i]
        for j in range(i):
            temp = ((temp - a[j]) * inverses[i][j]) % moduli[i]
        a[i] = temp
        
    reconstructed_seq = 0
    multiplier = 1
    for i in range(k):
        reconstructed_seq += a[i] * multiplier
        multiplier *= moduli[i]
    
    # 5. --- Parallel Check ---
    tree_lut, _ = get_tree_lut(moduli)
    reconstructed_par, _ = reconstruct_parallel(moduli, residues, tree_lut)

    duration = time.perf_counter() - start_perf
    signature = sum(int(digit) for digit in str(reconstructed_par))
    
    # 6. --- Output Display ---
    reconstructed_hex = hex(reconstructed_par).replace('0x', '')
    print(f"\n{'='*75}")
    print(f"PMRC GOLDEN MODEL | CONFIG: K={k}")
    print(f"{'='*75}")
    print(f"MATCH STATUS (SEQ): {'[ PASS ]' if target_number == reconstructed_seq else '[ FAIL ]'}")
    print(f"MATCH STATUS (PAR): {'[ PASS ]' if target_number == reconstructed_par else '[ FAIL ]'}")
    print(f"EXPECTED X (HEX):      {reconstructed_hex}")
    print(f"DIGITAL SIGNATURE:  {signature}")
    print(f"EXECUTION TIME:     {duration:.8f}s")

    # 7. --- C++ Testbench Interface (Decimal) ---
    print(f"\n{'='*75}")
    print(">>> COPY AND PASTE INTO pmrc_test_bench.cpp (DECIMAL INPUT FOR SMALL K):")
    print(f"{'='*75}")
    
    cpp_payload = f"{k} " 
    cpp_payload += " ".join(map(str, moduli)) + " " 
    cpp_payload += " ".join(map(str, residues)) + " "
    cpp_payload += " ".join(map(str, tree_lut))
    print(cpp_payload)

    # 8. --- Expected Coefficients ---
    print("\n" + "="*75)
    print(">>> EXPECTED COEFFICIENTS (SEQUENTIAL REFERENCE):")
    print("="*75)
    
    for i, val in enumerate(a):
        print(f"a[{i}] = {val}")

    # 9. --- Hex Chunks ---
    print("\n" + "="*75)
    print(">>> COPY AND PASTE BLOCKS INTO pmrc_test_bench.cpp (HEX INPUT FOR LARGE K)")
    print("="*75)
    print(f"{k}")
    print(" ".join(hex(int(x)) for x in moduli))
    print(" ".join(hex(int(x)) for x in residues))
    
    print(f"\n--- LUT DATA ({len(tree_lut)} values) ---")
    chunk_size = 30
    for i in range(0, len(tree_lut), chunk_size):
        chunk = tree_lut[i:i+chunk_size]
        print(" ".join(hex(int(x)) for x in chunk))
    print("\n>>> END OF PAYLOAD")
    print("="*75)

    # 10. --- Vectors.txt ---
    print("\n" + "="*75)
    print(">>> COPY AND PASTE INTO vectors.txt AND COMPILE WITH pmrc_test_bench.sv)")
    print("="*75)
    for x in moduli: print(f"{x:x}")
    for x in residues: print(f"{x:x}")
    for x in tree_lut: print(f"{x:x}")
    print("="*75)

if __name__ == "__main__":
    run_architectural_reference_model()
