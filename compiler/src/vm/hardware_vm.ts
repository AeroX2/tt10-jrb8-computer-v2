import {
  MOV_RANGE,
  CMP_RANGE,
  JMP_RANGE,
  JMP2_RANGE,
  OPP_RANGE,
  LOAD_RANGE,
  SAVE_RANGE,
  IN_OUT_RANGE,
  CU_FLAGS,
} from "../utils/cu_flags";

export class HardwareVM {
  // Registers
  private registerA: number = 0;
  private registerB: number = 0;
  private registerC: number = 0;
  private registerD: number = 0;

  // Memory
  private ram: number[] = new Array<number>(256).fill(0);
  rom: number[] = new Array<number>(65536).fill(0); // 16-bit address space
  private mar: number = 0; // Memory Address Register
  private ramPage: number = 0;

  // Flags
  private zeroFlag: boolean = false;
  private overflowFlag: boolean = false;
  private carryFlag: boolean = false;
  private signFlag: boolean = false;
  private carryEnabled: boolean = false;
  private signedMode: boolean = false;

  // Program Counter
  private pc: number = 0;

  private outputCallback?: (value: number) => void;
  private inputCallback?: () => number;

  constructor() {
    this.reset();
  }

  reset() {
    this.registerA = 0;
    this.registerB = 0;
    this.registerC = 0;
    this.registerD = 0;
    this.ram.fill(0);
    this.mar = 0;
    this.ramPage = 0;
    this.pc = 0;
    this.resetFlags();
  }

  resetFlags() {
    this.zeroFlag = false;
    this.overflowFlag = false;
    this.carryFlag = false;
    this.signFlag = false;
    this.carryEnabled = false;
    this.signedMode = false;
  }

  // Load program into ROM
  loadProgram(program: number[]) {
    this.rom = [...program];
    this.pc = 0;
  }

  // Get the loaded program
  getProgram(): number[] {
    return [...this.rom];
  }

  private updateFlags(result: number) {
    this.zeroFlag = result === 0;
    this.signFlag = (result & 0x80) !== 0;
    this.carryFlag = result > 255 || result < 0;

    if (this.signedMode) {
      this.overflowFlag = result > 127 || result < -128;
    } else {
      this.overflowFlag = false;
    }
  }

  // Execute one instruction
  step(): boolean {
    const instruction = this.rom[this.pc];
    this.pc++;

    if (instruction === CU_FLAGS["nop"]) {
      return true;
    } else if (instruction === CU_FLAGS["halt"]) {
      return false;
    }

    if (instruction >= MOV_RANGE.MIN && instruction <= MOV_RANGE.MAX) {
      this.executeMove(instruction);
    } else if (instruction >= CMP_RANGE.MIN && instruction <= CMP_RANGE.MAX) {
      this.executeCompare(instruction);
    } else if (instruction >= JMP_RANGE.MIN && instruction <= JMP_RANGE.MAX) {
      this.executeJump(instruction);
    } else if (instruction >= JMP2_RANGE.MIN && instruction <= JMP2_RANGE.MAX) {
      this.executeJumpRelative(instruction);
    } else if (instruction >= OPP_RANGE.MIN && instruction <= OPP_RANGE.MAX) {
      this.executeALU(instruction);
    } else if (instruction >= LOAD_RANGE.MIN && instruction <= LOAD_RANGE.MAX) {
      this.executeLoad(instruction);
    } else if (instruction >= SAVE_RANGE.MIN && instruction <= SAVE_RANGE.MAX) {
      this.executeSave(instruction);
    } else if (instruction >= IN_OUT_RANGE.MIN && instruction <= IN_OUT_RANGE.MAX) {
      this.executeIO(instruction);
    }

    return true;
  }

  private executeMove(instruction: number) {
    // Get source and destination from instruction mapping
    // For instruction 0xXY:
    // if Y < 4: src = 0 (A), dst = Y
    // if Y < 7: src = 1 (B), dst = Y-3
    // if Y < A: src = 2 (C), dst = Y-6
    // if Y < D: src = 3 (D), dst = Y-9
    const instr = instruction & 0x0f;
    if (instr === 0 || instr > 0x0c) return; // NOP or invalid

    const src = Math.floor((instr - 1) / 3);
    const dst = ((instr - 1) % 3) + ((instr - 1) % 3 >= src ? 1 : 0);

    this.setRegisterByIndex(dst, this.getRegisterByIndex(src));
  }

  private executeCompare(instruction: number) {
    let value1: number, value2: number;

    if (instruction <= CMP_RANGE.MIN + 0x0f) {
      // Compare with constants (0, 1, -1, 255)
      const reg = instruction & 0x03;
      const constType = (instruction >> 2) & 0x03;
      value1 = this.getRegisterByIndex(reg);
      value2 = this.getConstantForCmp(constType);
    } else {
      // Compare between registers
      value1 = this.getRegisterByIndex((instruction >> 2) & 0x03);
      value2 = this.getRegisterByIndex(instruction & 0x03);
    }

    const result = value1 - value2;
    this.updateFlags(result);
  }

  private executeJump(instruction: number) {
    const condition = instruction & 0x0f;
    const jumpAddress = (this.rom[this.pc] << 8) | this.rom[this.pc + 1];

    if (this.shouldJump(condition)) {
      this.pc = jumpAddress;
    } else {
      this.pc += 2; // Skip address bytes
    }
  }

  private executeJumpRelative(instruction: number) {
    const condition = instruction & 0x0f;
    const offset = this.rom[this.pc]; // Get 8-bit offset

    // Convert to signed offset (-128 to +127)
    const signedOffset = offset & 0x80 ? offset - 256 : offset;

    if (this.shouldJump(condition)) {
      this.pc = (this.pc + signedOffset + 1) & 0xff; // +1 to skip the offset byte
    } else {
      this.pc++; // Skip offset byte
    }
  }

  private executeALU(instruction: number) {
    let result = 0;

    // Control operations
    if (instruction === CU_FLAGS["opp clr"]) {
      this.resetFlags();
      return;
    } else if (instruction === CU_FLAGS["opp carry off"]) {
      this.carryEnabled = false;
      return;
    } else if (instruction === CU_FLAGS["opp carry on"]) {
      this.carryEnabled = true;
      return;
    } else if (instruction === CU_FLAGS["opp sign off"]) {
      this.signedMode = false;
      return;
    } else if (instruction === CU_FLAGS["opp sign on"]) {
      this.signedMode = true;
      return;
    }

    // Calculate result first
    if (instruction === CU_FLAGS["opp 0"]) result = 0;
    else if (instruction === CU_FLAGS["opp 1"]) result = 1;
    else if (instruction === CU_FLAGS["opp -1"]) result = -1;
    else if (instruction === CU_FLAGS["opp a"]) result = this.registerA;
    else if (instruction === CU_FLAGS["opp b"]) result = this.registerB;
    else if (instruction === CU_FLAGS["opp c"]) result = this.registerC;
    else if (instruction === CU_FLAGS["opp d"]) result = this.registerD;
    // Unary operations
    else if (instruction === CU_FLAGS["opp ~a"]) result = ~this.registerA;
    else if (instruction === CU_FLAGS["opp ~b"]) result = ~this.registerB;
    else if (instruction === CU_FLAGS["opp ~c"]) result = ~this.registerC;
    else if (instruction === CU_FLAGS["opp ~d"]) result = ~this.registerD;
    else if (instruction === CU_FLAGS["opp -a"]) result = -this.registerA;
    else if (instruction === CU_FLAGS["opp -b"]) result = -this.registerB;
    else if (instruction === CU_FLAGS["opp -c"]) result = -this.registerC;
    else if (instruction === CU_FLAGS["opp -d"]) result = -this.registerD;
    else if (instruction === CU_FLAGS["opp a+1"]) result = this.registerA + 1;
    else if (instruction === CU_FLAGS["opp b+1"]) result = this.registerB + 1;
    else if (instruction === CU_FLAGS["opp c+1"]) result = this.registerC + 1;
    else if (instruction === CU_FLAGS["opp d+1"]) result = this.registerD + 1;
    else if (instruction === CU_FLAGS["opp a-1"]) result = this.registerA - 1;
    else if (instruction === CU_FLAGS["opp b-1"]) result = this.registerB - 1;
    else if (instruction === CU_FLAGS["opp c-1"]) result = this.registerC - 1;
    else if (instruction === CU_FLAGS["opp d-1"]) result = this.registerD - 1;
    // Binary operations - Addition (now with carry handling)
    else if (instruction >= CU_FLAGS["opp a+b"] && instruction <= CU_FLAGS["opp d+c"]) {
      const carryValue = this.carryEnabled && this.carryFlag ? 1 : 0;
      if (instruction === CU_FLAGS["opp a+b"])
        result = this.registerA + this.registerB + carryValue;
      else if (instruction === CU_FLAGS["opp a+c"])
        result = this.registerA + this.registerC + carryValue;
      else if (instruction === CU_FLAGS["opp a+d"])
        result = this.registerA + this.registerD + carryValue;
      else if (instruction === CU_FLAGS["opp b+a"])
        result = this.registerB + this.registerA + carryValue;
      else if (instruction === CU_FLAGS["opp b+c"])
        result = this.registerB + this.registerC + carryValue;
      else if (instruction === CU_FLAGS["opp b+d"])
        result = this.registerB + this.registerD + carryValue;
      else if (instruction === CU_FLAGS["opp c+a"])
        result = this.registerC + this.registerA + carryValue;
      else if (instruction === CU_FLAGS["opp c+b"])
        result = this.registerC + this.registerB + carryValue;
      else if (instruction === CU_FLAGS["opp c+d"])
        result = this.registerC + this.registerD + carryValue;
      else if (instruction === CU_FLAGS["opp d+a"])
        result = this.registerD + this.registerA + carryValue;
      else if (instruction === CU_FLAGS["opp d+b"])
        result = this.registerD + this.registerB + carryValue;
      else if (instruction === CU_FLAGS["opp d+c"])
        result = this.registerD + this.registerC + carryValue;
    }

    // Binary operations - Subtraction
    else if (instruction === CU_FLAGS["opp a-b"]) result = this.registerA - this.registerB;
    else if (instruction === CU_FLAGS["opp a-c"]) result = this.registerA - this.registerC;
    else if (instruction === CU_FLAGS["opp a-d"]) result = this.registerA - this.registerD;
    else if (instruction === CU_FLAGS["opp b-a"]) result = this.registerB - this.registerA;
    else if (instruction === CU_FLAGS["opp b-c"]) result = this.registerB - this.registerC;
    else if (instruction === CU_FLAGS["opp b-d"]) result = this.registerB - this.registerD;
    else if (instruction === CU_FLAGS["opp c-a"]) result = this.registerC - this.registerA;
    else if (instruction === CU_FLAGS["opp c-b"]) result = this.registerC - this.registerB;
    else if (instruction === CU_FLAGS["opp c-d"]) result = this.registerC - this.registerD;
    else if (instruction === CU_FLAGS["opp d-a"]) result = this.registerD - this.registerA;
    else if (instruction === CU_FLAGS["opp d-b"]) result = this.registerD - this.registerB;
    else if (instruction === CU_FLAGS["opp d-c"]) result = this.registerD - this.registerC;
    // Binary operations - Multiplication (low)
    else if (instruction === CU_FLAGS["opp a*a"]) result = this.registerA * this.registerA;
    else if (instruction === CU_FLAGS["opp a*b"]) result = this.registerA * this.registerB;
    else if (instruction === CU_FLAGS["opp a*c"]) result = this.registerA * this.registerC;
    else if (instruction === CU_FLAGS["opp a*d"]) result = this.registerA * this.registerD;
    else if (instruction === CU_FLAGS["opp b*a"]) result = this.registerB * this.registerA;
    else if (instruction === CU_FLAGS["opp b*b"]) result = this.registerB * this.registerB;
    else if (instruction === CU_FLAGS["opp b*c"]) result = this.registerB * this.registerC;
    else if (instruction === CU_FLAGS["opp b*d"]) result = this.registerB * this.registerD;
    else if (instruction === CU_FLAGS["opp c*a"]) result = this.registerC * this.registerA;
    else if (instruction === CU_FLAGS["opp c*b"]) result = this.registerC * this.registerB;
    else if (instruction === CU_FLAGS["opp c*c"]) result = this.registerC * this.registerC;
    else if (instruction === CU_FLAGS["opp c*d"]) result = this.registerC * this.registerD;
    else if (instruction === CU_FLAGS["opp d*a"]) result = this.registerD * this.registerA;
    else if (instruction === CU_FLAGS["opp d*b"]) result = this.registerD * this.registerB;
    else if (instruction === CU_FLAGS["opp d*c"]) result = this.registerD * this.registerC;
    else if (instruction === CU_FLAGS["opp d*d"]) result = this.registerD * this.registerD;
    // Binary operations - Division
    else if (instruction === CU_FLAGS["opp a/b"])
      result = Math.floor(this.registerA / this.registerB);
    else if (instruction === CU_FLAGS["opp a/c"])
      result = Math.floor(this.registerA / this.registerC);
    else if (instruction === CU_FLAGS["opp a/d"])
      result = Math.floor(this.registerA / this.registerD);
    else if (instruction === CU_FLAGS["opp b/a"])
      result = Math.floor(this.registerB / this.registerA);
    else if (instruction === CU_FLAGS["opp b/c"])
      result = Math.floor(this.registerB / this.registerC);
    else if (instruction === CU_FLAGS["opp b/d"])
      result = Math.floor(this.registerB / this.registerD);
    else if (instruction === CU_FLAGS["opp c/a"])
      result = Math.floor(this.registerC / this.registerA);
    else if (instruction === CU_FLAGS["opp c/b"])
      result = Math.floor(this.registerC / this.registerB);
    else if (instruction === CU_FLAGS["opp c/d"])
      result = Math.floor(this.registerC / this.registerD);
    else if (instruction === CU_FLAGS["opp d/a"])
      result = Math.floor(this.registerD / this.registerA);
    else if (instruction === CU_FLAGS["opp d/b"])
      result = Math.floor(this.registerD / this.registerB);
    else if (instruction === CU_FLAGS["opp d/c"])
      result = Math.floor(this.registerD / this.registerC);
    // Binary operations - Logical AND
    else if (instruction === CU_FLAGS["opp a&b"]) result = this.registerA & this.registerB;
    else if (instruction === CU_FLAGS["opp a&c"]) result = this.registerA & this.registerC;
    else if (instruction === CU_FLAGS["opp a&d"]) result = this.registerA & this.registerD;
    else if (instruction === CU_FLAGS["opp b&c"]) result = this.registerB & this.registerC;
    else if (instruction === CU_FLAGS["opp b&d"]) result = this.registerB & this.registerD;
    else if (instruction === CU_FLAGS["opp c&d"]) result = this.registerC & this.registerD;
    // Binary operations - Logical OR
    else if (instruction === CU_FLAGS["opp a|b"]) result = this.registerA | this.registerB;
    else if (instruction === CU_FLAGS["opp a|c"]) result = this.registerA | this.registerC;
    else if (instruction === CU_FLAGS["opp a|d"]) result = this.registerA | this.registerD;
    else if (instruction === CU_FLAGS["opp b|c"]) result = this.registerB | this.registerC;
    else if (instruction === CU_FLAGS["opp b|d"]) result = this.registerB | this.registerD;
    else if (instruction === CU_FLAGS["opp c|d"]) result = this.registerC | this.registerD;
    // Binary operations - Special multiplication (high bits)
    else if (instruction === CU_FLAGS["opp a.*a"]) result = (this.registerA * this.registerA) >> 8;
    else if (instruction === CU_FLAGS["opp a.*b"]) result = (this.registerA * this.registerB) >> 8;
    else if (instruction === CU_FLAGS["opp a.*c"]) result = (this.registerA * this.registerC) >> 8;
    else if (instruction === CU_FLAGS["opp a.*d"]) result = (this.registerA * this.registerD) >> 8;
    else if (instruction === CU_FLAGS["opp b.*a"]) result = (this.registerB * this.registerA) >> 8;
    else if (instruction === CU_FLAGS["opp b.*b"]) result = (this.registerB * this.registerB) >> 8;
    else if (instruction === CU_FLAGS["opp b.*c"]) result = (this.registerB * this.registerC) >> 8;
    else if (instruction === CU_FLAGS["opp b.*d"]) result = (this.registerB * this.registerD) >> 8;
    else if (instruction === CU_FLAGS["opp c.*a"]) result = (this.registerC * this.registerA) >> 8;
    else if (instruction === CU_FLAGS["opp c.*b"]) result = (this.registerC * this.registerB) >> 8;
    else if (instruction === CU_FLAGS["opp c.*c"]) result = (this.registerC * this.registerC) >> 8;
    else if (instruction === CU_FLAGS["opp c.*d"]) result = (this.registerC * this.registerD) >> 8;
    else if (instruction === CU_FLAGS["opp d.*a"]) result = (this.registerD * this.registerA) >> 8;
    else if (instruction === CU_FLAGS["opp d.*b"]) result = (this.registerD * this.registerB) >> 8;
    else if (instruction === CU_FLAGS["opp d.*c"]) result = (this.registerD * this.registerC) >> 8;
    else if (instruction === CU_FLAGS["opp d.*d"]) result = (this.registerD * this.registerD) >> 8;

    // Update flags
    this.updateFlags(result);

    // Determine destination register based on operation type
    // For operations like "a+b", result goes to A
    // For operations like "b+a", result goes to B
    // For operations like "c+d", result goes to C
    // For operations like "d+c", result goes to D
    const destReg = this.getALUDestinationRegister(instruction);

    // Then mask to 8 bits for storage
    this.setRegisterByIndex(destReg, result & 0xff);
  }

  private getALUDestinationRegister(instruction: number): number {
    // Extract the first operand from the operation name
    // For example: "a+b" -> a, "b-c" -> b, etc.
    const opStr = Object.entries(CU_FLAGS).find(([_, value]) => value === instruction)?.[0] ?? "";
    if (!opStr.startsWith("opp ")) return 0; // Default to A if not found

    const firstOperand = opStr.charAt(4); // Get first character after "opp "
    switch (firstOperand) {
      case "a":
        return 0; // A register
      case "b":
        return 1; // B register
      case "c":
        return 2; // C register
      case "d":
        return 3; // D register
      default:
        return 0; // Default to A register
    }
  }

  private executeLoad(instruction: number) {
    let address: number;
    let value: number;
    let targetReg: number;

    if (instruction >= CU_FLAGS["load ram[a] a"] && instruction <= CU_FLAGS["load ram[d] d"]) {
      // Load from RAM using register address
      const addrReg = Math.floor((instruction - CU_FLAGS["load ram[a] a"]) / 4);
      targetReg = (instruction - CU_FLAGS["load ram[a] a"]) % 4;
      address = this.getRegisterByIndex(addrReg) + (this.ramPage << 8);
      value = this.ram[address & 0xff];
      this.setRegisterByIndex(targetReg, value);
    } else if (
      instruction >= CU_FLAGS["load rom a {number}"] &&
      instruction <= CU_FLAGS["load rom d {number}"]
    ) {
      // Load immediate value from ROM
      targetReg = instruction - CU_FLAGS["load rom a {number}"];
      value = this.rom[this.pc++];
      this.setRegisterByIndex(targetReg, value);
    } else if (
      instruction >= CU_FLAGS["load ram[{number}] a"] &&
      instruction <= CU_FLAGS["load ram[{number}] d"]
    ) {
      // Load from RAM using constant address
      targetReg = instruction - CU_FLAGS["load ram[{number}] a"];
      address = this.rom[this.pc++];
      value = this.ram[address];
      this.setRegisterByIndex(targetReg, value);
    } else if (
      instruction >= CU_FLAGS["set a rampage"] &&
      instruction <= CU_FLAGS["set d rampage"]
    ) {
      // Set RAM page
      const reg = instruction - CU_FLAGS["set a rampage"];
      this.ramPage = this.getRegisterByIndex(reg);
    }
  }

  private executeSave(instruction: number) {
    let address: number;
    let value: number;
    let sourceReg: number;

    if (instruction >= CU_FLAGS["save a mar"] && instruction <= CU_FLAGS["save d mar"]) {
      // Save to MAR
      sourceReg = instruction - CU_FLAGS["save a mar"];
      this.mar = this.getRegisterByIndex(sourceReg);
    } else if (
      instruction >= CU_FLAGS["save a ram[current]"] &&
      instruction <= CU_FLAGS["save d ram[current]"]
    ) {
      // Save to RAM at current MAR
      sourceReg = instruction - CU_FLAGS["save a ram[current]"];
      value = this.getRegisterByIndex(sourceReg);
      this.ram[this.mar] = value;
    } else if (
      instruction >= CU_FLAGS["save a ram[a]"] &&
      instruction <= CU_FLAGS["save d ram[d]"]
    ) {
      // Save to RAM using register address
      sourceReg = instruction - CU_FLAGS["save a ram[a]"];
      address = this.getRegisterByIndex(sourceReg);
      value = this.getRegisterByIndex(sourceReg);
      this.ram[address] = value;
    } else if (
      instruction >= CU_FLAGS["save a ram[{number}]"] &&
      instruction <= CU_FLAGS["save d ram[{number}]"]
    ) {
      // Save to RAM using constant address
      sourceReg = instruction - CU_FLAGS["save a ram[{number}]"];
      address = this.rom[this.pc++];
      value = this.getRegisterByIndex(sourceReg);
      this.ram[address] = value;
    }
  }

  private executeIO(instruction: number) {
    if (instruction >= CU_FLAGS["in a"] && instruction <= CU_FLAGS["in d"]) {
      const targetReg = instruction - CU_FLAGS["in a"];
      const value = this.inputCallback ? this.inputCallback() : 0;
      this.setRegisterValue(targetReg, value);
    } else if (instruction >= CU_FLAGS["out a"] && instruction <= CU_FLAGS["out d"]) {
      let value = this.getRegisterValue(instruction - CU_FLAGS["out a"]);
      // Convert to signed only if in signed mode and top bit is set
      if (this.signedMode && value & 0x80) value = value - 256;
      if (this.outputCallback) {
        this.outputCallback(value);
      }
    } else if (instruction === CU_FLAGS["out {number}"]) {
      // OUT immediate value
      const value = this.rom[this.pc++];
      if (this.outputCallback) {
        this.outputCallback(value);
      }
    } else if (instruction === CU_FLAGS["out ram[{number}]"]) {
      // OUT from RAM constant address
      const address = this.rom[this.pc++];
      if (this.outputCallback) {
        this.outputCallback(this.ram[address]);
      }
    } else if (instruction >= CU_FLAGS["out ram[a]"] && instruction <= CU_FLAGS["out ram[d]"]) {
      // OUT from RAM register address
      const reg = instruction - CU_FLAGS["out ram[a]"];
      const address = this.getRegisterByIndex(reg);
      if (this.outputCallback) {
        this.outputCallback(this.ram[address]);
      }
    }
  }

  private shouldJump(condition: number): boolean {
    switch (condition) {
      case 0x0:
        return true; // Unconditional
      case 0x1:
        return this.zeroFlag; // Equal
      case 0x2:
        return !this.zeroFlag; // Not Equal
      case 0x3:
        return this.carryFlag; // Less Than (unsigned)
      case 0x4:
        return this.carryFlag || this.zeroFlag; // Less Equal (unsigned)
      case 0x5:
        return !this.carryFlag && !this.zeroFlag; // Greater Than (unsigned)
      case 0x6:
        return !this.carryFlag; // Greater Equal (unsigned)
      case 0x7:
        return this.signFlag !== this.overflowFlag; // Less Than (signed)
      case 0x8:
        return this.signFlag !== this.overflowFlag || this.zeroFlag; // Less Equal (signed)
      case 0x9:
        return this.signFlag === this.overflowFlag && !this.zeroFlag; // Greater Than (signed)
      case 0xa:
        return this.signFlag === this.overflowFlag; // Greater Equal (signed)
      case 0xb:
        return this.zeroFlag; // Zero flag set
      case 0xc:
        return this.overflowFlag; // Overflow flag set
      case 0xd:
        return this.carryFlag; // Carry flag set
      case 0xe:
        return this.signFlag; // Sign flag set
      default:
        return false;
    }
  }

  private getRegisterByIndex(index: number): number {
    switch (index) {
      case 0:
        return this.registerA;
      case 1:
        return this.registerB;
      case 2:
        return this.registerC;
      case 3:
        return this.registerD;
      default:
        return 0;
    }
  }

  private setRegisterByIndex(index: number, value: number) {
    value &= 0xff; // Ensure 8-bit value
    switch (index) {
      case 0:
        this.registerA = value;
        break;
      case 1:
        this.registerB = value;
        break;
      case 2:
        this.registerC = value;
        break;
      case 3:
        this.registerD = value;
        break;
    }
  }

  private getConstantForCmp(type: number): number {
    switch (type) {
      case 0:
        return 0; // Compare with 0
      case 1:
        return 1; // Compare with 1
      case 2:
        return -1; // Compare with -1
      case 3:
        return 255; // Compare with 255
      default:
        return 0;
    }
  }

  private getRegisterValue(index: number): number {
    return this.getRegisterByIndex(index);
  }

  private setRegisterValue(index: number, value: number) {
    this.setRegisterByIndex(index, value);
  }

  setOutputCallback(callback: (value: number) => void) {
    this.outputCallback = callback;
  }

  setInputCallback(callback: () => number) {
    this.inputCallback = callback;
  }

  // Debug methods
  getRegisterA(): number {
    return this.registerA;
  }
  getRegisterB(): number {
    return this.registerB;
  }
  getRegisterC(): number {
    return this.registerC;
  }
  getRegisterD(): number {
    return this.registerD;
  }
  getRam(): number[] {
    return this.ram;
  }
  getProgramCounter(): number {
    return this.pc;
  }
  getCurrentInstruction(): number {
    return this.rom[this.pc];
  }
  getFlags(): { z: boolean; o: boolean; c: boolean; s: boolean } {
    return {
      z: this.zeroFlag,
      o: this.overflowFlag,
      c: this.carryFlag,
      s: this.signFlag,
    };
  }
}
