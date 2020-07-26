// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

////////////////////////////////////////////////////////////////////////////////
// Engineer:     Alenkruth                                                    //
// Project:      RISC-V crypto Extension                                      //
// Design name:  RISC V Vector/Crypto register file                           //
// Language:     System Verilog                                               //
// Description:  Regidter file with 32x vector registers. The width is given  //
//               by the user. This file is developed by using the register    //
//               file of RI5CY as the base.                                   //
//               The zeroth register is not fixed to zero value and is RWable //
////////////////////////////////////////////////////////////////////////////////

module riscv_vector_register_file_latch
#(
  parameter VADDR_WIDTH = 6,
  parameter VDATA_WIDTH = 256 //default assuming AES
)
(
  // Clock and Reset
  input  logic                   clk,
  input  logic                   rst_n,

  input  logic                   test_en_i,

  //Read port R1
  input  logic [VADDR_WIDTH-1:0]  vraddr_a_i,
  output logic [VDATA_WIDTH-1:0]  vrdata_a_o,

  //Read port R2
  input  logic [VADDR_WIDTH-1:0]  vraddr_b_i,
  output logic [VDATA_WIDTH-1:0]  vrdata_b_o,

  //Read port R3
  input  logic [VADDR_WIDTH-1:0]  vraddr_c_i,
  output logic [VDATA_WIDTH-1:0]  vrdata_c_o,

  // Write port W1
  input  logic [VADDR_WIDTH-1:0]   vwaddr_a_i,
  input  logic [VDATA_WIDTH-1:0]   vwdata_a_i,
  input  logic                    vwe_a_i,

  // Write port W2
  input  logic [VADDR_WIDTH-1:0]   vwaddr_b_i,
  input  logic [VDATA_WIDTH-1:0]   vwdata_b_i,
  input  logic                    vwe_b_i
); 


   // number of integer registers
   localparam    VNUM_WORDS     = 2**(VADDR_WIDTH-1);
   localparam    VNUM_TOT_WORDS = VNUM_WORDS;
   
   // vector register file
   logic [VDATA_WIDTH-1:0]         mem[VNUM_WORDS];
   logic [VNUM_TOT_WORDS-1:0]      vwaddr_onehot_a;
   logic [VNUM_TOT_WORDS-1:0]      vwaddr_onehot_b, vwaddr_onehot_b_q;
   logic [VNUM_TOT_WORDS-1:0]      mem_clocks;
   logic [VDATA_WIDTH-1:0]         vwdata_a_q;
   logic [VDATA_WIDTH-1:0]         vwdata_b_q;

   // masked write addresses
   logic [VADDR_WIDTH-1:0]         vwaddr_a;
   logic [VADDR_WIDTH-1:0]         vwaddr_b;

   logic                          clk_int; 
   
   int                            unsigned i;
   int                            unsigned j;
   int                            unsigned k;

   genvar                         x;
   genvar                         y;
   
   //-----------------------------------------------------------------------------
   //-- READ : Read address decoder RAD
   //-----------------------------------------------------------------------------
    assign vrdata_a_o = mem[vraddr_a_i[4:0]];
    assign vrdata_b_o = mem[vraddr_b_i[4:0]];
    assign vrdata_c_o = mem[vraddr_c_i[4:0]];
    
   //-----------------------------------------------------------------------------
   // WRITE : SAMPLE INPUT DATA
   //---------------------------------------------------------------------------

   cluster_clock_gating CG_WE_GLOBAL
     (
      .clk_i     ( clk               ),
      .en_i      ( vwe_a_i | vwe_b_i ),
      .test_en_i ( test_en_i         ),
      .clk_o     ( clk_int           )
      );

   // use clk_int here, since otherwise we don't want to write anything anyway
   always_ff @(posedge clk_int, negedge rst_n)
     begin : sample_waddr
        if (~rst_n) begin
           vwdata_a_q        <= '0;
           vwdata_b_q        <= '0;
           vwaddr_onehot_b_q <= '0;
        end else begin
           if(vwe_a_i)
             vwdata_a_q <= vwdata_a_i;

           if(vwe_b_i)
             vwdata_b_q <= vwdata_b_i;

           vwaddr_onehot_b_q <= vwaddr_onehot_b;
        end
     end
     
   //-----------------------------------------------------------------------------
   //-- WRITE : Write Address Decoder (WAD), combinatorial process
   //-----------------------------------------------------------------------------

   assign vwaddr_a = vwaddr_a_i;
   assign vwaddr_b = vwaddr_b_i;

    always_comb
       begin : p_WADa
          for(i = 0; i < VNUM_TOT_WORDS; i++)
            begin : p_WordItera
               if ( (vwe_a_i == 1'b1 ) && (vwaddr_a == i) )
                 vwaddr_onehot_a[i] = 1'b1;
               else
                 vwaddr_onehot_a[i] = 1'b0;
            end
       end

     always_comb
       begin : p_WADb
          for(j = 0; j < VNUM_TOT_WORDS; j++)
            begin : p_WordIterb
               if ( (vwe_b_i == 1'b1 ) && (vwaddr_b == j) )
                 vwaddr_onehot_b[j] = 1'b1;
               else
                 vwaddr_onehot_b[j] = 1'b0;
            end
       end

   //-----------------------------------------------------------------------------
   //-- WRITE : Clock gating (if integrated clock-gating cells are available)
   //-----------------------------------------------------------------------------
   generate
      for(x = 1; x < VNUM_TOT_WORDS; x++)
        begin : CG_CELL_WORD_ITER
           cluster_clock_gating CG_Inst
             (
              .clk_i     ( clk_int                                 ),
              .en_i      ( vwaddr_onehot_a[x] | vwaddr_onehot_b[x] ),
              .test_en_i ( test_en_i                               ),
              .clk_o     ( mem_clocks[x]                           )
              );
        end
   endgenerate
   
   //-----------------------------------------------------------------------------
   //-- WRITE : Write operation
   //-----------------------------------------------------------------------------
   //-- Generate M = WORDS sequential processes, each of which describes one
   //-- word of the memory. The processes are synchronized with the clocks
   //-- ClocksxC(i), i = 0, 1, ..., M-1
   //-- Use active low, i.e. transparent on low latches as storage elements
   //-- Data is sampled on rising clock edge

   // vector registers
   always_latch
     begin : latch_wdata

        for(k = 0; k < VNUM_WORDS; k++)
          begin : w_WordIter
             if(mem_clocks[k] == 1'b1)
               mem[k] = vwaddr_onehot_b_q[k] ? vwdata_b_q : vwdata_a_q;
          end
     end
     
endmodule
