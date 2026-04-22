import sys
import os

#Phase 2 worked on by Andrew Green and Fabian Nunez

# ChatGpt assisted in comment labels and completed some repetitive coding
# like assigning the values of the register map and sorting the instruction types
# for the dispatcher and the comments that discribe the format of the instruction types

# -------------------------------
# Register Map *assisted by chatgpt
# -------------------------------
REG = {
    "x0":0, "x1":1, "x2":2, "x3":3, "x4":4,
    "x5":5, "x6":6, "x7":7, "x8":8, "x9":9,
    "x10":10, "x11":11, "x12":12, "x13":13,
    "x14":14, "x15":15, "x16":16, "x17":17,
    "x18":18, "x19":19, "x20":20, "x21":21,
    "x22":22, "x23":23, "x24":24, "x25":25,
    "x26":26, "x27":27, "x28":28, "x29":29,
    "x30":30, "x31":31,

    "zero":0, "ra":1, "sp":2, "gp":3, "tp":4,
    "t0":5, "t1":6, "t2":7, "s0":8, "fp":8,
    "s1":9, "a0":10, "a1":11, "a2":12, "a3":13,
    "a4":14, "a5":15, "a6":16, "a7":17,
    "s2":18, "s3":19, "s4":20, "s5":21,
    "s6":22, "s7":23, "s8":24, "s9":25,
    "s10":26, "s11":27,
    "t3":28, "t4":29, "t5":30, "t6":31
}

# -------------------------------
# Memory Map (Phase 6)
# -------------------------------
INSTR_BASE = 0x00400000   # .text section starts here
DATA_BASE  = 0x10010000   # .data section starts here

# -------------------------------
# Global Tables
# -------------------------------
label_table = {}
instructions = []

# -------------------------------
# Utility Functions
# -------------------------------
def clean_line(line):
    line = line.split('#')[0]
    return line.strip()

# -------------------------------
# Pass 1: Build Label Table
# -------------------------------
def first_pass(lines):
    pc = INSTR_BASE
    data_pc = DATA_BASE
    in_text = False
    in_data = False

    for line in lines:
        line = clean_line(line)
        if not line:
            continue

        if line.startswith(".text"):
            in_text = True
            in_data = False
            continue

        if line.startswith(".data"):
            in_text = False
            in_data = True
            continue


        if line.startswith(".globl"):
            continue

        if in_data:
            # Handle label (possibly with data on same line)
            if ':' in line:
                label, rest = line.split(':', 1)
                label = label.strip()
                label_table[label] = data_pc
                line = rest.strip()

                if not line:
                    continue  # label-only line

            # Count data values (assume 32-bit words)
            values = line.split(',')
            data_pc += 4 * len(values)
            continue

        if in_text:
            # Handle label (possibly with instruction on same line)
            if ':' in line:
                label, rest = line.split(':', 1)
                label = label.strip()
                label_table[label] = pc
                line = rest.strip()

                if not line:
                    continue  # label-only line

            # Instruction occupies 4 bytes
            pc += 4


# -------------------------------
# Instruction Encoders (stubs) *THIS IS THE BIT TO WORK ON*
# -------------------------------
def encode_r_type(mnemonic, ops):
    # R-type format (32 bits total):
    # funct7 | rs2 | rs1 | funct3 | rd | opcode
    #  7     |  5  |  5  |   3    | 5  |   7
        rd  = REG[ops[0]]
        rs1 = REG[ops[1]]
        rs2 = REG[ops[2]]

        opcode = 0b0110011

        if mnemonic == "add":
            funct3 = 0b000
            funct7 = 0b0000000

        elif mnemonic == "sub":
            funct3 = 0b000
            funct7 = 0b0100000

        elif mnemonic == "and":
            funct3 = 0b111
            funct7 = 0b0000000

        elif mnemonic == "or":
            funct3 = 0b110
            funct7 = 0b0000000

        elif mnemonic == "sll":
            funct3 = 0b001
            funct7 = 0b0000000

        elif mnemonic == "slt":
            funct3 = 0b010; funct7 = 0b0000000

        elif mnemonic == "sltu":
            funct3 = 0b011; funct7 = 0b0000000

        elif mnemonic == "xor":
            funct3 = 0b100; funct7 = 0b0000000

        elif mnemonic == "srl":
            funct3 = 0b101; funct7 = 0b0000000

        elif mnemonic == "sra":
            funct3 = 0b101; funct7 = 0b0100000

        else:
            raise ValueError("Unsupported R-type instruction")

        instr = ((funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode)
        return instr

def encode_i_type(mnemonic, ops):
    # I-type format (32 bits total):
    # imm[11:0] | rs1 | funct3 | rd | opcode
    #    12     |  5  |   3    | 5  |   7

    if mnemonic == "addi":

        opcode = 0b0010011
        funct3 = 0b000

        rd = REG[ops[0]]
        rs = REG[ops[1]]

        imm_token = ops[2]

        if imm_token.startswith("%lo("):
            label = imm_token[4:-1]
            addr = label_table[label]
            imm = addr & 0xFFF
            if imm & 0x800:
                imm -= 0x1000

        elif imm_token in label_table:
            imm = label_table[imm_token] & 0xFFF
            if imm & 0x800:
                imm -= 0x1000

        else:
            imm = int(imm_token)

        imm &= 0xFFF

        instruction = (
            (imm << 20) |
            (rs << 15) |
            (funct3 << 12) |
            (rd << 7) |
            opcode
        )


    elif mnemonic == "lw":

        opcode = 0b0000011
        func3 = 0b010

        rd = REG[ops[0]]

        if '(' in ops[1]:
            offset, rs = ops[1].replace(")","").split("(")
            offset = int(offset) & 0xFFF
            rs = REG[rs]
        else:
            label = ops[1]
            destination = label_table[label]
            offset = destination & 0xFFF
            rs = 0

        instruction = ((offset << 20) | (rs << 15) | (func3 << 12) | (rd << 7) | opcode)



    elif mnemonic == "slli":
        opcode = 0b0010011; funct3 = 0b001; funct7 = 0b0000000
        rd = REG[ops[0]]; rs = REG[ops[1]]; shamt = int(ops[2]) & 0x1F
        instruction = ((funct7 << 25) | (shamt << 20) | (rs << 15) | (funct3 << 12) | (rd << 7) | opcode)

    elif mnemonic == "srli":
        opcode = 0b0010011; funct3 = 0b101; funct7 = 0b0000000
        rd = REG[ops[0]]; rs = REG[ops[1]]; shamt = int(ops[2]) & 0x1F
        instruction = ((funct7 << 25) | (shamt << 20) | (rs << 15) | (funct3 << 12) | (rd << 7) | opcode)

    elif mnemonic == "srai":
        opcode = 0b0010011; funct3 = 0b101; funct7 = 0b0100000
        rd = REG[ops[0]]; rs = REG[ops[1]]; shamt = int(ops[2]) & 0x1F
        instruction = ((funct7 << 25) | (shamt << 20) | (rs << 15) | (funct3 << 12) | (rd << 7) | opcode)

    elif mnemonic in ("andi", "ori", "xori", "slti", "sltiu"):
        opcode = 0b0010011
        funct3_map = {"andi": 0b111, "ori": 0b110, "xori": 0b100, "slti": 0b010, "sltiu": 0b011}
        funct3 = funct3_map[mnemonic]
        rd = REG[ops[0]]; rs = REG[ops[1]]
        imm = int(ops[2], 0) & 0xFFF
        instruction = ((imm << 20) | (rs << 15) | (funct3 << 12) | (rd << 7) | opcode)

    elif mnemonic in ("lb", "lh", "lbu", "lhu"):
        opcode = 0b0000011
        funct3_map = {"lb": 0b000, "lh": 0b001, "lbu": 0b100, "lhu": 0b101}
        funct3 = funct3_map[mnemonic]
        rd = REG[ops[0]]
        if '(' in ops[1]:
            offset, rs = ops[1].replace(")", "").split("(")
            imm = int(offset) & 0xFFF; rs = REG[rs]
        else:
            imm = label_table[ops[1]] & 0xFFF; rs = 0
        instruction = ((imm << 20) | (rs << 15) | (funct3 << 12) | (rd << 7) | opcode)

    elif mnemonic == "jalr":
        opcode = 0b1100111; funct3 = 0b000
        if len(ops) == 1:
            # jalr rs1  ->  jalr x0, rs1, 0
            rd = 0; rs = REG[ops[0]]; imm = 0
        elif '(' in ops[1]:
            # jalr rd, imm(rs1)
            rd = REG[ops[0]]
            offset, rs = ops[1].replace(")", "").split("(")
            imm = int(offset) & 0xFFF; rs = REG[rs]
        elif len(ops) == 2 and ops[1] in REG:
            # jalr rd, rs1  ->  jalr rd, rs1, 0
            rd = REG[ops[0]]; rs = REG[ops[1]]; imm = 0
        else:
            # jalr rd, rs1, imm
            rd = REG[ops[0]]; rs = REG[ops[1]]; imm = int(ops[2], 0) & 0xFFF
        instruction = ((imm << 20) | (rs << 15) | (funct3 << 12) | (rd << 7) | opcode)

    else:
        raise ValueError("Unsupported I-type")
    
    return instruction

def encode_s_type(mnemonic, ops):
    # S-type format:
    # imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode

    opcode = 0b0100011

    rs2 = REG[ops[0]]   # value to store

    # Parse offset(rs1) or label(rs1) or label
    addr_token = ops[1]

    if '(' in addr_token:
        offset, rs1 = addr_token.replace(")", "").split("(")
        rs1 = REG[rs1]

        if offset.startswith("%lo("):
            label = offset[4:-1]
            imm = label_table[label] & 0xFFF
        elif offset in label_table:
            imm = label_table[offset] & 0xFFF
        else:
            imm = int(offset)

    else:
        # sw rs2, label   → label(x0)
        rs1 = 0
        imm = label_table[addr_token] & 0xFFF

    # Sign-extend 12-bit immediate
    if imm & 0x800:
        imm -= 0x1000

    imm &= 0xFFF

    # funct3 selection
    if mnemonic == "sb":
        funct3 = 0b000
    elif mnemonic == "sh":
        funct3 = 0b001
    elif mnemonic == "sw":
        funct3 = 0b010
    else:
        raise ValueError("Unsupported S-type instruction")

    imm11_5 = (imm >> 5) & 0x7F
    imm4_0  = imm & 0x1F

    instruction = (
        (imm11_5 << 25) |
        (rs2 << 20) |
        (rs1 << 15) |
        (funct3 << 12) |
        (imm4_0 << 7) |
        opcode
    )

    return instruction

def encode_b_type(mnemonic, ops, pc):
    # B-type format (32 bits total):
    # imm[12] | imm[10:5] | rs2 | rs1 | funct3 | imm[4:1] | imm[11] | opcode
    #    1    |     6     |  5  |  5  |   3    |     4     |    1    |   7\

    rs1 = REG[ops[0]]
    rs2 = REG[ops[1]]
    label = ops[2]
    opcode = 0b1100011

    if mnemonic == "beq":
        func3 = 0b000
    elif mnemonic == "bne":
        func3 = 0b001
    elif mnemonic == "blt":
        func3 = 0b100
    elif mnemonic == "bge":
        func3 = 0b101
    elif mnemonic == "bltu":
        func3 = 0b110
    elif mnemonic == "bgeu":
        func3 = 0b111
    else:
        raise ValueError("Unsupported Instruction")   
    
    destination = label_table[label]
    offset = destination-pc

    imm12   = (offset >> 12) & 0x1
    imm10_5 = (offset >> 5)  & 0x3F
    imm4_1  = (offset >> 1)  & 0xF
    imm11   = (offset >> 11) & 0x1

    instruction = ((imm12   << 31) | (imm10_5 << 25) | (rs2     << 20) | (rs1     << 15) | (func3  << 12) | (imm4_1  << 8) | (imm11   << 7) | opcode)
    return instruction

def encode_u_type(mnemonic, ops):
    # U-type format (32 bits total):
    # imm[31:12] | rd | opcode
    #     20     | 5  |   7

    rd = REG[ops[0]]
    imm_token = ops[1]    # will be %hi(label) or an immediate

    if mnemonic == "lui":
        opcode = 0b0110111

        #this immideate code and be reused
        if imm_token.startswith("%hi("):    #checks for a label as the immideate
            label = imm_token[4:-1]          # extract label name
            addr = label_table[label]
            imm = (addr + 0x800) >> 12        # %hi calculation
        
        elif imm_token in label_table:
            addr = label_table[imm_token]
            imm = (addr + 0x800) >> 12

        else:
            imm = int(imm_token, 0)

        imm &= 0xFFFFF  # mask to keep 20 bits

        instr = (imm << 12) | (rd << 7) | opcode
        return instr

    elif mnemonic == "auipc":
        opcode = 0b0010111

        if imm_token.startswith("%hi("):
            label = imm_token[4:-1]
            addr = label_table[label]
            imm = (addr + 0x800) >> 12

        elif imm_token in label_table:
            addr = label_table[imm_token]
            imm = (addr + 0x800) >> 12
            
        else:
            imm = int(imm_token, 0)

        imm &= 0xFFFFF

        instr = ((imm << 12) | (rd << 7) | opcode)
        return instr

    else:
        raise ValueError("Unsupported U-type")

def encode_j_type(mnemonic, ops, pc):
    # J-type format (32 bits total):
    # imm[20] | imm[10:1] | imm[11] | imm[19:12] | rd | opcode
    #    1    |    10     |    1    |      8      | 5  |   7
    opcode = 0b1101111
    rd = REG[ops[0]]
    label = ops[1]

    destination = label_table[label]
    offset = destination-pc

    # Range check (21-bit signed, LSB is zero)
    if offset < -1048576 or offset > 1048574:
        raise ValueError("JAL offset out of range")
    
    # offset = offset >> 1 #drop LSB
    offset &= 0x1FFFFF #Force offset to be 21 bits

    imm20     = (offset >> 20) & 0x1
    imm10_1   = (offset >> 1)  & 0x3FF
    imm11     = (offset >> 11) & 0x1
    imm19_12  = (offset >> 12) & 0xFF

    instruction = ((imm20 << 31) | (imm10_1 << 21) | (imm11 << 20) | (imm19_12 << 12) | (rd << 7) | opcode)
    return instruction

# -------------------------------
# Dispatcher *assisted by chatgpt
# -------------------------------
def encode_instruction(mnemonic, ops, pc):
    if mnemonic in {"add", "sub", "and", "or", "sll", "slt", "sltu", "xor", "srl", "sra"}:
        return encode_r_type(mnemonic, ops)

    if mnemonic in {"addi", "andi", "ori", "xori", "slti", "sltiu", "lw", "lb", "lh", "lbu", "lhu", "jalr", "slli", "srli", "srai"}:
        return encode_i_type(mnemonic, ops)

    if mnemonic in {"sw", "sb", "sh"}:
        return encode_s_type(mnemonic, ops)

    if mnemonic in {"beq", "bne", "blt", "bge", "bltu", "bgeu"}:
        return encode_b_type(mnemonic, ops, pc)

    if mnemonic in {"lui", "auipc"}:
        return encode_u_type(mnemonic, ops)

    if mnemonic == "jal":
        return encode_j_type(mnemonic, ops, pc)

    raise ValueError(f"Unsupported instruction: {mnemonic}")

# -------------------------------
# Pass 2: Encode Instructions
# -------------------------------
def second_pass(lines, instr_path, data_path):
    pc = INSTR_BASE
    in_text = False

    with open(instr_path, "w", newline='\n') as instr_out:
        for line in lines:
            line = clean_line(line)
            if not line:
                continue
                 
            if line.startswith(".text"):
                in_text = True
                continue

            if not in_text:
                continue
            
            if ':' in line:
                # Handle labels
                if ':' in line:
                    label, rest = line.split(':', 1)
                    line = rest.strip()

                    if not line:
                        continue   # label-only line

            if line.startswith(".globl"):
                continue

            tokens = line.replace(',', '').split()
            mnemonic = tokens[0]
            ops = tokens[1:]

            # ebreak is appended automatically at the end, skip if explicit
            if mnemonic == "ebreak":
                continue

            instr = encode_instruction(mnemonic, ops, pc)

            bytes_le = instr.to_bytes(4, byteorder='little')

            for b in bytes_le:
                instr_out.write(f"0x{b:02X}\n")

            pc += 4
        # Append ebreak instruction
        ebreak = 0x00100073
        bytes_le = ebreak.to_bytes(4, byteorder='little')

        for b in bytes_le:
            instr_out.write(f"0x{b:02X}\n")

# -------------------------------
# Main
# -------------------------------
def write_data(lines, data_path):
    in_data = False
    words = []

    for line in lines:
        line = clean_line(line)
        if not line:
            continue
        if line.startswith(".data"):
            in_data = True
            continue
        if line.startswith(".text"):
            in_data = False
            continue
        if not in_data:
            continue
        if line.startswith(".globl"):
            continue

        # Strip label if present
        if ":" in line:
            _, line = line.split(":", 1)
            line = line.strip()
        if not line:
            continue

        # Parse .word directive
        if line.startswith(".word"):
            line = line[len(".word"):].strip()

        # Parse comma-separated values
        for val in line.split(","):
            val = val.strip()
            if val:
                words.append(int(val, 0) & 0xFFFFFFFF)

    with open(data_path, "w", newline='\n') as f:
        for w in words:
            bs = w.to_bytes(4, byteorder="little")
            for b in bs:
                f.write(f"0x{b:02X}\n")


def main():
    if len(sys.argv) != 3:
        print("assembler <file.s> <output_directory>")
        sys.exit(1)

    asm_file = sys.argv[1]
    output_dir = sys.argv[2]

    os.makedirs(output_dir, exist_ok=True)

    with open(asm_file, "r") as f:
        lines = f.readlines()

    first_pass(lines)

    instr_path = os.path.join(output_dir, "instr.txt")
    data_path = os.path.join(output_dir, "data.txt")

    second_pass(lines, instr_path, data_path)

    write_data(lines, data_path)
    
if __name__ == "__main__":
    main()
