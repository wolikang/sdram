
module sdr_wr(/*autoarg*/
    //Inouts
    sdr_DQ,

    //Outputs
    sdr_CKE, sdr_nCS, sdr_BA, sdr_A, sdr_nRAS, sdr_nCAS, sdr_nWE,
    sdr_DQM, wr_exit, sdr_wdata_rd, sdr_wr_pausing,

    //Inputs
    clk, rst_n, sdr_wr_req, sdr_wr_byte_cnt, sdr_bank_addr,
    sdr_row_addr, sdr_col_addr, sdr_wdata_filled_depth, sdr_wdata,
    need_ref
);

`include "sdr_parameters.vh"

input                 clk                       ;  //clock, 167MHz
input                 rst_n                     ;

output                sdr_CKE                   ;
output                sdr_nCS                   ;
output      [1:0]     sdr_BA                    ;
output      [12:0]    sdr_A                     ;
output                sdr_nRAS                  ;
output                sdr_nCAS                  ;
output                sdr_nWE                   ;
inout       [15:0]    sdr_DQ                    ;
output      [1:0]     sdr_DQM                   ;

input                 sdr_wr_req                ;  //write operation request
input       [11:0]    sdr_wr_byte_cnt           ;  //write total byte cnt
//input                 sdr_wr_term      ;    //write operation termination signal
input       [1:0]     sdr_bank_addr             ;
input       [12:0]    sdr_row_addr              ;
input       [8:0]     sdr_col_addr              ;

output                wr_exit                   ;
input       [4:0]     sdr_wdata_filled_depth    ;
output                sdr_wdata_rd              ;
input       [15:0]    sdr_wdata                 ;

input                 need_ref;//request for auto-refresh
output                sdr_wr_pausing;

localparam S_IDLE = 4'h0;
localparam S_ACTIVE = 4'h1;
localparam S_WRITE = 4'h2;
localparam S_PRECHARGE = 4'h3;
localparam S_PAUSE = 4'h4;

localparam CMD_NOP = 3'b111;
localparam CMD_ACTIVE = 3'b011;
localparam CMD_WRITE = 3'b100;
localparam CMD_PRECHARGE = 3'b010;

localparam NRCD = (tRCD/tCK);
localparam NRP = (tRP/tCK);

`define SEND_CMD {sdr_nRAS, sdr_nCAS, sdr_nWE} 

/*autodefine*/
//auto wires{{{
wire        active_done ;
wire        active_state ;
wire [1:0]  cur_bank_addr ;
wire [24:0] cur_col_addr ;
wire [13:0] cur_row_addr ;
wire        exec_active_cmd ;
wire        exec_precharge_cmd ;
wire        exec_write_cmd ;
wire        precharge_done ;
wire        precharge_state ;
wire        sdr_CKE ;
wire [15:0] sdr_DQ ;
wire [1:0]  sdr_DQM ;
wire        sdr_nCS ;
wire        wdata_rdy ;
wire        wr_last;
wire        wr_exit ;
wire        wr_data_over;
wire [23:0] wr_left_cnt ;
wire        wr_one_row_end ;
wire        write_state ;
wire        wr_burst_last;
//}}}
//auto regs{{{
reg        active_state_dly ;
reg [15:0] base_cnt ;
reg        base_cnt_en ;
reg        precharge_state_dly ;
reg [12:0] sdr_A ;
reg [1:0]  sdr_BA ;
reg        sdr_wdata_rd ;
reg        wdata_wr_en ;
reg [3:0]  sdr_wr_state ;
reg [3:0]  sdr_wr_state_nxt ;
reg [23:0] wr_total_cnt ;
reg        sdr_nCAS ;
reg        sdr_nRAS ;
reg        sdr_nWE ;
reg [1:0] sdr_bank_addr_r;
reg [12:0] sdr_row_addr_r;
reg [8:0] sdr_col_addr_r;
reg     wr_done;
//}}}
// End of automatic define

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        base_cnt[15:0] <= #`RD 16'h0;
    else if(active_done | wr_done | wr_one_row_end| precharge_done | (~sdr_wdata_rd & need_ref & write_state) | sdr_wr_pausing)
        base_cnt <= #`RD 16'h0;
    else if(base_cnt_en)
        base_cnt <= #`RD base_cnt + 16'h1;

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        base_cnt_en <= #`RD 1'b0;
    else if(sdr_wr_req)
        base_cnt_en <= #`RD 1'b1;
    else if(wr_exit)
        base_cnt_en <= #`RD 1'b0;

assign active_done = (base_cnt >= NRCD) & (sdr_wr_state == S_ACTIVE);
assign precharge_done = (base_cnt >= NRP) & (sdr_wr_state == S_PRECHARGE);
assign wr_exit = (sdr_wr_state == S_PRECHARGE) & (sdr_wr_state_nxt == S_IDLE);
assign wr_last = (wr_total_cnt == (sdr_wr_byte_cnt - 1));

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        wr_done <= #`RD 1'b0;
    else if(wr_last)
        wr_done <= #`RD 1'b1;
    else
        wr_done <= #`RD 1'b0;

// if write over one row, need active new row before write data to new row
// produce a active command request
always @(posedge clk or negedge rst_n)
    if(!rst_n)
        wr_total_cnt[23:0] <= #`RD 24'h0;
    else if(sdr_wr_req)
        wr_total_cnt[23:0] <= #`RD 24'h0;
    else if(sdr_wdata_rd)
        wr_total_cnt[23:0] <= #`RD wr_total_cnt + 24'h1;

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        sdr_bank_addr_r[1:0] <= #`RD 2'h0;
    else if(sdr_wr_req)
        sdr_bank_addr_r[1:0] <= #`RD sdr_bank_addr;

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        sdr_row_addr_r[12:0] <= #`RD 13'h0;
    else if(sdr_wr_req)
        sdr_row_addr_r[12:0] <= #`RD sdr_row_addr;

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        sdr_col_addr_r[8:0] <= #`RD 9'h0;
    else if(sdr_wr_req)
        sdr_col_addr_r[8:0] <= #`RD sdr_col_addr;


assign cur_col_addr[24:0] = (wr_total_cnt[23:0] + {sdr_bank_addr_r[1:0], sdr_row_addr_r[12:0], sdr_col_addr_r[8:0]});
assign cur_row_addr[13:0] = cur_col_addr[21:9];
assign cur_bank_addr[1:0] = cur_col_addr[23:22];
assign wr_one_row_end = wdata_wr_en & (wr_total_cnt < sdr_wr_byte_cnt) ? (cur_col_addr[8:0] == 9'h0) : 1'b0;
//assign wr_one_bank_end = (wr_total_cnt < sdr_wr_byte_cnt) ? (cur_col_addr[21:0] == 22'h0) : 1'b0;

assign wr_left_cnt[23:0] = (sdr_wr_byte_cnt - wr_total_cnt);
assign wr_data_over = (wr_left_cnt == 24'h0);
assign wdata_rdy = wr_data_over ? 1'b0 : 
                    (|wr_left_cnt[23:2]) ? (sdr_wdata_filled_depth >= 5'h4) : (wr_left_cnt[23:0] <= {19'h0, sdr_wdata_filled_depth});
assign wr_burst_last = (wr_total_cnt[1:0] == 2'b11);

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        sdr_wdata_rd <= #`RD 1'b0;
    else if(wr_last & sdr_wdata_rd)
        sdr_wdata_rd <= #`RD 1'b0;
    else if(~need_ref & (write_state & wdata_rdy) & (~wdata_wr_en | wr_burst_last))
        sdr_wdata_rd <= #`RD 1'b1;
    else if(wr_burst_last)
        sdr_wdata_rd <= #`RD 1'b0;

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        wdata_wr_en <= #`RD 1'b0;
    else
        wdata_wr_en <= #`RD sdr_wdata_rd;


always @(posedge clk or negedge rst_n)
    if(!rst_n)
        sdr_wr_state[3:0] <= #`RD S_IDLE;
    else
        sdr_wr_state[3:0] <= #`RD sdr_wr_state_nxt;

always @(*) begin
    sdr_wr_state_nxt[3:0] = sdr_wr_state;
    case(sdr_wr_state)
        S_IDLE: if(~need_ref & sdr_wr_req) sdr_wr_state_nxt = S_ACTIVE;
        S_ACTIVE: if(need_ref & active_done) sdr_wr_state_nxt = S_PRECHARGE;
                else if(active_done) sdr_wr_state_nxt = S_WRITE;
        S_WRITE: if((~sdr_wdata_rd & need_ref) | wr_done | wr_one_row_end) sdr_wr_state_nxt = S_PRECHARGE;
        S_PRECHARGE: if(need_ref & precharge_done) sdr_wr_state_nxt = S_PAUSE;
                    else if(~need_ref & precharge_done & (~wr_data_over)) sdr_wr_state_nxt = S_ACTIVE;
                    else if(precharge_done) sdr_wr_state_nxt = S_IDLE;
        S_PAUSE: if(~need_ref) sdr_wr_state_nxt = S_ACTIVE;
        default: sdr_wr_state_nxt = S_IDLE;
    endcase
end

assign sdr_wr_pausing = (sdr_wr_state == S_PAUSE);

assign active_state = (sdr_wr_state == S_ACTIVE);
assign exec_active_cmd = (~active_state_dly) & active_state;
always @(posedge clk or negedge rst_n)
    if(!rst_n)
        active_state_dly <= #`RD 1'b0;
    else
        active_state_dly <= #`RD active_state;

assign precharge_state = (sdr_wr_state == S_PRECHARGE);
assign exec_precharge_cmd = (~precharge_state_dly) & precharge_state;
always @(posedge clk or negedge rst_n)
    if(!rst_n)
        precharge_state_dly <= #`RD 1'b0;
    else
        precharge_state_dly <= #`RD precharge_state;

assign write_state = (sdr_wr_state == S_WRITE);
assign exec_write_cmd = sdr_wdata_rd & (wr_total_cnt[1:0] == 2'h0);
        

always @(posedge clk or negedge rst_n)
    if(!rst_n) begin
        `SEND_CMD <= #`RD CMD_NOP;
    end
    else if(exec_active_cmd)
        `SEND_CMD <= #`RD CMD_ACTIVE;
    else if(exec_precharge_cmd)
        `SEND_CMD <= #`RD CMD_PRECHARGE;
    else if(exec_write_cmd)
        `SEND_CMD <= #`RD CMD_WRITE;
    else
        `SEND_CMD <= #`RD CMD_NOP;

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        sdr_BA[1:0] <= #`RD 2'h0;
    else
        sdr_BA[1:0] <= #`RD cur_bank_addr;

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        sdr_A[12:0] <= #`RD 13'h0;
    else if(exec_write_cmd)
        sdr_A[12:0] <= #`RD {2'h0, 1'b0, 1'b0, cur_col_addr[8:0]};
    else if(exec_active_cmd)
        sdr_A[12:0] <= #`RD cur_row_addr;

assign sdr_DQ[15:0] = sdr_wdata;
assign sdr_DQM[1:0] = 2'h0;
assign sdr_CKE = 1'b1;
assign sdr_nCS = 1'b0;


endmodule
