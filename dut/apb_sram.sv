//==============================================================================
// File          : apb_sram.sv
// Description   : APB Slave Memory với logic sửa lỗi treo FSM khi gặp SLVERR
//                 (Giữ nguyên addr_valid = 0 cho vùng địa chỉ lỗi)
//==============================================================================

`timescale 1ns/1ps

module apb_sram #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int MEM_DEPTH  = 10,
    parameter int MAX_WAIT   = 8
) (
    input  logic                     pclk,
    input  logic                     presetn,
    
    input  logic                     psel,
    input  logic                     penable,
    input  logic                     pwrite,
    input  logic [ADDR_WIDTH-1:0]    paddr,
    input  logic [DATA_WIDTH-1:0]    pwdata,
    
    output logic [DATA_WIDTH-1:0]    prdata,
    output logic                     pready,
    output logic                     pslverr
);

    // =============================================
    // Local parameters & Internal Signals
    // =============================================
    localparam int MEM_SIZE = 1 << MEM_DEPTH;
    
    logic [DATA_WIDTH-1:0] mem [0:MEM_SIZE-1];
    
    typedef enum logic [1:0] {
        IDLE   = 2'b00,
        SETUP  = 2'b01,
        ACCESS = 2'b11
    } apb_state_t;

    apb_state_t current_state, next_state;
    
    logic [7:0] wait_cycles;
    logic [7:0] wait_cnt;
    logic       addr_valid;

    // =============================================
    // Address Decoding - Combinational
    // Vùng nhớ thật từ 0x000 đến 0x3FF (addr_valid = 1).
    // Vùng địa chỉ lỗi từ 0x400 đến 0x4FF (addr_valid = 0).
    // =============================================
    always_comb begin
        addr_valid = (paddr < MEM_SIZE); 
    end

    // =============================================
    // State Register (Sequential)
    // =============================================
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    // =============================================
    // Next State Logic (Combinational)
    // =============================================
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                // 🔥 Đfont SỬA: Chỉ cần psel lên là nhảy sang SETUP luôn,
                // không quan tâm địa chỉ có hợp lệ hay không.
                if (psel && !penable) begin
                    next_state = SETUP;
                end
            end
            
            SETUP: begin
                next_state = ACCESS;
            end
            
            ACCESS: begin
                if (pready)
                    next_state = IDLE;
                else
                    next_state = ACCESS;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // =============================================
    // Wait States Generation (Sequential)
    // =============================================
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            wait_cycles <= '0;
            wait_cnt    <= '0;
        end else begin
            if (current_state == SETUP) begin
                if (MAX_WAIT > 0)
                    wait_cycles <= paddr[7:0] % (MAX_WAIT + 1);
                else
                    wait_cycles <= '0;
                wait_cnt <= '0;
            end else if (current_state == ACCESS) begin
                if (wait_cnt < wait_cycles)
                    wait_cnt <= wait_cnt + 1'b1;
            end
        end
    end

    // =============================================
    // Output Logic - Combinational
    // =============================================
    always_comb begin
        pready  = 1'b0;
        pslverr = 1'b0;
        prdata  = '0;

        if (current_state == ACCESS) begin
            if (wait_cnt >= wait_cycles) begin
                pready = 1'b1; // Luôn kết thúc chu kỳ khi hết wait state
                
                if (!addr_valid) begin
                    // 🔥 Địa chỉ lỗi (> 0x3FF): Vẫn phản hồi Ready nhưng báo thêm SLVERR
                    pslverr = 1'b1;
                    prdata  = 32'hDEADBEEF;
                end else if (!pwrite) begin
                    // Địa chỉ đúng + lệnh Đọc: Trả data từ RAM thật
                    prdata = mem[paddr[MEM_DEPTH-1:0]];
                end
            end
        end
    end

    // =============================================
    // Write Logic (Sequential)
    // =============================================
    always_ff @(posedge pclk) begin
        // Chặn không cho ghi đè dữ liệu vào RAM thật khi addr_valid = 0
        if (current_state == ACCESS && pwrite && addr_valid && (wait_cnt >= wait_cycles)) begin
            mem[paddr[MEM_DEPTH-1:0]] <= pwdata;
        end
    end

    // =============================================
    // Debug Monitor System
    // =============================================
    // synthesis translate_off
    always_ff @(posedge pclk) begin
        if (current_state != IDLE) begin
            $display("[APB_SRAM] t=%0t | State=%s | Addr=0x%8h | Valid=%b | W=%b | Ready=%b | Err=%b", 
                     $time, current_state.name(), paddr, addr_valid, pwrite, pready, pslverr);
        end
    end
    // synthesis translate_on

endmodule