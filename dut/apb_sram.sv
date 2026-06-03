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
    // Local parameters
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
    // Reset
    // =============================================
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            current_state <= IDLE;
            wait_cnt      <= '0;
            wait_cycles   <= '0;
            foreach (mem[i]) mem[i] <= '0;
        end else begin
            current_state <= next_state;
        end
    end

    // =============================================
    // Next State Logic - HỖ TRỢ BACK-TO-BACK
    // =============================================
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (psel && !penable)
                    next_state = SETUP;
            end

            SETUP: begin
                next_state = ACCESS;
            end

            ACCESS: begin
                if (pready) begin
                    // Hỗ trợ Back-to-Back: Nếu Master đã đưa SETUP mới ngay
                    if (psel && !penable)
                        next_state = SETUP;
                    else
                        next_state = IDLE;
                end
                // else: vẫn đang wait → giữ ACCESS
            end

            default: next_state = IDLE;
        endcase
    end

    // =============================================
    // Wait Cycles Generation
    // =============================================
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            wait_cycles <= '0;
        end else if (current_state == SETUP) begin
            wait_cycles <= $urandom_range(0, MAX_WAIT);
        end
    end

    // =============================================
    // Wait Counter
    // =============================================
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            wait_cnt <= '0;
        end 
        else if (current_state == ACCESS) begin
            if (wait_cnt < wait_cycles) begin
                wait_cnt <= wait_cnt + 1'b1;
            end
        end 
        else begin
            wait_cnt <= '0;        // Clear khi ở IDLE hoặc SETUP
        end
    end

    // =============================================
    // Address Validation
    // =============================================
    assign addr_valid = (paddr < MEM_SIZE);

    // =============================================
    // Output Logic - Combinational
    // =============================================
    always_comb begin
        pready  = 1'b0;
        pslverr = 1'b0;
        prdata  = '0;

        if (current_state == ACCESS) begin
            if (wait_cnt >= wait_cycles) begin
                pready = 1'b1;
                
                if (!addr_valid) begin
                    pslverr = 1'b1;
                    prdata  = 32'hDEADBEEF;
                end else if (!pwrite) begin
                    prdata = mem[paddr[MEM_DEPTH-1:0]];
                end
            end
        end
    end

    // =============================================
    // Write Logic
    // =============================================
    always_ff @(posedge pclk) begin
        if (current_state == ACCESS && pwrite && addr_valid && (wait_cnt >= wait_cycles)) begin
            mem[paddr[MEM_DEPTH-1:0]] <= pwdata;
        end
    end

    // =============================================
    // Debug
    // =============================================
    // synthesis translate_off
    always_ff @(posedge pclk) begin
        if (current_state != IDLE) begin
            $display("[APB_SRAM] t=%0t | State=%s | Addr=0x%8h | W=%b | Ready=%b | Err=%b | Wait=%0d/%0d",
                     $time, current_state.name(), paddr, pwrite, pready, pslverr, wait_cnt, wait_cycles);
        end
    end
    // synthesis translate_on

endmodule