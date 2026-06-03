//==============================================================================
// File          : apb_driver.sv
// Version       : 1.7 (True B2B - Sửa lỗi Handshake & Triệt tiêu Treo Bus)
//==============================================================================

`ifndef APB_DRIVER_SV
`define APB_DRIVER_SV 

class apb_driver extends uvm_driver #(apb_transaction);
    `uvm_component_utils(apb_driver)
    
    virtual apb_if.driver vif;
    bit b2b_mode = 1; // Bật mặc định để chạy với DUT FSM mới

    function new(string name = "apb_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction 

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual apb_if.driver)::get(this,"","vif", vif)) begin
            `uvm_fatal("DRV", "Couldn't get APB interface from config DB")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        reset_bus();
        wait(vif.presetn === 1'b1);
        `uvm_info(get_type_name(), "Driver started after reset released", UVM_MEDIUM);
        
        forever begin 
            seq_item_port.get_next_item(req);
            drive_pipeline(req); // Chuyển sang quản lý dạng chuỗi liên tục
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

    task drive_pipeline(apb_transaction first_tr);
        apb_transaction current_tr;
        apb_transaction next_tr;

        current_tr = first_tr;

        // Kích hoạt SETUP PHASE cho gói tin đầu tiên
        vif.drv_cb.psel    <= 1;
        vif.drv_cb.penable <= 0;
        vif.drv_cb.paddr   <= current_tr.paddr;
        vif.drv_cb.pwrite  <= current_tr.pwrite;
        if (current_tr.pwrite) vif.drv_cb.pwdata <= current_tr.pwdata;

        @(vif.drv_cb); // Kết thúc Setup Phase đầu tiên

        while (current_tr != null) begin
            // ======== ACCESS PHASE =============
            vif.drv_cb.penable <= 1;

            // Chờ DUT phản hồi sẵn sàng (Có cơ chế thoát hiểm nếu quá 1000 chu kỳ tránh treo simulator)
            fork : wait_pready_guard
                begin
                    while (!vif.drv_cb.pready) begin
                        @(vif.drv_cb);
                    end
                end
                begin
                    repeat(1000) @(vif.drv_cb);
                    `uvm_fatal("DRV_TIMEOUT", "DUT hangs! PREADY stays LOW for 1000 cycles at ACCESS phase.")
                end
            join_any
            disable wait_pready_guard;

            // Thu thập phản hồi từ Slave
            if (!current_tr.pwrite) current_tr.prdata = vif.drv_cb.prdata;
            current_tr.pslverr = vif.drv_cb.pslverr;

            // ======== END TRANSACTION & B2B PIPELINE =============
            if (b2b_mode) begin
                seq_item_port.try_next_item(next_tr);

                if (next_tr != null) begin
                    // 🔥 TRUE B2B: Gối đầu pha SETUP của gói sau vào chu kỳ hiện tại
                    vif.drv_cb.penable <= 0;
                    vif.drv_cb.paddr   <= next_tr.paddr;
                    vif.drv_cb.pwrite  <= next_tr.pwrite;
                    if (next_tr.pwrite) vif.drv_cb.pwdata <= next_tr.pwdata;

                    // Giải phóng gói hiện tại hợp lệ về Sequencer
                    if (current_tr != first_tr) begin
                        seq_item_port.item_done();
                    end

                    current_tr = next_tr;
                    @(vif.drv_cb); // Cho phép tín hiệu SETUP có hiệu lực ngoài bus
                end 
                else begin
                    // Hết gói gối đầu -> Trút Bus an toàn về IDLE
                    if (current_tr != first_tr) seq_item_port.item_done();
                    current_tr = null;
                    vif.drv_cb.psel    <= 0;
                    vif.drv_cb.penable <= 0;
                    @(vif.drv_cb);
                end
            end 
            else begin
                // Chế độ Normal
                current_tr = null;
                vif.drv_cb.psel    <= 0;
                vif.drv_cb.penable <= 0;
                @(vif.drv_cb);
            end
        end
    endtask
endclass 

`endif