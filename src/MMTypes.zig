const std = @import("std");
const builtin = @import("builtin");

const MMTypes = @This();

pub const Script = struct {
    up_to_date_script: ?ResourceIdentifier,
    class_name: []const u8,
    super_class_script: ?ResourceIdentifier,
    modifiers: ?u32,
    type_references: []const TypeReference,
    field_references: []const FieldReference,
    function_references: []const FunctionReference,
    field_definitions: []const FieldDefinition,
    property_definitions: []const PropertyDefinition,
    functions: []const FunctionDefinition,
    a_string_table: AStringTable,
    w_string_table: WStringTable,
    constant_table_s64: ?[]const i64,
    constant_table_float: []const f32,
    depending_guids: ?[]const u32,
    bytecode: []const Bytecode,
    arguments: []const Argument,
    line_numbers: []const u16,
    local_variables: []const LocalVariable,

    pub fn deinit(self: *const Script, allocator: std.mem.Allocator) void {
        allocator.free(self.class_name);
        allocator.free(self.type_references);
        allocator.free(self.field_references);
        allocator.free(self.function_references);
        allocator.free(self.field_definitions);
        allocator.free(self.property_definitions);
        allocator.free(self.functions);
        self.a_string_table.deinit(allocator);
        self.w_string_table.deinit(allocator);
        if (self.constant_table_s64) |constant_table_s64|
            allocator.free(constant_table_s64);
        allocator.free(self.constant_table_float);
        if (self.depending_guids) |depending_guids|
            allocator.free(depending_guids);
        allocator.free(self.bytecode);
        allocator.free(self.arguments);
        allocator.free(self.line_numbers);
        allocator.free(self.local_variables);
    }
};

pub const NopClass = packed struct(u48) {
    _unused: u48 = undefined,
};

pub const LoadConstClass = packed struct(u48) {
    dst_idx: u16,
    constant_idx: u32,
};

pub const CastClass = packed struct(u48) {
    dst_idx: u16,
    src_idx: u16,
    type_idx: u16,
};

/// Used for instructions with a single source and a single destination register
pub const UnaryClass = packed struct(u48) {
    dst_idx: u16,
    src_idx: u16,
    _unused: u16 = undefined,
};

/// Used for instructions with two source registers and one destination register
pub const BinaryClass = packed struct(u48) {
    dst_idx: u16,
    src_a_idx: u16,
    src_b_idx: u16,
};

pub const GetBuiltinMemberClass = packed struct(u48) {
    dst_idx: u16,
    base_idx: u16,
    _unused: u16 = undefined,
};

pub const SetBuiltinMemberClass = packed struct(u48) {
    src_idx: u16,
    base_idx: u16,
    _unused: u16 = undefined,
};

pub const GetMemberClass = packed struct(u48) {
    dst_idx: u16,
    base_idx: u16,
    field_ref: u16,
};

pub const SetMemberClass = packed struct(u48) {
    src_idx: u16,
    base_idx: u16,
    field_ref: u16,
};

pub const GetElementClass = packed struct(u48) {
    dst_idx: u16,
    base_idx: u16,
    src_or_index_idx: u16,
};

pub const SetElementClass = packed struct(u48) {
    src_idx: u16,
    base_idx: u16,
    index_idx: u16,
};

pub const NewObjectClass = packed struct(u48) {
    dst_idx: u16,
    _unused: u16 = undefined,
    type_idx: u16,
};

pub const NewArrayClass = packed struct(u48) {
    dst_idx: u16,
    size_idx: u16,
    type_idx: u16,
};

pub const WriteClass = packed struct(u48) {
    _unused1: u16 = undefined,
    src_idx: u16,
    _unused2: u16 = undefined,
};

pub const ArgClass = packed struct(u48) {
    src_idx: u16,
    arg_idx: u16,
    _unused: u16 = undefined,
};

pub const CallClass = packed struct(u48) {
    dst_idx: u16,
    call_idx: u16,
    _unused: u16 = undefined,
};

pub const ReturnClass = packed struct(u48) {
    _unused1: u16 = undefined,
    src_idx: u16,
    _unused2: u16 = undefined,
};

pub const BranchClass = packed struct(u48) {
    src_idx: u16,
    branch_offset: i32,
};

pub const Bytecode = packed struct(u64) {
    op: InstructionType,
    type: MachineType,
    params: InstructionParams,

    pub inline fn init(instr: TaggedInstruction, machine_type: MachineType) Bytecode {
        const op, const params = instr.destructure();
        return .{
            .op = op,
            .type = machine_type,
            .params = params,
        };
    }
};

pub const InstructionType = @typeInfo(TaggedInstruction).Union.tag_type.?;
pub const InstructionParams = @Type(.{ .Union = blk: {
    var info = @typeInfo(TaggedInstruction).Union;
    info.tag_type = null;
    info.layout = .@"packed";
    info.decls = &.{};
    break :blk info;
} });
pub const TaggedInstruction = union(enum(u8)) {
    /// Does nothing, progresses to the next instruction
    NOP: NopClass = 0x0,
    /// Loads a boolean into the destination register,
    /// storing a 1 for true, and 0 for false.
    /// The result is a single byte
    LCb: LoadConstClass = 0x1,
    /// Loads a 16-bit integer into the destination register,
    /// This directly uses the upper 16-bits of the constant_idx as the loaded constant
    LCc: LoadConstClass = 0x2,
    /// Loads a 32-bit integer into a the destination register,
    /// This directly uses the constant_idx as the loaded constant
    LCi: LoadConstClass = 0x3,
    /// Loads a 32-bit floating point number into the destination register
    /// This directly uses the constant_idx as the loaded constant
    LCf: LoadConstClass = 0x4,
    /// Loads the 32-bit pointer to a string into the destination register
    /// This pulls from the wide-string table
    LCsw: LoadConstClass = 0x5,
    /// Loads a 32-bit null pointer into the destination register
    LC_NULLsp: LoadConstClass = 0x6,
    /// Moves a single byte from the source register into the destination register
    MOVb: UnaryClass = 0x7,
    /// Negates the 1-byte boolean at the source register,
    /// storing the result in the destination register as a 1-byte boolean
    LOG_NEGb: UnaryClass = 0x8,
    /// Moves a two byte integer from the source register into the destination register
    MOVc: UnaryClass = 0x9,
    /// Moves a four-byte integer from the source register into the destination register
    MOVi: UnaryClass = 0xa,
    /// Increments the signed 32-bit integer at the source register,
    /// storing the result as a signed 32-bit integer into the destination register
    INCi: UnaryClass = 0xb,
    /// Decrements the signed 32-bit integer at the source register,
    /// storing the result as a signed 32-bit integer into the destination register
    DECi: UnaryClass = 0xc,
    /// Negates the signed 32-bit integer at the source register (eg `-val`),
    /// storing the result as a signed 32-bit integer into the destination register
    NEGi: UnaryClass = 0xd,
    /// Does a bitwise negation of the 4-byte region of data stored at the source register
    /// storing the result into the destination register
    BIT_NEGi: UnaryClass = 0xe,
    /// Does a logical negation of the 32-bit integer stored at the source register,
    /// eg. turning a 1 into a 0, and a 0 into a 1
    LOG_NEGi: UnaryClass = 0xf,
    /// Gets the absolute value of the 32-bit integer stored at the source register,
    /// storing the result in the destination register
    ABSi: UnaryClass = 0x10,
    /// Moves a 32-bit float from the source register into the destination register
    MOVf: UnaryClass = 0x11,
    /// Negates the 32-bit float stored at the source register (eg. `-val`),
    /// storing the result in the destination register
    NEGf: UnaryClass = 0x12,
    /// Gets the absolute value of the 32-bit float stored at the source register
    /// storing the result in the destination register
    ABSf: UnaryClass = 0x13,
    /// Gets the square root of the 32-bit float stored at the source register
    /// storing the result in the destination register
    SQRTf: UnaryClass = 0x14,
    /// Does a sine operation on the 32-bit float stored at the source register,
    /// first, the value is cast to a double before the operation takes place,
    /// then the result of the operation is cast back to a 32-bit integer,
    /// and stored in the destination register as a 32-bit float
    SINf: UnaryClass = 0x15,
    /// Does a cosine operation on the 32-bit float stored at the source register,
    /// first, the value is cast to a double before the operation takes place,
    /// then the result of the operationis cast back to a 32-bit integer,
    /// and stored in the destination register as a 32-bit float
    COSf: UnaryClass = 0x16,
    /// Does a tangent operation on the 32-bit float stored at the source register,
    /// storing the result in the destination register as a 32-bit float
    TANf: UnaryClass = 0x17,
    /// Moves a v4 from the source register to the destination register
    /// Both registers are rounded *down* to the nearest multiple of 16, due to AltiVec requirements
    MOVv4: UnaryClass = 0x18,
    /// Negates the four f32 elements in the vector (eg `-val`)
    /// Storing the result in the destination register
    NEGv4: UnaryClass = 0x19,
    /// Moves the m44 matrix from the source register into the destination register
    MOVm44: UnaryClass = 0x1a,
    /// Treated as a NOP
    IT_MOV_S_DEPRECATED: NopClass = 0x1b,
    /// Moves a 4-byte raw_ptr from the source register into the destination register
    MOVrp: UnaryClass = 0x1c,
    /// Treated as a NOP
    MOVcp: UnaryClass = 0x1d,
    /// Moves a 4-byte safe_ptr from the source register into the destination register
    MOVsp: UnaryClass = 0x1e,
    /// Moves a 4-byte object_ref from the source register into the destination register
    MOVo: UnaryClass = 0x1f,
    /// Compares if the booleans stored at the source registers are equal,
    /// storing into the destination register as a boolean
    EQb: BinaryClass = 0x20,
    /// Compares if the booleans stored at the source registers are not equal,
    /// storing into the destination register as a boolean
    NEb: BinaryClass = 0x21,
    /// Seems to trigger a non-fatal "invalid instruction" message
    IT_RESERVED0_C: BinaryClass = 0x22,
    /// Seems to trigger a non-fatal "invalid instruction" message
    IT_RESERVED1_C: BinaryClass = 0x23,
    /// Compares two chars, checking if the value stored in src_a
    /// is less than the value stored in src_b
    ///
    /// Stores the result into the destination register as a boolean
    LTc: BinaryClass = 0x24,
    /// Compares two chars, checking if the value stored in src_a
    /// is less than or equal to the value stored in src_b
    ///
    /// Stores the result into the destination register as a boolean
    LTEc: BinaryClass = 0x25,
    /// Compares two chars, checking if the value stored in src_a
    /// is greater than the value stored in src_b
    ///
    /// Stores the result into the destination register as a boolean
    GTc: BinaryClass = 0x26,
    /// Compares two chars, checking if the value stored in src_a
    /// is greater than or equal to the value stored in src_b
    ///
    /// Stores the result into the destination register as a boolean
    GTEc: BinaryClass = 0x27,
    /// Compares if the chars stored at the source registers are equal,
    /// storing into the destination register as a boolean
    EQc: BinaryClass = 0x28,
    /// Compares if the chars stored at the source registers are not equal,
    /// storing into the destination register as a boolean
    NEc: BinaryClass = 0x29,
    /// Adds two signed 32-bit integers together, storing the result in the destionation register
    ADDi: BinaryClass = 0x2a,
    /// Subtracts two 32-bit integers from each other, storing a 32-bit integer result.
    /// Subtracting src_b_idx from src_a_idx, and storing the result into dst_idx
    SUBi: BinaryClass = 0x2b,
    /// Multiplies two 32-bit ingeters with eachother, storing a 32-bit integer result in dst_idx
    MULi: BinaryClass = 0x2c,
    /// Divides two 32-bit ingeters, storing the result as a 32-bit integer
    /// Divides src_a by src_b
    DIVi: BinaryClass = 0x2d,
    /// Performs modulo on two signed 32-bit integers, storing the result as a signed 32-bit integer
    /// Operation is as follows: dst = src_a % src_b
    MODi: BinaryClass = 0x2e,
    /// Reads two signed 32-bit integers from the source registers,
    /// storing the smaller value in the destination register as a signed 32-bit integer
    MINi: BinaryClass = 0x2f,
    /// Reads two signed 32-bit integers from the source registers,
    /// storing the larger value in the destination register as a signed 32-bit integer
    MAXi: BinaryClass = 0x30,
    /// Loads a signed 32-bit integer from src_a and src_b,
    /// masking src_b with 0x11111, then shifts src_a left by the masked value,
    /// storing the result in dst_idx
    ///
    /// Zeroes are shifted in.
    SLAi: BinaryClass = 0x31,
    /// Loads a signed 32-bit integer from src_a and src_b,
    /// masking src_b with 0x11111, then shifts src_a right by the masked value,
    /// storing the result as a signed 32-bit integer  in dst_idx
    ///
    /// The highest bit is shifted in.
    SRAi: BinaryClass = 0x32,
    /// Loads a signed 32-bit integer from src_a and src_b,
    /// masking src_b with 0x11111, then shifts src_a right by the masked value,
    /// storing the result as a signed 32-bit integer in dst_idx
    ///
    /// Zeroes are shifted in.
    SRLi: BinaryClass = 0x33,
    /// Loads a signed 32-bit integer from src_a and src_b,
    /// then does a bitwise OR on the values, storing the result in dst_idx
    BIT_ORi: BinaryClass = 0x34,
    /// Loads a signed 32-bit integer from src_a and src_b,
    /// then does a bitwise AND on the values, storing the result in dst_idx
    BIT_ANDi: BinaryClass = 0x35,
    /// Loads a signed 32-bit integer from src_a and src_b,
    /// then does a bitwise XOR on the values, storing the result in dst_idx
    BIT_XORi: BinaryClass = 0x36,
    /// Loads a signed 32-bit integer from src_a and src_b,
    /// then compares whether src_a < src_b,
    /// then storing the result into dst_idx as a 32-bit signed integer
    ///
    /// The result is 1 if true, 0 if false
    LTi: BinaryClass = 0x37,
    /// Loads a signed 32-bit integer from src_a and src_b,
    /// then compares whether src_a <= src_b,
    /// then storing the result into dst_idx as a 32-bit signed integer
    ///
    /// The result is 1 if true, 0 if false
    LTEi: BinaryClass = 0x38,
    /// Loads a signed 32-bit integer from src_a and src_b,
    /// then compares whether src_a > src_b,
    /// then storing the result into dst_idx as a 32-bit signed integer
    ///
    /// The result is 1 if true, 0 if false
    GTi: BinaryClass = 0x39,
    /// Loads a signed 32-bit integer from src_a and src_b,
    /// then compares whether src_a >= src_b,
    /// then storing the result into dst_idx as a 32-bit signed integer
    ///
    /// The result is 1 if true, 0 if false
    GTEi: BinaryClass = 0x3a,
    /// Loads a signed 32-bit integer from src_a and src_b,
    /// then compares whether src_a == src_b,
    /// then storing the result into dst_idx as a single byte (?)
    ///
    /// The result is 1 if true, 0 if false
    EQi: BinaryClass = 0x3b,
    /// Loads a signed 32-bit integer from src_a and src_b,
    /// then compares whether src_a != src_b,
    /// then storing the result into dst_idx as a single byte (?)
    ///
    /// The result is 1 if true, 0 if false
    NEi: BinaryClass = 0x3c,
    /// Adds the two 32-bit floats stored at the source registers together,
    /// then stores the result in the destination register as a 32-bit float
    ADDf: BinaryClass = 0x3d,
    /// Subtracts the 32-bit float from the src_b register from the src_a register (eg. `*src_a - *src_b`),
    /// then stores the result in the destination register as a 32-bit float
    SUBf: BinaryClass = 0x3e,
    /// Multiplies the two 32-bit floats stored in the source registers,
    /// then stores the result in the destination register
    MULf: BinaryClass = 0x3f,
    /// Divides the 32-bit float stored in src_a by the 32-bit float stored in src_b (eg. *src_a / *src_b),
    /// then stores the result in the destination register
    DIVf: BinaryClass = 0x40,
    /// Stores the lower 32-bit float of the two source registers into the destination register
    MINf: BinaryClass = 0x41,
    /// Stores the higher 32-bit float of the two source registers into the destination register
    MAXf: BinaryClass = 0x42,
    /// Compares whether the 32-bit float stored at src_a is less than the 32-bit float stored at src_b
    /// Stores the result as a boolean into the destination register
    LTf: BinaryClass = 0x43,
    /// Compares whether the 32-bit float stored at src_a is less than or equal to the 32-bit float stored at src_b
    /// Stores the result as a boolean into the destination register
    LTEf: BinaryClass = 0x44,
    /// Compares whether the 32-bit float stored at src_a is greater than the 32-bit float stored at src_b
    /// Stores the result as a boolean into the destination register
    GTf: BinaryClass = 0x45,
    /// Compares whether the 32-bit float stored at src_a is greater than or equal to the 32-bit float stored at src_b
    /// Stores the result as a boolean into the destination register
    GTEf: BinaryClass = 0x46,
    /// Compares whether the two 32-bit floats in the source registers are equal,
    /// storing the result as a boolean in the destination register
    EQf: BinaryClass = 0x47,
    /// Compares whether the two 32-bit floats in the source registers are not equal,
    /// storing the result as a boolean in the destination register
    NEf: BinaryClass = 0x48,
    /// Adds the four 32-bit floating point numbers in the src_a register with the ones in the src_b register,
    /// storing the result in the destination register
    ///
    /// The source and destination registers are rounded *down* to the nearest multiple of 16, due to Altivec requirements
    ADDv4: BinaryClass = 0x49,
    /// Subtracts the four 32-bit floating point numbers in the src_b register from the ones in the src_b register,
    /// storing the result in the destination register (eg. *src_a - *src_b)
    ///
    /// The source and destination registers are rounded *down* to the nearest multiple of 16, due to Altivec requirements
    SUBv4: BinaryClass = 0x4a,
    /// TODO: 0x00217b98
    MULSv4: BinaryClass = 0x4b,
    /// TODO: 0x00217b1c
    DIVSv4: BinaryClass = 0x4c,
    /// Does a dot-product of two 4-element vectors stored at src_a and src_b,
    /// and stores the result as a 32-bit floating point number in the destination register
    ///
    /// Due to AltiVec requirements, the source registers are rounded *down* to the nearest multiple of 16,
    /// and the destination register is rounded *down* to the nearest multiple of 4
    DOT4v4: BinaryClass = 0x4d,
    /// Does a dot product of the rightmost three elements stored in both vectors,
    /// storing the result as a 32-bit float in the destination register
    ///
    /// Due to AltiVec requirements, the source registers are rounded *down* to the nearest multiple of 16,
    /// and the destination register is rounded *down* to the nearest multiple of 4
    DOT3v4: BinaryClass = 0x4e,
    /// Does a dot product on the rightmost two elements stored in both vectors,
    /// storing the result as a 32-bit float in the destination register
    ///
    /// Due to AltiVec requirements, the source registers are rounded *down* to the nearest multiple of 16,
    /// and the destination register is rounded *down* to the nearest multiple of 4
    DOT2v4: BinaryClass = 0x4f,
    /// Does a cross product on the vectors stored in the two input registers,
    /// storing the result vector in the destination register
    ///
    /// Due to AltiVec requirements, the source and destination registers
    /// are rounded *down* to the nearest multiple of 16
    CROSS3v4: BinaryClass = 0x50,
    /// Multiplies two 4x4 matrices of f32 together.
    /// Stores the result in the destination register.
    ///
    /// Due to AltiVec requirements, the source and destination registers
    /// are rounded *down* to the nearest multiple of 16
    MULm44: BinaryClass = 0x51,
    /// Treated as a NOP
    IT_EQ_S_DEPRECATED: NopClass = 0x52,
    /// Treated as a NOP
    IT_NE_S_DEPRECATED: NopClass = 0x53,
    /// Compares if the two 32-bit values stored in the source registers are equal,
    /// storing the result in the destination register as a boolean
    EQrp: BinaryClass = 0x54,
    /// Compares if the two 32-bit values stored in the source registers are not equal,
    /// storing the result in the destination register as a boolean
    NErp: BinaryClass = 0x55,
    /// Compares if the two 32-bit values stored in the source registers are equal,
    /// storing the result in the destination register as a boolean
    EQo: BinaryClass = 0x56,
    /// Compares if the two 32-bit values stored in the source registers are not equal,
    /// storing the result in the destination register as a boolean
    NEo: BinaryClass = 0x57,
    /// Gets the Things that are located at the two safe_ptrs in the source registers,
    /// and checks if they are equal
    /// Stores the result in the destination register as a boolean
    EQsp: BinaryClass = 0x58,
    /// Gets the Things that are located at the two safe_ptrs in the source registers,
    /// and checks if they are not equal
    /// Stores the result in the destination register as a boolean
    NEsp: BinaryClass = 0x59,
    /// Gets the X [0] member of the v4 specified in the base register,
    /// stores the result in the destination register as an f32
    GET_V4_X: GetBuiltinMemberClass = 0x5a,
    /// Gets the Y [1] member of the v4 specified in the base register,
    /// stores the result in the destination register as an f32
    GET_V4_Y: GetBuiltinMemberClass = 0x5b,
    /// Gets the Z [2] member of the v4 specified in the base register,
    /// stores the result in the destination register as an f32
    GET_V4_Z: GetBuiltinMemberClass = 0x5c,
    /// Gets the W [3] member of the v4 specified in the base register,
    /// stores the result in the destination register as an f32
    GET_V4_W: GetBuiltinMemberClass = 0x5d,
    GET_V4_LEN2: GetBuiltinMemberClass = 0x5e,
    GET_V4_LEN3: GetBuiltinMemberClass = 0x5f,
    GET_V4_LEN4: GetBuiltinMemberClass = 0x60,
    GET_M44_XX: GetBuiltinMemberClass = 0x61,
    GET_M44_XY: GetBuiltinMemberClass = 0x62,
    GET_M44_XZ: GetBuiltinMemberClass = 0x63,
    GET_M44_XW: GetBuiltinMemberClass = 0x64,
    GET_M44_YX: GetBuiltinMemberClass = 0x65,
    GET_M44_YY: GetBuiltinMemberClass = 0x66,
    GET_M44_YZ: GetBuiltinMemberClass = 0x67,
    GET_M44_YW: GetBuiltinMemberClass = 0x68,
    GET_M44_ZX: GetBuiltinMemberClass = 0x69,
    GET_M44_ZY: GetBuiltinMemberClass = 0x6a,
    GET_M44_ZZ: GetBuiltinMemberClass = 0x6b,
    GET_M44_ZW: GetBuiltinMemberClass = 0x6c,
    GET_M44_WX: GetBuiltinMemberClass = 0x6d,
    GET_M44_WY: GetBuiltinMemberClass = 0x6e,
    GET_M44_WZ: GetBuiltinMemberClass = 0x6f,
    GET_M44_WW: GetBuiltinMemberClass = 0x70,
    GET_M44_rX: GetBuiltinMemberClass = 0x71,
    GET_M44_rY: GetBuiltinMemberClass = 0x72,
    GET_M44_rZ: GetBuiltinMemberClass = 0x73,
    GET_M44_rW: GetBuiltinMemberClass = 0x74,
    GET_M44_cX: GetBuiltinMemberClass = 0x75,
    GET_M44_cY: GetBuiltinMemberClass = 0x76,
    GET_M44_cZ: GetBuiltinMemberClass = 0x77,
    GET_M44_cW: GetBuiltinMemberClass = 0x78,
    SET_V4_X: SetBuiltinMemberClass = 0x79,
    SET_V4_Y: SetBuiltinMemberClass = 0x7a,
    SET_V4_Z: SetBuiltinMemberClass = 0x7b,
    SET_V4_W: SetBuiltinMemberClass = 0x7c,
    SET_M44_XX: SetBuiltinMemberClass = 0x7d,
    SET_M44_XY: SetBuiltinMemberClass = 0x7e,
    SET_M44_XZ: SetBuiltinMemberClass = 0x7f,
    SET_M44_XW: SetBuiltinMemberClass = 0x80,
    SET_M44_YX: SetBuiltinMemberClass = 0x81,
    SET_M44_YY: SetBuiltinMemberClass = 0x82,
    SET_M44_YZ: SetBuiltinMemberClass = 0x83,
    SET_M44_YW: SetBuiltinMemberClass = 0x84,
    SET_M44_ZX: SetBuiltinMemberClass = 0x85,
    SET_M44_ZY: SetBuiltinMemberClass = 0x86,
    SET_M44_ZZ: SetBuiltinMemberClass = 0x87,
    SET_M44_ZW: SetBuiltinMemberClass = 0x88,
    SET_M44_WX: SetBuiltinMemberClass = 0x89,
    SET_M44_WY: SetBuiltinMemberClass = 0x8a,
    SET_M44_WZ: SetBuiltinMemberClass = 0x8b,
    SET_M44_WW: SetBuiltinMemberClass = 0x8c,
    SET_M44_rX: SetBuiltinMemberClass = 0x8d,
    SET_M44_rY: SetBuiltinMemberClass = 0x8e,
    SET_M44_rZ: SetBuiltinMemberClass = 0x8f,
    SET_M44_rW: SetBuiltinMemberClass = 0x90,
    SET_M44_cX: SetBuiltinMemberClass = 0x91,
    SET_M44_cY: SetBuiltinMemberClass = 0x92,
    SET_M44_cZ: SetBuiltinMemberClass = 0x93,
    SET_M44_cW: SetBuiltinMemberClass = 0x94,
    GET_SP_MEMBER: GetMemberClass = 0x95,
    GET_RP_MEMBER: GetMemberClass = 0x96,
    SET_SP_MEMBER: SetMemberClass = 0x97,
    SET_RP_MEMBER: SetMemberClass = 0x98,
    GET_ELEMENT: GetElementClass = 0x99,
    SET_ELEMENT: SetElementClass = 0x9a,
    GET_ARRAY_LEN: GetBuiltinMemberClass = 0x9b,
    NEW_ARRAY: NewArrayClass = 0x9c,
    ARRAY_INSERT: SetElementClass = 0x9d,
    ARRAY_APPEND: SetElementClass = 0x9e,
    ARRAY_ERASE: SetElementClass = 0x9f,
    ARRAY_FIND: GetElementClass = 0xa0,
    ARRAY_CLEAR: SetElementClass = 0xa1,
    WRITE: WriteClass = 0xa2,
    /// Loads the specified register into the specified argument register
    ///
    /// The data loaded depends on the machine type of the instruction.
    ///
    /// If the destination register is a0 and the machine type is safe_ptr
    /// it does something idk look at 218c14 in ghidra in deploy
    /// its maybe a special "pointer to self" if I had to guess?
    /// Its set to the CThing GUID when preparing a non-static function,
    /// so its *probably* the self ptr or the attached GUID of the function if I had to guess.
    ///
    /// void       - No load takes place
    /// bool       - Loads one byte
    /// char       - Loads two bytes
    /// s32        - Loads four bytes
    /// f32        - Loads four bytes
    /// v4         - Loads sixteen bytes, rounding *down* the src and dst registers
    ///              to the nearest multiple of 16, due to Altivec requirements.
    /// m44        - Loads four packed v4 (total of 64 bytes), rounding *down* the src and dst registers
    ///              to the nearest multiple of 16, due to Altivec requirements.
    /// deprecated - No load takes place
    /// raw_ptr    - Loaded as s32
    /// ref_ptr    - No load takes place
    /// safe_ptr   - Loaded as s32
    /// object_ref - Loaded as s32
    /// s64        - Loads eight bytes
    /// f64        - Loads eight bytes
    ARG: ArgClass = 0xa3,
    /// Calls the function specified by call_idx, storing the return value inside of dst_idx
    CALL: CallClass = 0xa4,
    RET: ReturnClass = 0xa5,
    /// Unconditional relative branch, with the offset specified
    B: BranchClass = 0xa6,
    /// Branches if the byte in the specified register is equal to zero
    BEZ: BranchClass = 0xa7,
    /// Branches if the byte in the specified register is not equal to zero
    BNEZ: BranchClass = 0xa8,
    CASTsp: CastClass = 0xa9,
    INTb: UnaryClass = 0xaa,
    INTc: UnaryClass = 0xab,
    INTf: UnaryClass = 0xac,
    FLOATb: UnaryClass = 0xad,
    FLOATc: UnaryClass = 0xae,
    FLOATi: UnaryClass = 0xaf,
    BOOLc: UnaryClass = 0xb0,
    BOOLi: UnaryClass = 0xb1,
    BOOLf: UnaryClass = 0xb2,
    GET_OBJ_MEMBER: GetMemberClass = 0xb3,
    SET_OBJ_MEMBER: SetMemberClass = 0xb4,
    NEW_OBJECT: NewObjectClass = 0xb5,
    ARRAY_RESIZE: SetElementClass = 0xb6,
    ARRAY_RESERVE: SetElementClass = 0xb7,
    LCv4: LoadConstClass = 0xb8,
    LC_NULLo: LoadConstClass = 0xb9,
    CASTo: CastClass = 0xba,
    GET_SP_NATIVE_MEMBER: GetMemberClass = 0xbb,
    LCsa: LoadConstClass = 0xbc,
    BIT_ORb: BinaryClass = 0xbd,
    BIT_ANDb: BinaryClass = 0xbe,
    BIT_XORb: BinaryClass = 0xbf,
    CALLVo: CallClass = 0xc0,
    CALLVsp: CallClass = 0xc1,
    ASSERT: WriteClass = 0xc2,

    pub inline fn destructure(tagged: TaggedInstruction) struct { InstructionType, InstructionParams } {
        return .{
            tagged,
            switch (tagged) {
                inline else => |payload, itag| @unionInit(InstructionParams, @tagName(itag), payload),
            },
        };
    }

    pub inline fn from(tag: InstructionType, payload: InstructionParams) TaggedInstruction {
        return switch (tag) {
            inline else => |itag| @unionInit(TaggedInstruction, @tagName(itag), @field(payload, @tagName(itag))),
        };
    }
};

pub const AStringTable = struct {
    buf: []const u8,
    strings: []const [:0]const u8,

    pub fn deinit(self: AStringTable, allocator: std.mem.Allocator) void {
        allocator.free(self.strings);
        allocator.free(self.buf);
    }
};

pub const WStringTable = struct {
    buf: []const u16,
    strings: []const [:0]const u16,

    pub fn deinit(self: WStringTable, allocator: std.mem.Allocator) void {
        allocator.free(self.strings);
        allocator.free(self.buf);
    }
};

const ResolvableTypeReference = u32;

const ResolvableString = u32;

const ResolvableFunction = u32;

const ArgumentSlice = struct {
    begin: u32,
    end: u32,

    pub inline fn len(self: ArgumentSlice) u32 {
        return self.end - self.begin;
    }

    pub fn slice(self: ArgumentSlice, source: []const Argument) []const Argument {
        return source[self.begin..self.end];
    }
};

const ResolvableBytecodeSlice = struct {
    begin: u32,
    end: u32,

    pub inline fn len(self: ResolvableBytecodeSlice) u32 {
        return self.end - self.begin;
    }

    pub fn slice(self: ResolvableBytecodeSlice, source: []const Bytecode) []const Bytecode {
        return source[self.begin..self.end];
    }
};

const ResolvableLineNumberSlice = struct {
    begin: u32,
    end: u32,

    pub inline fn len(self: ResolvableLineNumberSlice) u32 {
        return self.end - self.begin;
    }

    pub fn slice(self: ResolvableLineNumberSlice, source: []const u16) []const u16 {
        return source[self.begin..self.end];
    }
};

const ResolvableLocalVariableSlice = struct {
    begin: u32,
    end: u32,

    pub inline fn len(self: ResolvableLocalVariableSlice) u32 {
        return self.end - self.begin;
    }

    pub fn slice(self: ResolvableLocalVariableSlice, source: []const LocalVariable) []const LocalVariable {
        return source[self.begin..self.end];
    }
};

pub const FunctionDefinition = struct {
    modifiers: Modifiers,
    type_reference: ResolvableTypeReference,
    name: ResolvableString,
    arguments: ArgumentSlice,
    bytecode: ResolvableBytecodeSlice,
    line_numbers: ResolvableLineNumberSlice,
    local_variables: ResolvableLocalVariableSlice,
    stack_size: u32,
};

const Function = struct {
    modifiers: u32,
    type_reference: ResolvableTypeReference,
    name: ResolvableString,
    arguments: []const Argument,
    bytecode: []const u64,
    line_numbers: []const u16,
    local_variables: []const LocalVariable,
    stack_size: u32,
};

pub const LocalVariable = struct {
    modifiers: u32,
    type_reference: ResolvableTypeReference,
    name: ResolvableString,
    offset: u32,
};

pub const Argument = struct {
    type_reference: ResolvableTypeReference,
    offset: u32,
};

pub const PropertyDefinition = struct {
    modifiers: u32,
    type_reference: ResolvableTypeReference,
    name: ResolvableString,
    get_function: ResolvableFunction,
    set_function: ResolvableFunction,
};

pub const Modifiers = packed struct(u32) {
    static: bool,
    native: bool,
    ephemeral: bool,
    pinned: bool,
    @"const": bool,
    public: bool,
    protected: bool,
    private: bool,
    property: bool,
    abstract: bool,
    virtual: bool,
    override: bool,
    divergent: bool,
    _unused: u19,
};

pub const FieldDefinition = struct {
    modifiers: Modifiers,
    type_reference: ResolvableTypeReference,
    name: ResolvableString,
};

pub const FunctionReference = struct {
    type_reference: ResolvableTypeReference,
    name: ResolvableString,
};

pub const FieldReference = struct {
    type_reference: ResolvableTypeReference,
    name: ResolvableString,
};

pub const TypeReference = struct {
    machine_type: MachineType,
    fish_type: FishType,
    dimension_count: u8,
    array_base_machine_type: MachineType,
    script: ?ResourceIdentifier,
    type_name: ResolvableString,
};

pub const Revision = struct {
    head: u32,
    branch_id: u16,
    branch_revision: u16,
};

pub const ResourceType = GeneratedTypes.ResourceType;
pub const headerToResourceType = GeneratedTypes.headerToResourceType;
pub const resourceTypeToHeader = GeneratedTypes.resourceTypeToHeader;

const GeneratedTypes = GenerateResourceType(.{
    .{ "invalid", null, 0 },
    .{ "texture", "TEX", 1 },
    // .{ "gtf_texture", "GTF", 1 },
    // .{ "gxt_texture", "GXT", 1 },
    .{ "mesh", "MSH", 2 },
    .{ "pixel_shader", null, 3 },
    .{ "vertex_shader", null, 4 },
    .{ "animation", "ANM", 5 },
    .{ "guid_substitution", "GSB", 6 },
    .{ "gfx_material", "GMT", 7 },
    .{ "spu_elf", null, 8 },
    .{ "level", "LVL", 9 },
    .{ "filename", null, 10 },
    .{ "script", "FSH", 11 },
    .{ "settings_character", "CHA", 12 },
    .{ "file_of_bytes", null, 13 },
    .{ "settings_soft_phys", "SSP", 14 },
    .{ "fontface", "FNT", 15 },
    .{ "material", "MAT", 16 },
    .{ "downloadable_content", "DLC", 17 },
    .{ "editor_settings", null, 18 },
    .{ "joint", "JNT", 19 },
    .{ "game_constants", "CON", 20 },
    .{ "poppet_settings", "POP", 21 },
    .{ "cached_level_data", "CLD", 22 },
    .{ "synced_profile", "PRF", 23 },
    .{ "bevel", "BEV", 24 },
    .{ "game", "GAM", 25 },
    .{ "settings_network", "NWS", 26 },
    .{ "packs", "PCK", 27 },
    .{ "big_profile", "BPR", 28 },
    .{ "slot_list", "SLT", 29 },
    .{ "translation", null, 30 },
    .{ "adventure_create_profile", "ADC", 31 },
    .{ "local_profile", "IPR", 32 },
    .{ "limits_settings", "LMT", 33 },
    .{ "tutorials", "TUT", 34 },
    .{ "guid_list", "GLT", 35 },
    .{ "audio_materials", "AUM", 36 },
    .{ "settings_fluid", "SSF", 37 },
    .{ "plan", "PLN", 38 },
    .{ "texture_list", "TXL", 39 },
    .{ "music_settings", "MUS", 40 },
    .{ "mixer_settings", "MIX", 41 },
    .{ "replay_config", "REP", 42 },
    .{ "palette", "PAL", 43 },
    .{ "static_mesh", "SMH", 44 },
    .{ "animated_texture", "ATX", 45 },
    .{ "voip_recording", "VOP", 46 },
    .{ "pins", "PIN", 47 },
    .{ "instrument", "INS", 48 },
    .{ "sample", null, 49 },
    .{ "outfit_list", "OFT", 50 },
    .{ "paint_brush", "PBR", 51 },
    .{ "thing_recording", "REC", 52 },
    .{ "painting", "PTG", 53 },
    .{ "quest", "QST", 54 },
    .{ "animation_bank", "ABK", 55 },
    .{ "animation_set", "AST", 56 },
    .{ "skeleton_map", "SMP", 57 },
    .{ "skeleton_registry", "SRG", 58 },
    .{ "skeleton_anim_styles", "SAS", 59 },
    .{ "crossplay_vita", null, 60 },
    .{ "streaming_chunk", "CHK", 61 },
    .{ "shared_adventure_data", "ADS", 62 },
    .{ "adventure_play_profile", "ADP", 63 },
    .{ "animation_map", "AMP", 64 },
    .{ "cached_costume_data", "CCD", 65 },
    .{ "data_labels", "DLA", 66 },
    .{ "adventure_maps", "ADM", 67 },
});

pub const SerializationMethod = enum(u8) {
    binary = 'b',
    text = 't',
    encrypted_binary = 'e',
    texture = ' ',
    gxt_simple = 's',
    gxt_extended = 'S',
};

fn GenerateResourceType(items: anytype) type {
    comptime {
        var enum_fields: [items.len]std.builtin.Type.EnumField = undefined;

        for (items, &enum_fields) |item, *field| {
            const name = item[0];
            // const header = item[1];
            const value = item[2];

            field.* = .{
                .name = name,
                .value = value,
            };
        }

        return struct {
            pub const ResourceType = @Type(std.builtin.Type{
                .Enum = .{
                    .tag_type = u8,
                    .decls = &.{},
                    .is_exhaustive = false,
                    .fields = &enum_fields,
                },
            });

            pub fn headerToResourceType(header: [3]u8) ?@This().ResourceType {
                inline for (items) |item| {
                    if (@TypeOf(item[1]) == @TypeOf(null)) continue;

                    const header_u24: u24 = @bitCast(header);
                    const item_header_u24: u24 = @bitCast(@as([3]u8, item[1].*));

                    if (item_header_u24 == header_u24) {
                        return @enumFromInt(item[2]);
                    }
                }

                return null;
            }

            pub fn resourceTypeToHeader(resource_type: @This().ResourceType) ?[3]u8 {
                inline for (items) |item| {
                    if (@intFromEnum(resource_type) == item[2]) {
                        if (@TypeOf(item[1]) == @TypeOf(null))
                            return null;

                        return item[1].*;
                    }
                }

                return null;
            }
        };
    }
}

pub const MachineType = enum(u8) {
    void = 0x0,
    /// A boolean, one byte in size.
    bool = 0x1,
    /// A character, two bytes in size, presumably as a single big endian UTF-16 codepoint
    char = 0x2,
    /// A signed 32-bit integer
    s32 = 0x3,
    /// A 32-bit floating point number
    f32 = 0x4,
    /// A four element f32 vector, sixteen bytes in size, in the order of XYZW
    v4 = 0x5,
    /// A 4x4 matrix of f32 elements, total of 64 bytes.
    /// This is in-memory equivalent to four v4 next to eachother.
    m44 = 0x6,
    deprecated = 0x7,
    raw_ptr = 0x8,
    ref_ptr = 0x9,
    safe_ptr = 0xa,
    object_ref = 0xb,
    /// A signed 64-bit integer
    s64 = 0xc,
    /// A 64-bit floating point number
    f64 = 0xd,
};

pub const FishType = enum(u8) {
    void = 0x0,
    bool = 0x1,
    char = 0x2,
    s32 = 0x3,
    f32 = 0x4,
    v2 = 0x5,
    v3 = 0x6,
    v4 = 0x7,
    m44 = 0x8,
    guid = 0x9,
    s64 = 0xa,
    f64 = 0xb,
};

pub const ResourceIdentifier = union(enum(u8)) {
    guid: u32 = 2,
    hash: [std.crypto.hash.Sha1.digest_length]u8 = 1,
};

pub const ResourceDescriptor = struct {
    type: MMTypes.ResourceType,
    ident: ResourceIdentifier,
    flags: u32,
};

pub const CompressionFlags = packed struct(u8) {
    compressed_integers: bool,
    compressed_vectors: bool,
    compressed_matrices: bool,
    _padding: u5 = undefined,
};
