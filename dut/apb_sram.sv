module apb_sram #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_DEPTH   = 1024,
    parameter MAX_WAIT   = 4
)(
    input  logic                    pclk,
    input  logic                    presetn,
    input  logic [ADDR_WIDTH-1:0]   paddr,
    input  logic                    psel,
    input  logic                    penable,
    input  logic                    pwrite,
    input  logic [DATA_WIDTH-1:0]   pwdata,
    output logic [DATA_WIDTH-1:0]   prdata,
    output logic                    pready,
    output logic                    pslverr
);

    // 1. Định nghĩa các trạng thái FSM bằng mẫu dữ liệu enum mã hóa tĩnh
    typedef enum logic [1:0] {
        IDLE   = 2'b00,
        SETUP  = 2'b01,
        ACCESS = 2'b10
    } apb_state_e;

    apb_state_e current_state, next_state;

    // Khai báo mảng bộ nhớ SRAM (Fix cứng theo Word-addressing hiện tại của bro)
    logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // Khai báo các thanh ghi điều khiển chu kỳ đợi (Wait states) ngẫu nhiên
    logic [3:0] wait_cycles;
    logic [3:0] wait_cnt;

    // 2. Định nghĩa cấu trúc FSM - Khối 1: Chuyển đổi trạng thái (Sequential Logic)
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // 2. Định nghĩa cấu trúc FSM - Khối 2: Tính toán trạng thái tiếp theo (Combinational Logic)
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (psel) next_state = SETUP;
            end
            
            SETUP: begin
                if (penable) next_state = ACCESS;
                else         next_state = IDLE; // Phòng vệ giao thức (Protocol protection)
            end
            
            ACCESS: begin
                // Chỉ khi pready dựng lên cao mới kết thúc chu kỳ ACCESS
                if (pready) begin
                    if (psel) next_state = SETUP;  // Có chu kỳ tiếp theo (Back-to-Back)
                    else      next_state = IDLE;   // Kết thúc giao dịch, quay về nghỉ
                end
            end
            
            default: next_state = IDLE;
        endcase
    end

    // 3. Khối điều khiển chu kỳ đợi (Wait-state Generator) & Đọc/Ghi dữ liệu
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            wait_cnt <= 4'h0;
            pready   <= 1'b0;
            prdata   <= {DATA_WIDTH{1'b0}};
            pslverr  <= 1'b0;
            // Xóa trắng bộ nhớ khi reset (Tùy chọn, giúp Scoreboard không bị rác)
            for (int i = 0; i < MEM_DEPTH; i++) mem[i] <= {DATA_WIDTH{1'b0}};
        end else begin
            // Mặc định hạ các cờ điều khiển bus
            pready  <= 1'b0;
            pslverr <= 1'b0;

            case (current_state)
                IDLE: begin
                    wait_cnt <= 4'h0;
                end

                SETUP: begin
                    // Tạo số chu kỳ đợi ngẫu nhiên dựa trên bit địa chỉ thấp để kiểm thử (Hoặc fix cứng tùy bro)
                    // Ở đây tôi giữ nguyên tư duy tự tạo trễ của bro để testbench có việc làm nhé
                    wait_cycles <= paddr[3:0] % 4; // Trễ ngẫu nhiên từ 0 đến 3 chu kỳ clock
                    wait_cnt    <= 4'h0;
                end

                ACCESS: begin
                    if (wait_cnt < wait_cycles) begin
                        // Chưa đủ chu kỳ đợi -> Tiếp tục đếm, giữ pready = 0
                        wait_cnt <= wait_cnt + 1'b1;
                        pready   <= 1'b0;
                    end else begin
                        // Đã đợi đủ! Bắt đầu chốt dữ liệu (Đọc/Ghi) và dựng pready = 1
                        pready <= 1'b1;

                        // Kiểm tra an toàn vùng biên địa chỉ (Bẫy lỗi Illegal Address)
                        if (paddr >= MEM_DEPTH) begin
                            pslverr <= 1'b1; // Văng lỗi ra bus
                            prdata  <= {DATA_WIDTH{1'b1}}; // Trả về dữ liệu rác toàn bit 1
                        end else begin
                            pslverr <= 1'b0;
                            if (pwrite) begin
                                // Thực hiện Lệnh GHI
                                mem[paddr] <= pwdata;
                            end else begin
                                // Thực hiện Lệnh ĐỌC
                                prdata <= mem[paddr];
                            end
                        end
                    end
                end
            endcase
        end
    end

endmodule