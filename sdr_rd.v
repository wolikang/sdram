
module sdr_rd(/*autoarg*/);

input clk;//clock, 167MHz
input rst_n;//reset

output sdr_CKE;
output sdr_nCS;
output[1:0] sdr_BA;
output[12:0] sdr_A;
output sdr_nRAS;
output sdr_nCAS;
output sdr_nWE;
inout[15:0] sdr_DQ;
output [1:0] sdr_DQM;

input sdr_rd_req;
input [1:0] sdr_bank_addr;
input [12:0] sdr_row_addr;
input [8:0] sdr_col_addr;
output rd_done;

localparam S_IDLE = 4'h0;
localparam S_ACTIVE = 4'h1;
localparam S_READ = 4'h2;

localparam CMD_NOP = 3'b111;
localparam CMD_ACTIVE = 3'b011;
localparam CMD_READ = 3'b101;
localparam CMD_PRECHARGE = 3'b010;

localparam tRCD = 3;
/*autodefine*/

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        base_cnt[15:0] <= #`RD 16'h0;
    else if(active_done | rd_done)
        base_cnt <= #`RD 16'h0;
    else if(base_cnt_en)
        base_cnt <= #`RD base_cnt + 16'h1;

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        base_cnt_en <= #`RD 1'b0;
    else if(sdr_rd_req)
        base_cnt_en <= #`RD 1'b1;
    else if(rd_done)
        base_cnt_en <= #`RD 1'b0;

assign active_done = (base_cnt == tRCD) & (sdr_rd_state == S_ACTIVE);
assign rd_done = (base_cnt == 4) & (sdr_rd_state == S_READ);

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        sdr_rd_state[3:0] <= #`RD S_IDLE;
    else
        sdr_rd_state[3:0] <= #`RD sdr_rd_state_nxt;

always @(*) begin
    sdr_rd_state_nxt[3:0] = sdr_rd_state;
    case(sdr_rd_state)
        S_IDLE: if(sdr_rd_req) sdr_rd_state_nxt = S_ACTIVE;
        S_ACTIVE: if(active_done) sdr_rd_state_nxt = S_READ;
        S_READ: if(rd_done) sdr_rd_state_nxt = S_IDLE;
        default: sdr_rd_state_nxt = S_IDLE;
    endcase
end

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        {sdr_nRAS, sdr_nCAS, sdr_nWE} <= #`RD CMD_NOP;
    else 
        case({sdr_wr_state, sdr_wr_state_nxt})
            {S_IDLE, S_IDLE}: {sdr_nRAS, sdr_nCAS, sdr_nWE} <= #`RD CMD_NOP;
            {S_IDLE, S_ACTIVE}: {sdr_nRAS, sdr_nCAS, sdr_nWE} <= #`RD CMD_ACTIVE;
            {S_ACTIVE, S_READ}: {sdr_nRAS, sdr_nCAS, sdr_nWE} <= #`RD CMD_READ;
            default: {sdr_nRAS, sdr_nCAS, sdr_nWE} <= #`RD CMD_NOP;
        endcase

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        sdr_BA[1:0] <= #`RD 2'h0;
    else if(sdr_wr_req)
        sdr_BA[1:0] <= #`RD sdr_bank_addr;

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        sdr_A[12:0] <= #`RD 13'h0;
    else if(sdr_rd_req)
        sdr_A[12:0] <= #`RD sdr_row_addr;
    else if({sdr_rd_state, sdr_rd_state_nxt} == {S_ACTIVE, S_READ})
        sdr_A[12:0] <= #`RD {2'h0, 1'b0, 1'b0, sdr_col_addr};

assign sdr_DQM[1:0] = 2'h0;
assign sdr_CKE = 1'b1;
assign sdr_nCS = 1'b0;



endmodule