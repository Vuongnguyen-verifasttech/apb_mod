//==============================================================================
// File          : apb_driver.sv
// Version       : 1.7 (True B2B - Sửa lỗi Handshake Sequencer hoàn chỉnh)
//==============================================================================

`ifndef APB_DRIVER_SV
`define APB_DRIVER_SV 

class apb_driver extends uvm_driver #(apb_transaction);
    `uvm_component_utils(apb_driver)
    
    virtual apb_if.driver vif;
    bit b2b_mode = 1;        // Bật mặc định cho DUT FSM mới

    function new(string name = "apb_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction 

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual apb_if.driver)::get(this,"","vif", vif)) begin
            `uvm_fatal("DRV", "Could not get APB driver interface!")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        reset_bus();
        wait(vif.presetn === 1'b1);
        `uvm_info(get_type_name(), "Driver started after reset", UVM_MEDIUM);
        
        forever begin 
            seq_item_port.get_next_item(req);
            drive_pipeline(req); // Đổi tên task để thể hiện rõ tính chất pipeline
            seq_item_port.item_done();
        end
    endtask

    task reset_bus();
        vif.drv_cb.psel    <= 0;
        vif.drv_cb.penable <= 0;
        vif.drv_cb.pwrite  <= 0;
        vif.drv_cb.paddr   <= 0;
        vif.drv_cb.pwdata  <= 0;
    endtask 

    //==================================================================
    // DRIVE PIPELINE - Quản lý chuỗi B2B liên tục một cách an toàn
    //==================================================================
    task drive_pipeline(apb_transaction first_tr);
        apb_transaction current_tr;
        apb_transaction next_tr;

        current_tr = first_tr;

        // Kích hoạt chu kỳ SETUP cho gói tin đầu tiên trong chuỗi
        vif.drv_cb.psel    <= 1;
        vif.drv_cb.penable <= 0;
        vif.drv_cb.paddr   <= current_tr.paddr;
        vif.drv_cb.pwrite  <= current_tr.pwrite;
        if (current_tr.pwrite) vif.drv_cb.pwdata <= current_tr.pwdata;

        @(vif.drv_cb); // Kết thúc chu kỳ SETUP đầu tiên

        // Vòng lặp quản lý chuỗi gói tin liên tục
        while (current_tr != null) begin
            // -------------------- ACCESS PHASE --------------------
            vif.drv_cb.penable <= 1;

            // Chờ DUT phản hồi pready
            while (!vif.drv_cb.pready) begin
                @(vif.drv_cb);
            end

            // Thu thập phản hồi (Response)
            if (!current_tr.pwrite) 
                current_tr.prdata = vif.drv_cb.prdata;
            current_tr.pslverr = vif.drv_cb.pslverr;

            // -------------------- B2B HANDLING --------------------
            if (b2b_mode) begin
                // "Nhìn trước" gói tiếp theo từ Sequencer
                seq_item_port.try_next_item(next_tr);

                if (next_tr != null) begin
                    // 🔥 TRUE B2B: Biến chu kỳ hiện tại thành pha SETUP của gói sau luôn
                    vif.drv_cb.penable <= 0;
                    vif.drv_cb.paddr   <= next_tr.paddr;
                    vif.drv_cb.pwrite  <= next_tr.pwrite;
                    if (next_tr.pwrite) vif.drv_cb.pwdata <= next_tr.pwdata;

                    // Giải phóng gói hiện tại về Sequencer một cách hợp lệ
                    if (current_tr == first_tr) begin
                        // Gói đầu tiên được quản lý bởi run_phase (bên ngoài task) nên không gọi item_done ở đây
                    end else begin
                        seq_item_port.item_done();
                    end

                    // Chuyển gói tiếp theo thành gói hiện tại và lặp tiếp pha ACCESS
                    current_tr = next_tr;
                    @(vif.drv_cb); // Cho phép tín hiệu SETUP có hiệu lực ngoài Bus trước khi sang nhịp ACCESS sau
                end 
                else begin
                    // Hết gói gối đầu -> Kết thúc chuỗi, giải phóng gói cuối cùng và hạ Bus
                    if (current_tr != first_tr) begin
                        seq_item_port.item_done();
                    end
                    current_tr = null; // Thoát vòng lặp while

                    vif.drv_cb.psel    <= 0;
                    vif.drv_cb.penable <= 0;
                    @(vif.drv_cb);
                end
            end 
            else begin
                // Chế độ Normal Mode (Không chạy B2B)
                current_tr = null;
                vif.drv_cb.psel    <= 0;
                vif.drv_cb.penable <= 0;
                @(vif.drv_cb);
            end
        end
    endtask

endclass 

`endif