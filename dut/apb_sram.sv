//==============================================================================
// File          : apb_sram.sv
// Description   : APB Slave Memory hỗ trợ True Back-to-Back (B2B) chuẩn AMBA
//                 bằng đường chuyển trạng thái trực tiếp ACCESS -> SETUP.
//                 (Giữ nguyên addr_valid = 0 cho vùng địa chỉ lỗi 0x400 - 0x4FF)
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
    // Next State Logic (Combinational) - FIX THEO CÁCH A
    // =============================================
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                // Bắt đầu chu kỳ đầu tiên: Chuyển sang SETUP khi có psel
                if (psel && !penable) begin
                    next_state = SETUP;
                end
            end
            
            SETUP: begin
                // APB Spec: Sau SETUP luôn là ACCESS
                next_state = ACCESS;
            end
            
            ACCESS: begin
                // Chỉ xét chuyển trạng thái khi chu kỳ hiện tại đã HOÀN THÀNH (pready = 1)
                if (pready) begin
                    if (psel && !penable) begin
                        // 🔥 ĐƯỜNG TẮT CÁCH A: Master gối đầu gói mới ngay lập tức!
                        // Chuyển thẳng từ ACCESS về SETUP mà không thèm qua IDLE.
                        next_state = SETUP;
                    end else begin
                        // Không có gói gối đầu -> Bus nghỉ, về IDLE
                        next_state = IDLE;
                    end
                end else begin
                    // Nếu DUT chưa sẵn sàng (pready = 0), bắt buộc phải giữ ACCESS
                    next_state = ACCESS;
                end
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
            // Nạp giá trị chu kỳ đợi ngay tại pha SETUP (áp dụng cho cả khi đi tắt từ ACCESS sang)
            if (next_state == SETUP) begin
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
                pready = 1'b1; // Kéo Ready lên báo kết thúc giao dịch
                
                if (!addr_valid) begin
                    // 🔥 Nếu là địa chỉ test lỗi (> 0x3FF): Bật PSLVERR vọt lên 1
                    pslverr = 1'b1;
                    prdata  = 32'hDEADBEEF;
                end else if (!pwrite) begin
                    // Địa chỉ đúng + Lệnh Đọc: Xuất data từ RAM thật
                    prdata = mem[paddr[MEM_DEPTH-1:0]];
                end
            end
        end
    end

    // =============================================
    // Write Logic (Sequential)
    // =============================================
    always_ff @(posedge pclk) begin
        // Chỉ ghi vào mảng RAM nếu địa chỉ thực sự hợp lệ (addr_valid = 1)
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