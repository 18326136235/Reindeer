/*
###############################################################################
# Copyright (c) 2018, PulseRain Technology LLC 
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
###############################################################################
*/


`include "RV2T_common.vh"

`default_nettype none

module RV2T_execution_unit (

     //=====================================================================
     // clock and reset
     //=====================================================================
        input wire                                              clk,                          
        input wire                                              reset_n,                      
        input wire                                              sync_reset,

     //=====================================================================
     // interface from the controller   
     //=====================================================================
        input wire                                              exe_enable,
         
     //=====================================================================
     // interface for the instruction decode
     //=====================================================================
        input wire                                              enable_in,
        input wire [`XLEN - 1 : 0]                              IR_in,
        input wire [`PC_BITWIDTH - 1 : 0]                       PC_in,
        input wire [`CSR_BITS - 1 : 0]                          csr_addr_in,
        
         
        
        input wire                                              ctl_load_Y_from_imm_12,
        input wire                                              ctl_save_to_rd,

        input wire                                              ctl_LUI,
        input wire                                              ctl_AUIPC,
        input wire                                              ctl_JAL,
        input wire                                              ctl_JALR,
        input wire                                              ctl_BRANCH,
        input wire                                              ctl_LOAD,
        input wire                                              ctl_STORE,
        input wire                                              ctl_SYSTEM,
        input wire                                              ctl_CSR,
        input wire                                              ctl_CSR_write,
        input wire                                              ctl_MISC_MEM,
        input wire                                              ctl_MRET,
        
        input wire                                              ctl_MUL_DIV_FUNCT3,
        
     //=====================================================================
     // interface for the register file
     //=====================================================================
        input wire signed [`XLEN - 1 : 0]                       rs1_in,
        input wire signed [`XLEN - 1 : 0]                       rs2_in,
     
     //=====================================================================
     // interface for the CSR
     //=====================================================================
        input wire [`XLEN - 1 : 0]                              csr_in,
         
      
     //=====================================================================
     // output
     //=====================================================================
        output reg                                              enable_out,
        output reg [`REG_ADDR_BITS - 1 : 0]                     rd_addr_out,

        output reg [`XLEN - 1 : 0]                              IR_out,
        output reg [`PC_BITWIDTH - 1 : 0]                       PC_out,
        
        output wire                                             branch_active,
        output reg [`PC_BITWIDTH - 1 : 0]                       branch_addr,
        output reg                                              jalr_active,
        output wire [`PC_BITWIDTH - 1 : 0]                      jalr_addr,
        output reg                                              jal_active,
        output reg [`PC_BITWIDTH - 1 : 0]                       jal_addr,
        
        output reg  [`XLEN - 1 : 0]                             csr_new_value,
        output wire [`XLEN - 1 : 0]                             csr_old_value,
        output reg                                              reg_ctl_save_to_rd,
        output reg [`XLEN - 1 : 0]                              data_out,
        
        output reg                                              load_active,
        output reg                                              store_active,
        output wire [2 : 0]                                     width_load_store,
        output wire [`XLEN - 1 : 0]                             data_to_store,
        output wire [`XLEN - 1 : 0]                             mem_write_addr,
        output wire [`XLEN - 1 : 0]                             mem_read_addr,
        output wire                                             unaligned_write,
        output wire                                             unaligned_read,
        
        output reg                                              reg_ctl_CSR,
        output reg                                              reg_ctl_CSR_write,
        output reg  [`CSR_BITS - 1 : 0]                         csr_addr_out,
        output wire                                             ecall_active,
        output wire                                             ebreak_active,
        output reg                                              mret_active,
        output wire                                             mul_div_active,
        output reg                                              mul_div_done
); 

    //+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    // Signal
    //+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        reg  signed [`XLEN - 1 : 0]                             X;
        reg  signed [`XLEN - 1 : 0]                             Y;
                
        wire  [`XLEN - 1 : 0]                                   X_unsigned;
        wire  [`XLEN - 1 : 0]                                   Y_unsigned;
        
        wire  [2 : 0]                                           funct3_in;
        wire  [2 : 0]                                           funct3;
        reg   [2 : 0]                                           funct3_mul_div;
        
        wire  [2 : 0]                                           width; // load/store width, only support up to 32 bits at this moment 
        wire  [4 : 0]                                           opcode;
        
        wire  signed [11 : 0]                                   I_immediate_12;
        wire  [19 : 0]                                          U_immediate_20;
        
        wire  [4 : 0]                                           shamt;
        
        wire                                                    SRL0_SRA1;
        wire                                                    ADD0_SUB1;

        reg [`XLEN - 1 : 0]                                     LUI_out;
        reg [`XLEN - 1 : 0]                                     AUIPC_out;
        reg signed [`XLEN - 1 : 0]                              ALU_out;
        
        wire  [4 : 0]                                           csr_uimm;
        wire  [`XLEN - 1: 0]                                    csr_uimm_ext;
     
        wire [`XLEN - 1 : 0]                                    decode_offset;
            
        wire  [`XLEN - 1 : 0]                                   exe_offset_JALR;
        wire  [`XLEN - 1 : 0]                                   exe_offset_BRANCH;
        
        reg                                                     reg_ctl_LUI;
        reg                                                     reg_ctl_AUIPC;
        reg                                                     reg_ctl_SYSTEM;
        reg                                                     reg_ctl_JAL;
        reg                                                     reg_ctl_JALR;
        reg                                                     reg_ctl_BRANCH;
        reg                                                     reg_ctl_MUL_DIV_FUNCT3;
        
        reg                                                     branch_active_i;
        
        reg                                                     ecall_active_i;
        reg                                                     ebreak_active_i;
        
        reg                                                     exe_enable_d1;
        
        wire                                                    mul_div_enable_out;
        
        wire [63 : 0]                                           Z;
        wire [31 : 0]                                           Q;
        wire [31 : 0]                                           R;
        
        wire                                                    overflow_flag;
        wire                                                    x_mul_div_signed0_unsigned1;
        wire                                                    y_mul_div_signed0_unsigned1;
        wire                                                    mul_div_enable;
        
        reg  [31 : 0]                                           mul_div_out_reg;
        reg                                                     mul_div_sign_reg;
        reg                                                     x_sign_reg;
        
        wire [63 : 0]                                           Z_neg;
        wire [31 : 0]                                           Q_neg;
        wire [31 : 0]                                           R_neg;
        
    //+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    // data path
    //+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        //---------------------------------------------------------------------
        //  immediate number
        //---------------------------------------------------------------------
            assign I_immediate_12  = IR_in [31 : 20];
            assign U_immediate_20  = IR_in [31 : 12];
            
            
            assign shamt = Y [4 : 0];
        //---------------------------------------------------------------------
        //  funct3
        //---------------------------------------------------------------------
            assign funct3_in = IR_in [14 : 12];
            
            assign opcode = IR_out [6 : 2];
            assign funct3 = IR_out [14 : 12];
            assign SRL0_SRA1 = IR_out [30];
            assign ADD0_SUB1 = opcode[3] ? IR_out [30] : 1'b0;  // distinguish between addi/add/sub
            
            assign width  = funct3 [2 : 0];
            
            assign csr_uimm = IR_out [19 : 15];
            assign csr_uimm_ext = {27'd0, csr_uimm};
            
        //---------------------------------------------------------------------
        //  X/Y register
        //---------------------------------------------------------------------
            assign X_unsigned = $unsigned(X);
            assign Y_unsigned = $unsigned(Y);
            
            always @(posedge clk, negedge reset_n) begin
                if (!reset_n) begin
                    X <= 0;
                    Y <= 0;
                    
                    PC_out <= 0;
                    IR_out <= 0;
                    
                    reg_ctl_LUI   <= 0;
                    reg_ctl_AUIPC <= 0;
                    reg_ctl_JAL   <= 0;
                    reg_ctl_JALR  <= 0;
                    
                    reg_ctl_BRANCH <= 0;
                    
                    reg_ctl_SYSTEM <= 0;
                    
                    mret_active <= 0;
                    
                    exe_enable_d1 <= 0;
                    
                    mul_div_done <= 0;
                    
                end else begin
                    
                    X <= rs1_in;
                    Y <= ctl_load_Y_from_imm_12 ? {{20{I_immediate_12[11]}}, I_immediate_12} : rs2_in;
                    
                    PC_out <= PC_in;
                    IR_out <= IR_in;
                    
                    exe_enable_d1 <= exe_enable;
                    
                    mul_div_done <= (`ENABLE_HW_MUL_DIV) ? mul_div_enable_out : 1'b0; 
                    
                    if (exe_enable) begin
                        
                        reg_ctl_LUI    <= ctl_LUI;
                        reg_ctl_AUIPC  <= ctl_AUIPC;
                        reg_ctl_JAL    <= ctl_JAL | ctl_MISC_MEM;
                        reg_ctl_JALR   <= ctl_JALR;
                        reg_ctl_BRANCH <= ctl_BRANCH;
                        reg_ctl_SYSTEM <= ctl_SYSTEM;
                        
                        reg_ctl_MUL_DIV_FUNCT3 <= ctl_MUL_DIV_FUNCT3;
                        
                        mret_active    <= ctl_MRET & ctl_SYSTEM;
                        
                    end else begin
                        
                        reg_ctl_LUI    <= 0;
                        reg_ctl_AUIPC  <= 0;
                        reg_ctl_JAL    <= 0;
                        reg_ctl_JALR   <= 0;
                        reg_ctl_BRANCH <= 0;
                        reg_ctl_SYSTEM <= 0;
                        reg_ctl_MUL_DIV_FUNCT3 <= 0;
                        
                        mret_active    <= 0;
                        
                    end
                end
            end
            
           //assign X = rs1_in;
           //assign Y = ctl_load_Y_from_imm_12 ? {{20{I_immediate_12[11]}}, I_immediate_12} : rs2_in;
            
        //---------------------------------------------------------------------
        //  ALU
        //---------------------------------------------------------------------
            always @(*) begin : alu_proc
                case (funct3) // synopsys full_case parallel_case     
                    `ALU_ADD_SUB : begin
                        ALU_out = (ADD0_SUB1) ? (X - Y) : (X + Y);
                    end
                    
                    `ALU_SLL : begin
                        ALU_out = X << shamt;                    
                    end
                    
                    `ALU_SLT : begin
                        ALU_out = (X < Y) ? 32'd1 : 32'd0;
                    end
                    
                    `ALU_SLTU : begin
                        ALU_out = (X_unsigned < Y_unsigned) ? 32'd1 : 32'd0;
                    end
                    
                    `ALU_XOR : begin
                        ALU_out = X ^ Y;
                    end
                    
                    `ALU_SRL_SRA : begin
                        ALU_out = (SRL0_SRA1) ? (X >>> shamt) : (X >> shamt);
                    end
                    
                    `ALU_OR : begin
                        ALU_out = X | Y;
                    end
                    
                    `ALU_AND : begin
                        ALU_out = X & Y;
                    end

                    default : begin
                        ALU_out = 0;
                    end
                endcase
            end
        
        //---------------------------------------------------------------------
        //  LUI / AUIPC
        //---------------------------------------------------------------------
                
            always @(posedge clk, negedge reset_n) begin : lui_auipc_proc
                if (!reset_n) begin
                    LUI_out   <= 0;
                    AUIPC_out <= 0;
                end else if (exe_enable) begin
                    LUI_out   <= {U_immediate_20, 12'd0};
                    AUIPC_out <= {U_immediate_20, 12'd0} + PC_in;
                end
            end
                
        //---------------------------------------------------------------------
        //  BRANCH
        //---------------------------------------------------------------------
                        
            always @(*) begin : branch_proc
                case (funct3) // synopsys full_case parallel_case     
                    `BRANCH_BEQ : begin
                        branch_active_i = (X == Y) ? 1'b1 : 1'b0;
                    end

                    `BRANCH_BNE : begin
                        branch_active_i = (X == Y) ? 1'b0 : 1'b1;             
                    end

                    `BRANCH_BLT : begin
                        branch_active_i = (X < Y) ? 1'b1 : 1'b0;
                    end

                    `BRANCH_BGE : begin
                        branch_active_i = (X >= Y) ? 1'b1 : 1'b0;
                    end

                    `BRANCH_BLTU : begin
                        branch_active_i = (X_unsigned < Y_unsigned) ? 1'b1 : 1'b0;
                    end

                    `BRANCH_BGEU : begin
                        branch_active_i = (X_unsigned >= Y_unsigned) ? 1'b1 : 1'b0;
                    end

                    default : begin
                        branch_active_i = 0;
                    end
                endcase
            end
        
            always @(posedge clk, negedge reset_n) begin : branch_addr_proc
                if (!reset_n) begin
                    branch_addr <= 0;
                end else if (exe_enable) begin
                    branch_addr <= PC_in + exe_offset_BRANCH;
                end
            end
            
            assign exe_offset_BRANCH = {{20{IR_in[31]}}, IR_in[7], IR_in[30 : 25], IR_in[11 : 8], 1'b0};
            
            assign branch_active = reg_ctl_BRANCH & branch_active_i;
        //---------------------------------------------------------------------
        //  JALR
        //---------------------------------------------------------------------
            always @(posedge clk, negedge reset_n) begin : jalr_active_proc
                if (!reset_n) begin
                    jalr_active <= 0;
                end else if (exe_enable) begin
                    jalr_active <= ctl_JALR;
                end else begin
                    jalr_active <= 0;
                end
            end
            
            assign exe_offset_JALR   = {{21{IR_out[31]}}, IR_out[30 : 20]};
            assign jalr_addr = (X + exe_offset_JALR) & {{(`XLEN - 1){1'b1}}, 1'b0};
        
        //---------------------------------------------------------------------
        //  JAL
        //---------------------------------------------------------------------
            always @(posedge clk, negedge reset_n) begin : jal_active_proc
                if (!reset_n) begin
                    jal_active <= 0;
                    jal_addr   <= 0;
                end else if (exe_enable) begin
                    jal_active <= ctl_JAL | ctl_MISC_MEM;
                    if (ctl_MISC_MEM) begin
                        jal_addr   <= PC_in + 4;
                    end else begin
                        jal_addr   <= PC_in + decode_offset;
                    end
                end else begin
                    jal_active <= 0;
                end
            end
                
            assign decode_offset = {{12{IR_in[31]}}, IR_in [19 : 12], IR_in[20], IR_in[30 : 21], 1'b0}; 
        //---------------------------------------------------------------------
        //  CSR
        //---------------------------------------------------------------------
            
            always @(*) begin
                case (funct3) // synopsys full_case parallel_case     
                    `SYSTEM_CSRRW : begin
                        csr_new_value = X;
                    end
                    
                    `SYSTEM_CSRRS : begin
                        csr_new_value = csr_in | X;
                    end

                    `SYSTEM_CSRRC : begin
                        csr_new_value = csr_in & (~X);
                    end

                    `SYSTEM_CSRRWI : begin
                       csr_new_value = csr_uimm_ext;
                    end

                    `SYSTEM_CSRRSI : begin
                        csr_new_value = csr_in | csr_uimm_ext; 
                    end
                    
                    `SYSTEM_CSRRCI : begin
                        csr_new_value = csr_in & (~csr_uimm_ext); 
                    end

                    default : begin
                        csr_new_value   = 0;
                    end
                endcase
            end
            
            assign csr_old_value = csr_in;

            always @(*) begin : ecall_ebreak_proc
                if (funct3 == `SYSTEM_ECALL_EBREAK) begin
                    ecall_active_i  = ~(|(IR_out [31 : 20]));
                    ebreak_active_i = (~(|(IR_out [31 : 21]))) & IR_out[20];
                end else begin
                    ecall_active_i  = 0;
                    ebreak_active_i = 0;
                end
            end
            
            assign ecall_active  = ecall_active_i & reg_ctl_SYSTEM;
            assign ebreak_active = ebreak_active_i & reg_ctl_SYSTEM;
                    
            always @(posedge clk, negedge reset_n) begin : reg_ctl_CSR_proc
                if (!reset_n) begin
                    reg_ctl_CSR         <= 0;
                    reg_ctl_CSR_write   <= 0;
                    csr_addr_out        <= 0;
                end else if (exe_enable) begin
                    reg_ctl_CSR   <= ctl_CSR;
                    if ((funct3_in == `SYSTEM_CSRRW) || (funct3_in == `SYSTEM_CSRRWI)) begin
                        reg_ctl_CSR_write <= ctl_CSR;
                    end else begin
                        reg_ctl_CSR_write <= ctl_CSR_write;
                    end
                    
                    csr_addr_out        <= csr_addr_in;
                end
            end 
    
        //---------------------------------------------------------------------
        //  mul / div
        //---------------------------------------------------------------------
        
        generate
        
            assign x_mul_div_signed0_unsigned1 = funct3[2] ? funct3[0] : funct3[1] & funct3[0];
            assign y_mul_div_signed0_unsigned1 = funct3[2] ? funct3[0] : funct3[1];
            assign mul_div_enable = exe_enable_d1 & reg_ctl_MUL_DIV_FUNCT3;
            assign mul_div_active = reg_ctl_MUL_DIV_FUNCT3;
            
            assign Z_neg  = (~Z) + 1;
            assign Q_neg  = (~Q) + 1;
            assign R_neg  = (~R) + 1;
            
            if (`ENABLE_HW_MUL_DIV) begin
                mul_div_32 mul_div_32_i (
                    .clk (clk),
                    .reset_n (reset_n),
                    
                    .enable_in (mul_div_enable),
                    .x (X),
                    .y (Y),
                    
                    .mul0_div1 (funct3[2]),
                    .x_signed0_unsigned1 (x_mul_div_signed0_unsigned1),
                    .y_signed0_unsigned1 (y_mul_div_signed0_unsigned1),
                    .enable_out (mul_div_enable_out),
                    
                    .z (Z),
                    .q (Q),
                    .r (R),
                    .ov (overflow_flag) );
                
                always @(posedge clk, negedge reset_n) begin : mul_div_proc
                    if (!reset_n) begin
                        funct3_mul_div <= 0;
                        mul_div_sign_reg <= 0;
                        x_sign_reg <= 0;
                        
                    end else if (mul_div_enable) begin
                        funct3_mul_div <= funct3;
                        mul_div_sign_reg <= X[31] ^ Y[31];
                        x_sign_reg <= X[31];
                        
                    end
                end
                
                
                always @(posedge clk) begin : mul_div_reg_proc
                    case (funct3_mul_div) // synopsys full_case parallel_case     
                        `RV32M_MUL : begin
                            //mul_div_out_reg <=  ?  Z_neg [31 : 0]: Z [31 : 0];
                            mul_div_out_reg <=  Z [31 : 0];
                        end
                        
                    /*    `RV32M_MULH : begin
                            //mul_div_out_reg <= mul_div_sign_reg ? Z_neg [63 : 32] : Z [63 : 32];                    
                            mul_div_out_reg <= Z [63 : 32];
                        end
                        
                        `RV32M_MULHSU : begin
                            //mul_div_out_reg <= x_sign_reg ? Z_neg [63 : 32] : Z [63 : 32];
                            mul_div_out_reg <= Z [63 : 32];
                        end
                        
                        `RV32M_MULHU : begin
                            mul_div_out_reg <= Z [63 : 32];
                        end
                      */

                        `RV32M_MULH, `RV32M_MULHSU, `RV32M_MULHU : begin
                            mul_div_out_reg <= Z [63 : 32];
                        end
                      
                  //      `RV32M_DIV : begin
                  //          if (overflow_flag) begin
                  //              mul_div_out_reg <= 32'hFFFFFFFF;
                  //          end else begin
                  //              mul_div_out_reg <= mul_div_sign_reg ? Q_neg : Q;
                  //          end
                  //      end
                        
                        `RV32M_DIVU : begin
                            mul_div_out_reg <= Q;
                        end
                        
                        /*
                        `RV32M_REM : begin
                           // mul_div_out_reg <= x_sign_reg ? R_neg : R;
                           mul_div_out_reg <= R;
                        end
                        
                        `RV32M_REMU : begin
                            mul_div_out_reg <= R;
                        end
                        */
                        
                        `RV32M_REM, `RV32M_REMU : begin
                            mul_div_out_reg <= R;
                        end
                        
                        default : begin
                            if (overflow_flag) begin
                                mul_div_out_reg <= 32'hFFFFFFFF;
                            end else begin
                               // mul_div_out_reg <= mul_div_sign_reg ? Q_neg : Q;
                                mul_div_out_reg <= Q;
                            end
                        end
                    endcase
                end
            end    
        endgenerate
        
        //---------------------------------------------------------------------
        //  data_out
        //---------------------------------------------------------------------
            always @(*) begin : data_out_proc
                case (1'b1) // synopsys parallel_case  
                    reg_ctl_LUI : begin
                        data_out = LUI_out;
                    end
                    
                    reg_ctl_AUIPC : begin
                        data_out = AUIPC_out;
                    end
                    
                    reg_ctl_JAL | reg_ctl_JALR : begin
                        data_out = PC_out + 4;
                    end
                    
                    mul_div_done : begin
                        data_out = mul_div_out_reg;
                    end
                    
                    default : begin
                        data_out = ALU_out;
                    end
                endcase
            end

        //---------------------------------------------------------------------
        //  enable_out
        //---------------------------------------------------------------------
            always @(posedge clk, negedge reset_n) begin : output_proc
                if (!reset_n) begin
                    rd_addr_out <= 0;
                    reg_ctl_save_to_rd <= 0;
                    
                    load_active  <= 0;
                    store_active <= 0;
                end else if (exe_enable) begin
                    rd_addr_out <= IR_in [11 : 7];
                    reg_ctl_save_to_rd <= ctl_save_to_rd;
                    
                    load_active  <= ctl_LOAD;
                    store_active <= ctl_STORE;
                end
            end
            
            assign data_to_store = Y;
            
            assign mem_write_addr =  X + {{20{IR_out [31]}}, IR_out [31 : 25], IR_out [11 : 7]};
            assign mem_read_addr  =  X + {{20{IR_out[31]}}, IR_out[31 : 20]};
            
            assign unaligned_read  = (width == `WIDTH_32) ? (mem_read_addr[0] | mem_read_addr[1]) : ( (width == `WIDTH_16) || (width == `WIDTH_16U) ?  mem_read_addr[0] : 0 );
            
            assign unaligned_write = (width == `WIDTH_32) ? (mem_write_addr[0] | mem_write_addr[1]) : ( (width == `WIDTH_16) || (width == `WIDTH_16U) ?  mem_write_addr[0] : 0 );
            assign width_load_store = width;
        
endmodule

`default_nettype wire
